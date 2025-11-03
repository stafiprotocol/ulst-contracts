// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {StakeManager} from "../src/StakeManager.sol";
import {AaveStakePool} from "../src/AaveStakePool.sol";
import {LsdToken} from "../src/LsdToken.sol";
import {LsdNetworkFactory} from "../src/LsdNetworkFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILsdNetworkFactory} from "../src/interfaces/ILsdNetworkFactory.sol";
import {MyTest} from "./MyTest.sol";

contract AaveStakeManagerTest is MyTest {
    using SafeERC20 for IERC20;

    address admin = address(1);
    address fakeFactory = address(2);
    address user = address(20251027);

    address aavePoolAddress = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    IERC20 aUSDT = IERC20(0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a); // Aave Ethereum USDT (aEthUSDT)

    StakeManager stakeManager;
    AaveStakePool stakePool;
    LsdToken lsdToken;

    function setUp() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/eth")));

        stakeManager = StakeManager(address(new ERC1967Proxy(address(new StakeManager()), "")));
        stakePool = AaveStakePool(address(new ERC1967Proxy(address(new AaveStakePool()), "")));
        lsdToken = new LsdToken("Test LSD Token", "TLSD");
        lsdToken.initMinter(address(stakeManager));
        assertEq(lsdToken.decimals(), 6);

        address[] memory stablecoins = new address[](1);
        stablecoins[0] = USDT;
        stakePool.initialize(address(stakeManager), aavePoolAddress, admin);
        vm.prank(admin);
        stakeManager.initialize(address(lsdToken), address(stakePool), admin, stablecoins, fakeFactory);
    }

    function test_pause_unstake() public {
        uint256 stakeAmount = 50_000e6;
        airdropUSDT(address(this), stakeAmount);
        IERC20(USDT).safeIncreaseAllowance(address(stakeManager), stakeAmount);
        stakeManager.stake(USDT, stakeAmount);
        uint256 unstakeAmount = stakeAmount;
        lsdToken.approve(address(stakeManager), unstakeAmount);

        assertEq(stakeManager.nextUnstakeIndex(), 1);

        // unstake should be paused at default
        assertEq(stakeManager.isUnstakePaused(), true);

        vm.expectRevert(StakeManager.UnstakePausedError.selector);
        stakeManager.unstake(USDT, unstakeAmount);
        assertEq(lsdToken.balanceOf(address(this)), stakeAmount);

        vm.prank(admin);
        stakeManager.setIsUnstakePaused(false);

        assertEq(stakeManager.isUnstakePaused(), false);
        stakeManager.unstake(USDT, unstakeAmount);
        assertEq(lsdToken.balanceOf(address(this)), 0);
    }

    function test_stake_unstake_withdraw() public {
        vm.prank(admin);
        stakeManager.setIsUnstakePaused(false);

        uint256 stakeAmount = 50_000e6;
        airdropUSDT(user, stakeAmount);

        vm.startPrank(user);
        IERC20(USDT).safeIncreaseAllowance(address(stakeManager), stakeAmount);
        stakeManager.stake(USDT, stakeAmount);

        assertEq(lsdToken.balanceOf(user), stakeAmount);

        uint256 unstakeAmount = stakeAmount;
        lsdToken.approve(address(stakeManager), unstakeAmount);
        stakeManager.unstake(USDT, unstakeAmount);
        assertEq(lsdToken.balanceOf(user), 0);

        uint256 unbondingDuration = stakeManager.unbondingDuration();
        for (uint256 i = 0; i < unbondingDuration; i++) {
            vm.warp(block.timestamp + stakeManager.eraSeconds());
            stakeManager.newEra();
            assertEq(stakeManager.latestEra(), i + 1);
        }

        stakeManager.withdraw();
        assertEq(IERC20(USDT).balanceOf(user), stakeAmount);
        assertEq(IERC20(USDT).balanceOf(address(stakePool)), 0);

        console.log("Test stake_unstake_withdraw completed successfully!");
    }

    function test_newEra() public {
        console.log("stakeManager.owner(): ", stakeManager.owner());
        console.log("address(this): ", address(this));
        vm.startPrank(admin);
        stakeManager.setEraParams(stakeManager.MIN_ERA_SECONDS(), block.timestamp / stakeManager.MIN_ERA_SECONDS());
        stakeManager.setIsUnstakePaused(false);
        vm.stopPrank();

        uint256 stakeAmount = 50_000e6;
        airdropUSDT(user, stakeAmount);

        vm.startPrank(user);
        IERC20(USDT).safeIncreaseAllowance(address(stakeManager), stakeAmount);
        stakeManager.stake(USDT, stakeAmount);

        assertEq(lsdToken.balanceOf(user), stakeAmount);
        assertEq(stakeManager.latestEra(), 0);
        assertEq(stakeManager.currentEra(), 0);
        assertEq(stakeManager.rate(), 1e18);
        assertEq(stakePool.getDelegated(USDT), 0);
        assertEq(IERC20(USDT).balanceOf(address(stakePool)), stakeAmount);

        // 1. delegate to ondo
        vm.warp(block.timestamp + stakeManager.eraSeconds());
        stakeManager.newEra();
        assertEq(stakeManager.latestEra(), 1);
        assertEq(stakeManager.rate(), 1e18);

        // 2 newEra(): query rewards and update rate
        vm.warp(block.timestamp + stakeManager.eraSeconds());
        stakeManager.newEra();
        assertEq(stakeManager.latestEra(), 2);
        assertGt(stakeManager.rate(), 1e18);
        console.log("new rate after rewards: ", stakeManager.rate());

        // 3.1 unstake
        uint256 lstAmount = lsdToken.balanceOf(user);
        lsdToken.approve(address(stakeManager), lstAmount);
        stakeManager.unstake(USDT, lstAmount);
        assertEq(lsdToken.balanceOf(user), 0);
        assertEq(IERC20(USDT).balanceOf(address(stakePool)), 0);

        // 3.2 redeem from aave
        vm.warp(block.timestamp + stakeManager.eraSeconds());
        stakeManager.newEra();
        assertGt(IERC20(USDT).balanceOf(address(stakePool)), stakeAmount);
        assertEq(stakeManager.latestEra(), 3);

        // 4.1 pass unbonding duration
        for (uint256 i = 1; i < stakeManager.unbondingDuration(); i++) {
            vm.warp(block.timestamp + stakeManager.eraSeconds());
            stakeManager.newEra();
            assertEq(stakeManager.latestEra(), i + 3);
        }

        // 4.2 withdraw
        stakeManager.withdraw();
        assertGt(IERC20(USDT).balanceOf(user), stakeAmount);
        assertEq(IERC20(USDT).balanceOf(address(stakePool)), 0);

        console.log("Test newEra completed successfully!");
    }
}
