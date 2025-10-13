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
import {ITestUSDC} from "./testUSDC.sol";
import {MyTest} from "./MyTest.sol";

contract StakePoolTest is MyTest {
    using SafeERC20 for IERC20;

    address admin = address(1);
    address manager = address(2);
    StakePool stakePool;
    uint256 usdcAmount = 50_000e6;

    function setUp() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/eth")));

        stakePool = StakePool(address(new ERC1967Proxy(address(new StakePool()), "")));
        stakePool.initialize(manager, OUSG_INSTANT_MANAGER, ONDO_ORACLE, admin);
        airdropUSDC(address(stakePool), usdcAmount);
        mockIDRegistry();
        mockOracle();
    }

    function test_delegate_undelegate_withdraw() public {
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), usdcAmount);
        assertEq(stakePool.getDelegated(USDC), 0);

        vm.startPrank(manager);
        stakePool.delegate(USDC, usdcAmount);
        assertGe(stakePool.getDelegated(USDC), usdcAmount - 100); // 100 is for calculation loss
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), 0);

        stakePool.undelegate(USDC, usdcAmount);
        assertEq(stakePool.getDelegated(USDC), 0);

        uint256 receivedUsdcAmount = IERC20(USDC).balanceOf(address(stakePool));
        assertGe(receivedUsdcAmount + stakePool.totalMissingUnbondingFee(USDC), usdcAmount);

        // pay missing unbonding fee
        address[] memory stablecoins = new address[](1);
        stablecoins[0] = USDC;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = stakePool.totalMissingUnbondingFee(USDC);
        IERC20(USDC).safeIncreaseAllowance(address(stakePool), stakePool.totalMissingUnbondingFee(USDC));
        stakePool.payMissingUnbondingFee(stablecoins, amounts);
        assertEq(stakePool.totalMissingUnbondingFee(USDC), 0);
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), usdcAmount);

        stakePool.withdrawForStaker(USDC, address(this), usdcAmount);
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), 0);
        assertGe(IERC20(USDC).balanceOf(address(this)), usdcAmount);

        console.log("Test completed successfully!");
    }

    function test_stake_pool_with_pyusd() public {
        airdropPYUSD(address(stakePool), usdcAmount);
        assertEq(IERC20(PYUSD).balanceOf(address(stakePool)), usdcAmount);
        assertEq(stakePool.getDelegated(PYUSD), 0);

        vm.startPrank(manager);
        stakePool.delegate(PYUSD, usdcAmount);
        assertGe(stakePool.getDelegated(PYUSD), usdcAmount - 100); // 100 is for calculation loss
        assertEq(IERC20(PYUSD).balanceOf(address(stakePool)), 0);

        stakePool.undelegate(USDC, usdcAmount);
        uint256 receivedUsdcAmount = IERC20(USDC).balanceOf(address(stakePool));
        assertGe(receivedUsdcAmount, usdcAmount - 100); // 100 is for calculation loss
        assertEq(stakePool.getDelegated(USDC), 0);

        stakePool.withdrawForStaker(USDC, address(this), receivedUsdcAmount);
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), 0);
        assertGe(IERC20(USDC).balanceOf(address(this)), receivedUsdcAmount);

        console.log("Test completed successfully!");
    }

    function test_stake_pool_with_rewards() public {
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), usdcAmount);
        assertEq(stakePool.getDelegated(USDC), 0);

        vm.startPrank(manager);
        stakePool.delegate(USDC, usdcAmount);

        // add rewards by increasing rwa token price
        console.log("Delegated amount before rewards: ", stakePool.getDelegated(USDC));
        mockOndoOracle.setAssetPrice(ondoInstantManager.rwaToken(), 0x6194f8a6903775000);
        assertGt(stakePool.getDelegated(USDC), usdcAmount);
        uint256 usdcAmountAfterRewards = stakePool.getDelegated(USDC);
        console.log("Delegated amount after rewards: ", usdcAmountAfterRewards);

        stakePool.undelegate(USDC, usdcAmountAfterRewards);
        uint256 receivedUsdcAmount = IERC20(USDC).balanceOf(address(stakePool));
        assertGe(receivedUsdcAmount, usdcAmountAfterRewards - 100); // 100 is for calculation loss
        assertEq(stakePool.getDelegated(USDC), 0);

        console.log("Rewards amount: ", usdcAmountAfterRewards - usdcAmount);

        console.log("Test test_stake_pool_with_rewards completed successfully!");
    }
}
