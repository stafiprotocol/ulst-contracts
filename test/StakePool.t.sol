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

interface IOndoIDRegistry {
    function getRegisteredID(address rwaToken, address user) external view returns (bytes32 userID);
}

contract MockIOndoIDRegistry is IOndoIDRegistry {
    function getRegisteredID(address, /* rwaToken */ address /* user */ ) external pure returns (bytes32 userID) {
        return bytes32(0x4f55534700000000ea17b6d53c96e90000000000000000000000000000000000);
    }
}

contract FactoryTest is Test {
    using SafeERC20 for IERC20;

    address admin = address(1);
    address manager = address(2);

    // Real contract addresses for production testing
    address constant OUSG_INSTANT_MANAGER = 0x93358db73B6cd4b98D89c8F5f230E81a95c2643a;
    address constant ONDO_ORACLE = 0x9Cad45a8BF0Ed41Ff33074449B357C7a1fAb4094;
    address constant ONDO_Registry = 0xcf6958D69d535FD03BD6Df3F4fe6CDcd127D97df;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/eth")));
    }

    function test_stake_pool() public {
        uint256 usdcAmount = 50_000e6;
        StakePool stakePool = StakePool(address(new ERC1967Proxy(address(new StakePool()), "")));
        {
            // mint 500 USDC to stake pool for testing
            ITestUSDC usdc = ITestUSDC(USDC);
            vm.prank(usdc.masterMinter());
            usdc.configureMinter(address(this), type(uint256).max);
            usdc.mint(address(stakePool), usdcAmount);
        }

        {
            // Mock registration for stake pool
            IOndoIDRegistry mockRegistryImpl = new MockIOndoIDRegistry();
            vm.etch(ONDO_Registry, address(mockRegistryImpl).code);
            address rwaToken = IOndoInstantManager(OUSG_INSTANT_MANAGER).rwaToken();
            IOndoIDRegistry(ONDO_Registry).getRegisteredID(rwaToken, address(stakePool));
        }

        stakePool.initialize(manager, OUSG_INSTANT_MANAGER, ONDO_ORACLE, admin);

        assertEq(IERC20(USDC).balanceOf(address(stakePool)), usdcAmount);
        assertEq(stakePool.getDelegated(), 0);

        vm.startPrank(manager);
        stakePool.delegate(USDC, usdcAmount);
        assertGt(stakePool.getDelegated(), 0);
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), 0);

        stakePool.undelegate(USDC, stakePool.getDelegated());
        uint256 receivedUsdcAmount = IERC20(USDC).balanceOf(address(stakePool));
        assertGe(receivedUsdcAmount, usdcAmount - 100); // 100 is for calculation loss
        assertEq(stakePool.getDelegated(), 0);

        stakePool.withdrawForStaker(USDC, address(this), receivedUsdcAmount);
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), 0);
        assertGe(IERC20(USDC).balanceOf(address(this)), receivedUsdcAmount);

        console.log("Test completed successfully!");
    }
}
