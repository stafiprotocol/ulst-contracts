// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/Test.sol";
import {StakeManager} from "../src/StakeManager.sol";
import {StakePool} from "../src/StakePool.sol";
import {LsdToken} from "../src/LsdToken.sol";
import {LsdNetworkFactory} from "../src/LsdNetworkFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IGovInstantManager} from "../src/interfaces/IGovInstantManager.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGovOracle} from "../src/interfaces/IGovOracle.sol";
import {ILsdNetworkFactory} from "../src/interfaces/ILsdNetworkFactory.sol";

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

        // Deploy logic contracts
        StakeManager stakeManagerLogic = new StakeManager();
        StakePool stakePoolLogic = new StakePool();
        LsdNetworkFactory factoryLogic = new LsdNetworkFactory();

        // Deploy factory proxy
        factory = LsdNetworkFactory(address(new ERC1967Proxy(address(factoryLogic), "")));

        // Initialize factory with all required parameters
        factory.initialize(
            admin,
            OUSG_INSTANT_MANAGER,
            ONDO_ORACLE,   
            USDC,     
            address(stakeManagerLogic),
            address(stakePoolLogic)   
        );
    }

    event Stake(address staker, address poolAddress, uint256 tokenAmount, uint256 lsdTokenAmount);
    event Settle(uint256 indexed era, address indexed pool);
    event Delegate(address pool, address validator, uint256 amount);

    error OutOfFund();
    error NotVoter();
    error ZeroWithdrawAmount();

    // forge test --fork-url=$RPC_URL --block-number 23309397 --match-test test_create --match-path ./test/LsdNetworkFactory.t.sol -vvvvv 
    function test_create() public {
        // Test factory admin is set correctly
        assertEq(factory.factoryAdmin(), admin);
        
        // Test creating a new LSD network
        string memory tokenName = "Test LSD Token";
        string memory tokenSymbol = "TLSD";
        address networkAdmin = address(this);

        // Create the LSD network using real contract addresses
        factory.createLsdNetwork(
            tokenName, 
            tokenSymbol, 
            OUSG_INSTANT_MANAGER, 
            ONDO_ORACLE
        );

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

        address whale = 0x22A460a317dc399247E1f33fB3bFBf0daa5b965e;
        console.log("Whale USDC balance: ", IERC20(USDC).balanceOf(whale));

        // Impersonate whale
        vm.startPrank(whale);
        // Test staking functionality
        uint256 stakeAmount = 4_000_000_000;
        IERC20(USDC).safeIncreaseAllowance(address(stakeManager), 10**28);
        stakeManager.stake(USDC, stakeAmount);

        // Verify staking results
        assertEq(lsdToken.balanceOf(whale), stakeAmount);
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), stakeAmount);
        assertEq(stakeManager.latestEra(), 0);
        assertEq(stakeManager.currentEra(), 0);
        assertEq(stakeManager.rate(), 1e18);

        // Test unstaking functionality
        uint256 unstakeAmount = stakeAmount;
        lsdToken.approve(address(stakeManager), unstakeAmount);
        stakeManager.unstake(USDC, unstakeAmount);

        // Verify unstaking results
        assertEq(lsdToken.balanceOf(whale), stakeAmount - unstakeAmount);

        console.log("Unbonding duration: ", stakeManager.unbondingDuration());
        console.log("Era seconds: ", stakeManager.eraSeconds());

        vm.warp(block.timestamp + stakeManager.unbondingDuration() * stakeManager.eraSeconds() + 1);

        // Test withdrawal
        uint256 preBalance = IERC20(USDC).balanceOf(address(stakePool));
        stakeManager.withdraw(USDC);
        uint256 postBalance = IERC20(USDC).balanceOf(address(stakePool));
        console.log("Pre balance: ", preBalance);
        console.log("Post balance: ", postBalance);

        // Verify withdrawal
        assertEq(IERC20(USDC).balanceOf(address(stakePool)), 0);
        assertEq(preBalance - unstakeAmount, postBalance);

        console.log("Test completed successfully!");
    }
}
