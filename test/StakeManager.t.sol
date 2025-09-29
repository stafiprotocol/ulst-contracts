// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {StakeManager} from "../src/StakeManager.sol";
import {StakePool} from "../src/StakePool.sol";
import {LsdToken} from "../src/LsdToken.sol";
import {LsdNetworkFactory} from "../src/LsdNetworkFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IOndoInstantManager, IOndoOracle} from "../src/interfaces/Ondo.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILsdNetworkFactory} from "../src/interfaces/ILsdNetworkFactory.sol";
import {MyTest} from "./MyTest.sol";

contract StakeManagerTest is MyTest {
    using SafeERC20 for IERC20;

    LsdNetworkFactory public factory;
    address admin = address(1);

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/eth")));

        // Deploy logic contracts
        StakeManager stakeManagerLogic = new StakeManager();
        StakePool stakePoolLogic = new StakePool();
        LsdNetworkFactory factoryLogic = new LsdNetworkFactory();

        // Deploy factory proxy
        factory = LsdNetworkFactory(address(new ERC1967Proxy(address(factoryLogic), "")));

        // Initialize factory with all required parameters
        factory.initialize(
            admin, OUSG_INSTANT_MANAGER, ONDO_ORACLE, USDC, address(stakeManagerLogic), address(stakePoolLogic)
        );

        mockIDRegistry();
        mockOracle();
    }

    function test_stake_unstake_withdraw() public {
        address[] memory stablecoins = new address[](2);
        stablecoins[0] = USDC;
        stablecoins[1] = PYUSD;
        factory.createLsdNetwork("Test LSD Token", "TLSD", OUSG_INSTANT_MANAGER, ONDO_ORACLE, stablecoins);
        address[] memory createdTokens = factory.lsdTokensOfCreater(address(this));
        assertEq(createdTokens.length, 1);

        ILsdNetworkFactory.NetworkContracts memory contracts = factory.getNetworkContracts(createdTokens[0]);
        LsdToken lsdToken = LsdToken(contracts._lsdToken);
        StakeManager stakeManager = StakeManager(contracts._stakeManager);
        StakePool stakePool = StakePool(contracts._stakePool);

        uint256 stakeAmount = 50_000e6;
        airdropUSDC(address(this), stakeAmount);

        IERC20(USDC).safeIncreaseAllowance(address(stakeManager), stakeAmount);
        stakeManager.stake(USDC, stakeAmount);

        assertEq(lsdToken.balanceOf(address(this)), stakeAmount);

        uint256 unstakeAmount = stakeAmount;
        lsdToken.approve(address(stakeManager), unstakeAmount);
        stakeManager.unstake(USDC, unstakeAmount);
        assertEq(lsdToken.balanceOf(address(this)), 0);

        uint256 unbondingDuration = stakeManager.unbondingDuration();
        for (uint256 i = 0; i < unbondingDuration; i++) {
            vm.warp(block.timestamp + stakeManager.eraSeconds());
            stakeManager.newEra();
            assertEq(stakeManager.latestEra(), i + 1);
        }

        stakeManager.withdraw();
        assertEq(IERC20(USDC).balanceOf(address(this)), stakeAmount);
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), 0);

        console.log("Test stake_unstake_withdraw completed successfully!");
    }

    function test_newEra() public {
        address[] memory stablecoins = new address[](2);
        stablecoins[0] = USDC;
        stablecoins[1] = PYUSD;
        factory.createLsdNetwork("Test LSD Token", "TLSD", OUSG_INSTANT_MANAGER, ONDO_ORACLE, stablecoins);
        address[] memory createdTokens = factory.lsdTokensOfCreater(address(this));
        assertEq(createdTokens.length, 1);

        ILsdNetworkFactory.NetworkContracts memory contracts = factory.getNetworkContracts(createdTokens[0]);
        LsdToken lsdToken = LsdToken(contracts._lsdToken);
        StakeManager stakeManager = StakeManager(contracts._stakeManager);
        console.log("stakeManager.owner(): ", stakeManager.owner());
        console.log("address(this): ", address(this));
        stakeManager.setEraParams(stakeManager.MIN_ERA_SECONDS(), block.timestamp / stakeManager.MIN_ERA_SECONDS());

        StakePool stakePool = StakePool(contracts._stakePool);

        uint256 stakeAmount = 50_000e6;
        airdropUSDC(address(this), stakeAmount);

        IERC20(USDC).safeIncreaseAllowance(address(stakeManager), stakeAmount);
        stakeManager.stake(USDC, stakeAmount);

        assertEq(lsdToken.balanceOf(address(this)), stakeAmount);
        assertEq(stakeManager.latestEra(), 0);
        assertEq(stakeManager.currentEra(), 0);
        assertEq(stakeManager.rate(), 1e18);
        assertEq(stakePool.getDelegated(USDC), 0);
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), stakeAmount);

        // 1. delegate to ondo
        vm.warp(block.timestamp + stakeManager.eraSeconds());
        stakeManager.newEra();
        assertEq(stakeManager.latestEra(), 1);
        assertEq(stakeManager.rate(), 1e18);

        // 2.1 add rewards by increasing rwa token price
        mockOndoOracle.setAssetPrice(ondoInstantManager.rwaToken(), 0x7194f8a6903775000);

        // 2.2 newEra(): query rewards and update rate
        vm.warp(block.timestamp + stakeManager.eraSeconds());
        stakeManager.newEra();
        assertEq(stakeManager.latestEra(), 2);
        assertGt(stakeManager.rate(), 1e18);
        console.log("new rate after rewards: ", stakeManager.rate());

        // 3.1 unstake
        uint256 lstAmount = lsdToken.balanceOf(address(this));
        lsdToken.approve(address(stakeManager), lstAmount);
        stakeManager.unstake(PYUSD, lstAmount);
        assertEq(lsdToken.balanceOf(address(this)), 0);
        assertEq(IERC20(PYUSD).balanceOf(address(stakePool)), 0);

        // 3.2 redeem from ondo
        vm.warp(block.timestamp + stakeManager.eraSeconds());
        stakeManager.newEra();
        assertGt(IERC20(PYUSD).balanceOf(address(stakePool)), stakeAmount);
        assertEq(stakeManager.latestEra(), 3);

        // 3.3 pay missing unbonding fee
        {
            uint256 missingAmount = stakePool.totalMissingUnbondingFee(PYUSD);
            if (missingAmount > 0) {
                airdropPYUSD(address(this), missingAmount);
                IERC20(PYUSD).safeIncreaseAllowance(address(stakePool), missingAmount);

                address[] memory _stablecoins = new address[](1);
                _stablecoins[0] = PYUSD;
                uint256[] memory _amounts = new uint256[](1);
                _amounts[0] = missingAmount;
                stakePool.payMissingUnbondingFee(_stablecoins, _amounts);
            }
        }
        
        // 4.1 pass unbonding duration
        for (uint256 i = 1; i < stakeManager.unbondingDuration(); i++) {
            vm.warp(block.timestamp + stakeManager.eraSeconds());
            stakeManager.newEra();
            assertEq(stakeManager.latestEra(), i + 3);
        }
        // 4.2 withdraw
        stakeManager.withdraw();
        assertGt(IERC20(PYUSD).balanceOf(address(this)), stakeAmount);
        assertLe(IERC20(PYUSD).balanceOf(address(stakePool)), 100);

        console.log("Test newEra completed successfully!");
    }
    
    function test_unbondingFee() public {
        address[] memory stablecoins = new address[](2);
        stablecoins[0] = USDC;
        stablecoins[1] = PYUSD;
        factory.createLsdNetwork("Test LSD Token", "TLSD", OUSG_INSTANT_MANAGER, ONDO_ORACLE, stablecoins);
        address[] memory createdTokens = factory.lsdTokensOfCreater(address(this));
        assertEq(createdTokens.length, 1);

        ILsdNetworkFactory.NetworkContracts memory contracts = factory.getNetworkContracts(createdTokens[0]);
        LsdToken lsdToken = LsdToken(contracts._lsdToken);
        StakeManager stakeManager = StakeManager(contracts._stakeManager);
        StakePool stakePool = StakePool(contracts._stakePool);
        stakeManager.setUnbondingFee(1e14); // 0.01%

        uint256 stakeAmount = 50_000e6;
        airdropUSDC(address(this), stakeAmount);

        IERC20(USDC).safeIncreaseAllowance(address(stakeManager), stakeAmount);
        stakeManager.stake(USDC, stakeAmount);

        assertEq(lsdToken.balanceOf(address(this)), stakeAmount);

        uint256 unstakeAmount = stakeAmount;
        lsdToken.approve(address(stakeManager), unstakeAmount);
        stakeManager.unstake(USDC, unstakeAmount);
        assertEq(lsdToken.balanceOf(address(this)), 0);

        uint256 unbondingDuration = stakeManager.unbondingDuration();
        for (uint256 i = 0; i < unbondingDuration; i++) {
            vm.warp(block.timestamp + stakeManager.eraSeconds());
            stakeManager.newEra();
            assertEq(stakeManager.latestEra(), i + 1);
        }

        stakeManager.withdraw();
        uint256 unbondingFee = stakeAmount * 1e14 / 1e18;
        console.log("unbondingFee: ", unbondingFee);
        assertEq(IERC20(USDC).balanceOf(address(this)), stakeAmount - unbondingFee);
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), unbondingFee);

        console.log("Test unbondingFee completed successfully!");
    }
}
