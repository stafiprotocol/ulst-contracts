// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {AaveStakePool} from "../src/AaveStakePool.sol";
import {IAavePool} from "../src/interfaces/Aave.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AaveErrors, ReserveDataLegacy} from "../src/interfaces/Aave.sol";
import {MyTest} from "./MyTest.sol";

contract AaveStakePoolTest is MyTest {
    using SafeERC20 for IERC20;

    address admin = address(1);
    address manager = address(2);
    address user = address(20251027);
    AaveStakePool stakePool;
    address aavePoolAddress = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    function test_sepolia_aave_delegate_undelegate_withdraw() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/sepolia")));

        aavePoolAddress = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
        user = 0xa9b8af5C53E6282fB469297091A33B08B5AC40B7;
        uint256 delegationAmount = 1_000_000;

        stakePool = AaveStakePool(address(new ERC1967Proxy(address(new AaveStakePool()), "")));
        stakePool.initialize(manager, aavePoolAddress, admin);

        address LINK = 0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5;
        address aLINK = 0x3FfAf50D4F4E96eB78f2407c090b72e86eCaed24;

        vm.prank(user);
        IERC20(LINK).safeTransfer(address(stakePool), delegationAmount);

        _delegate_undelegate_withdraw(LINK, aLINK, delegationAmount);
    }

    function test_sepolia_usdt_exceed_supply_cap() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/sepolia")), 9548875);

        user = 0xa9b8af5C53E6282fB469297091A33B08B5AC40B7;
        IAavePool aavePool = IAavePool(0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951);
        address USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;

        ReserveDataLegacy memory reserveData = aavePool.getReserveData(USDT);
        console.log("aToken address:", reserveData.aTokenAddress);

        vm.startPrank(user);
        vm.expectRevert(bytes(AaveErrors.SUPPLY_CAP_EXCEEDED));
        aavePool.supply(USDT, 1_000_000, user, 0);
    }

    function test_mainnet_aave_delegate_undelegate_withdraw() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/eth")));
        address aUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a; // Aave Ethereum USDT (aEthUSDT)
        uint256 usdtAmount = 50_000e6;

        stakePool = AaveStakePool(address(new ERC1967Proxy(address(new AaveStakePool()), "")));
        stakePool.initialize(manager, aavePoolAddress, admin);
        airdropUSDT(address(stakePool), usdtAmount);

        _delegate_undelegate_withdraw(USDT, aUSDT, usdtAmount);
    }

    function _delegate_undelegate_withdraw(address asset, address assetToken, uint256 delegationAmount) public {
        vm.prank(admin);

        assertEq(IERC20(asset).balanceOf(address(stakePool)), delegationAmount);
        assertEq(stakePool.getDelegated(asset), 0);

        vm.startPrank(manager);
        stakePool.delegate(asset, delegationAmount);
        assertGe(stakePool.getDelegated(asset), delegationAmount - 100); // 100 is for calculation loss

        vm.warp(block.timestamp + 1 hours);
        assertGe(IERC20(assetToken).balanceOf(address(stakePool)), delegationAmount - 100);

        stakePool.undelegate(asset, IERC20(assetToken).balanceOf(address(stakePool)));
        uint256 principalAndRewardUsdtAmount = IERC20(asset).balanceOf(address(stakePool));
        assertGt(principalAndRewardUsdtAmount, delegationAmount);
        assertEq(stakePool.getDelegated(asset), 0);

        stakePool.withdrawForStaker(asset, address(this), principalAndRewardUsdtAmount);
        assertEq(IERC20(asset).balanceOf(address(stakePool)), 0);
        assertGe(IERC20(asset).balanceOf(address(this)), principalAndRewardUsdtAmount);

        console.log("Test completed successfully!");
    }
}
