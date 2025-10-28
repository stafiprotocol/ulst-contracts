// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {Test} from "forge-std/Test.sol";
import {ITestUSDC} from "./testUSDC.sol";
import "./ondoErrors.sol";
import {IOndoInstantManager, IOndoOracle} from "../src/interfaces/Ondo.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract MyTest is Test {
    using SafeERC20 for IERC20;

    address constant OUSG_INSTANT_MANAGER = 0x93358db73B6cd4b98D89c8F5f230E81a95c2643a;
    address constant ONDO_Registry = 0xcf6958D69d535FD03BD6Df3F4fe6CDcd127D97df;
    address constant ONDO_ORACLE = 0x9Cad45a8BF0Ed41Ff33074449B357C7a1fAb4094;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant PYUSD = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    IOndoInstantManager public ondoInstantManager = IOndoInstantManager(OUSG_INSTANT_MANAGER);

    function airdropUSDC(address to, uint256 amount) internal {
        ITestUSDC usdc = ITestUSDC(USDC);
        if (block.chainid == 1) {
            vm.prank(usdc.masterMinter());
            usdc.configureMinter(address(this), type(uint256).max);
            usdc.mint(to, amount);
            return;
        }

        if (block.chainid == 11155111) {
            vm.prank(usdc.owner());
            usdc.mint(to, amount);
            return;
        }
    }

    function airdropUSDT(address to, uint256 amount) internal {
        ITestUSDT usdt = ITestUSDT(USDT);
        vm.prank(usdt.owner());
        if (block.chainid == 1) {
            usdt.issue(amount);
            vm.prank(usdt.owner());
            IERC20(USDT).safeTransfer(to, amount);
            return;
        }
        if (block.chainid == 11155111) {
            usdt.mint(to, amount);
        }
    }

    function airdropPYUSD(address to, uint256 amount) internal {
        ITestPYUSD pyusd = ITestPYUSD(PYUSD);
        ISupplyControl supplyControl = pyusd.supplyControl();
        vm.prank(supplyControl.getAllSupplyControllerAddresses()[0]);
        pyusd.mint(to, amount);
    }

    function mockIDRegistry() internal {
        IOndoIDRegistry mockRegistryImpl = new MockIOndoIDRegistry();
        vm.etch(ONDO_Registry, address(mockRegistryImpl).code);
    }

    MockOndoOracle public mockOndoOracle;

    function mockOracle() internal {
        IOndoOracle ondoOracleImpl = new MockOndoOracle();
        vm.etch(ONDO_ORACLE, address(ondoOracleImpl).code);
        mockOndoOracle = MockOndoOracle(ONDO_ORACLE);
        mockOndoOracle.setAssetPrice(USDC, 1000000000000000000);
        mockOndoOracle.setAssetPrice(PYUSD, 1000000000000000000);
        mockOndoOracle.setAssetPrice(ondoInstantManager.rwaToken(), 0x619234f3380033000);
    }
}

interface ISupplyControl {
    function getAllSupplyControllerAddresses() external view returns (address[] memory);
}

interface ITestUSDT {
    function issue(uint256 amount) external;
    function mint(address to, uint256 amount) external; // on sepolia
    function owner() external view returns (address);
}

interface ITestPYUSD {
    function mint(address to, uint256 amount) external;
    function supplyControl() external view returns (ISupplyControl);

    error AccountMissingSupplyControllerRole(address account);
    error AccountAlreadyHasSupplyControllerRole(address account);
    error CannotMintToAddress(address supplyController, address mintToAddress);
    error CannotBurnFromAddress(address supplyController, address burnFromAddress);
    error CannotAddDuplicateAddress(address addressToAdd);
    error CannotRemoveNonExistantAddress(address addressToRemove);
    error ZeroAddress();
}

interface IOndoIDRegistry {
    function getRegisteredID(address rwaToken, address user) external view returns (bytes32 userID);
}

contract MockIOndoIDRegistry is IOndoIDRegistry {
    function getRegisteredID(
        address,
        /* rwaToken */
        address /* user */
    )
        external
        pure
        returns (bytes32 userID)
    {
        return bytes32(0x4f55534700000000ea17b6d53c96e90000000000000000000000000000000000);
    }
}

contract MockOndoOracle is IOndoOracle {
    mapping(address => uint256) public assetPrices;

    function setAssetPrice(address asset, uint256 price) external {
        assetPrices[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return assetPrices[asset];
    }
}
