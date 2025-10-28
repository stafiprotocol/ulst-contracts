// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {AaveStakePool} from "../src/AaveStakePool.sol";
import {IAavePool} from "../src/interfaces/Aave.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MyTest} from "./MyTest.sol";

contract AaveStakePoolTest22 is MyTest {
    using SafeERC20 for IERC20;

    address admin = address(1);
    address manager = address(2);
    address user = address(20251027);
    AaveStakePool stakePool;
    uint256 usdtAmount = 50_000e6;
    address test1111 = address(1111);
    address aavePoolAddress = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    IERC20 aUSDT = IERC20(0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a); // Aave Ethereum USDT (aEthUSDT)

    function test_sepolia_aave_delegate_undelegate_withdraw() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/sepolia")));

        aavePoolAddress = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
        // {
        //     // test usdc
        //     USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
        //     airdropUSDC(user, usdtAmount);
        //     IAavePool aavePool = IAavePool(aavePoolAddress);
        //     IERC20(USDC).safeIncreaseAllowance(address(aavePool), usdtAmount);
        //     aavePool.supply(USDC, usdtAmount, user, 0);
        // }

        // USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
        // aUSDT = IERC20(0x9844386d29EEd970B9F6a2B9a676083b0478210e);

        // airdropUSDT(user, usdtAmount);
        // IAavePool aavePool = IAavePool(aavePoolAddress);

        // IERC20(USDT).safeIncreaseAllowance(address(aavePool), usdtAmount);
        // aavePool.supply(USDT, usdtAmount, user, 0);

        // _delegate_undelegate_withdraw();
    }

    function test_mainnet_aave_delegate_undelegate_withdraw() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/eth")));
        _delegate_undelegate_withdraw();
    }

    function _delegate_undelegate_withdraw() public {
        stakePool = AaveStakePool(address(new ERC1967Proxy(address(new AaveStakePool()), "")));
        stakePool.initialize(manager, aavePoolAddress, admin);
        airdropUSDT(address(stakePool), usdtAmount);
        vm.prank(admin);
        stakePool.setStablecoinToAaveToken(USDT, address(aUSDT));

        assertEq(IERC20(USDT).balanceOf(address(stakePool)), usdtAmount);
        assertEq(stakePool.getDelegated(USDT), 0);

        vm.startPrank(manager);
        stakePool.delegate(USDT, usdtAmount);
        assertGe(stakePool.getDelegated(USDT), usdtAmount - 100); // 100 is for calculation loss

        vm.warp(block.timestamp + 1 hours);
        assertGe(aUSDT.balanceOf(address(stakePool)), usdtAmount - 100);

        stakePool.undelegate(USDT, aUSDT.balanceOf(address(stakePool)));
        uint256 principalAndRewardUsdtAmount = IERC20(USDT).balanceOf(address(stakePool));
        assertGt(principalAndRewardUsdtAmount, usdtAmount);
        assertEq(stakePool.getDelegated(USDT), 0);

        stakePool.withdrawForStaker(USDT, address(this), principalAndRewardUsdtAmount);
        assertEq(IERC20(USDT).balanceOf(address(stakePool)), 0);
        assertGe(IERC20(USDT).balanceOf(address(this)), principalAndRewardUsdtAmount);

        console.log("Test completed successfully!");
    }
}
