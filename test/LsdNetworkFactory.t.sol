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

contract FactoryTest is MyTest {
    using SafeERC20 for IERC20;

    LsdNetworkFactory public factory;
    address admin = address(1);

    function setUp() public {
        vm.createSelectFork(vm.envOr("RPC_URL", string("https://1rpc.io/eth")));

        // Deploy logic contracts
        StakeManager stakeManagerLogic = new StakeManager();
        StakePool stakePoolLogic = new StakePool();
        LsdNetworkFactory factoryLogic = new LsdNetworkFactory();

        // Deploy factory proxy
        factory = LsdNetworkFactory(address(new ERC1967Proxy(address(factoryLogic), "")));

        // Initialize factory with all required parameters
        factory.initialize(admin, address(stakeManagerLogic), address(stakePoolLogic));
    }

    function test_create() public {
        // Test factory admin is set correctly
        assertEq(factory.factoryAdmin(), admin);

        // Test creating a new LSD network
        string memory tokenName = "Test LSD Token";
        string memory tokenSymbol = "TLSD";

        address[] memory stablecoins = new address[](2);
        stablecoins[0] = USDC;
        stablecoins[1] = PYUSD;
        // Create the LSD network using real contract addresses
        factory.createLsdNetwork(tokenName, tokenSymbol, OUSG_INSTANT_MANAGER, ONDO_ORACLE, stablecoins);

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

        console.log("Test factory.createLsdNetwork completed successfully!");
    }
}
