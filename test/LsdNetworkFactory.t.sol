// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/Test.sol";
import "./ondoErrors.sol";
import {StakeManager} from "../src/StakeManager.sol";
import {StakePool} from "../src/StakePool.sol";
import {LsdToken} from "../src/LsdToken.sol";
import {LsdNetworkFactory} from "../src/LsdNetworkFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IOndoInstantManager, IOndoOracle} from "../src/interfaces/Ondo.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILsdNetworkFactory} from "../src/interfaces/ILsdNetworkFactory.sol";
import {ITestUSDC} from "./testUSDC.sol";

contract FactoryTest is Test {
    using SafeERC20 for IERC20;

    LsdNetworkFactory public factory;
    address admin = address(1);

    // Real contract addresses for production testing
    address constant OUSG_INSTANT_MANAGER = 0x93358db73B6cd4b98D89c8F5f230E81a95c2643a;
    address constant ONDO_ORACLE = 0x9Cad45a8BF0Ed41Ff33074449B357C7a1fAb4094;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/eth")), 22269346);

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
    }

    function test_create() public {
        // Test factory admin is set correctly
        assertEq(factory.factoryAdmin(), admin);

        // Test creating a new LSD network
        string memory tokenName = "Test LSD Token";
        string memory tokenSymbol = "TLSD";

        // Create the LSD network using real contract addresses
        factory.createLsdNetwork(tokenName, tokenSymbol, OUSG_INSTANT_MANAGER, ONDO_ORACLE, USDC);

        // Verify the LSD token was created and stored
        address[] memory createdTokens = factory.lsdTokensOfCreater(address(this));
        assertEq(createdTokens.length, 1);

        address lsdTokenAddr = createdTokens[0];
        LsdToken lsdToken = LsdToken(lsdTokenAddr);

        // Verify token name and symbol
        assertEq(lsdToken.name(), tokenName);
        assertEq(lsdToken.symbol(), tokenSymbol);

        // Get network contracts
        ILsdNetworkFactory.NetworkContracts memory contracts = factory.getNetworkContracts(lsdTokenAddr);
        address stakeManagerAddr = contracts._stakeManager;
        address stakePoolAddr = contracts._stakePool;

        console.log("StakeManager: %s", stakeManagerAddr);
        console.log("StakePool: %s", stakePoolAddr);
        console.log("LSD Token: %s", lsdTokenAddr);

        // Verify contracts are deployed
        assertTrue(stakeManagerAddr != address(0));
        assertTrue(stakePoolAddr != address(0));
        assertTrue(lsdTokenAddr != address(0));

        // Test basic functionality
        StakeManager stakeManager = StakeManager(stakeManagerAddr);
        StakePool stakePool = StakePool(payable(stakePoolAddr));

        // Verify initial state
        assertEq(address(stakePool).balance, 0);
        assertEq(stakeManager.latestEra(), 0);
        assertEq(stakeManager.currentEra(), 0);
        assertEq(stakeManager.rate(), 1e18);

        uint256 stakeAmount = 100e6;
        {
            // mint 100 USDC to stake pool for testing
            ITestUSDC usdc = ITestUSDC(USDC);
            vm.prank(usdc.masterMinter());
            usdc.configureMinter(address(this), type(uint256).max);
            usdc.mint(address(this), stakeAmount);
        }

        // Test staking functionality
        IERC20(USDC).safeIncreaseAllowance(address(stakeManager), stakeAmount);
        stakeManager.stake(stakeAmount);

        // Verify staking results
        assertEq(lsdToken.balanceOf(address(this)), stakeAmount);
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), stakeAmount);
        assertEq(stakeManager.latestEra(), 0);
        assertEq(stakeManager.currentEra(), 0);
        assertEq(stakeManager.rate(), 1e18);

        // Test unstaking functionality
        uint256 unstakeAmount = stakeAmount;
        lsdToken.approve(address(stakeManager), unstakeAmount);
        stakeManager.unstake(unstakeAmount);

        // Verify unstaking results
        assertEq(lsdToken.balanceOf(address(this)), stakeAmount - unstakeAmount);

        console.log("Unbonding duration: ", stakeManager.unbondingDuration());
        console.log("Era seconds: ", stakeManager.eraSeconds());

        vm.warp(block.timestamp + stakeManager.unbondingDuration() * stakeManager.eraSeconds() + 1);

        // Test withdrawal
        uint256 preBalance = IERC20(USDC).balanceOf(address(stakePool));
        stakeManager.withdraw();
        uint256 postBalance = IERC20(USDC).balanceOf(address(stakePool));
        console.log("Pre balance: ", preBalance);
        console.log("Post balance: ", postBalance);

        // Verify withdrawal
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), 0);
        assertEq(preBalance - unstakeAmount, postBalance);

        console.log("Test completed successfully!");
    }
}
