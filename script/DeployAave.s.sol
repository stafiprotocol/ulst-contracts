// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {AaveStakePool} from "../src/AaveStakePool.sol";
import {IAavePool, ReserveDataLegacy} from "../src/interfaces/Aave.sol";
import {StakeManager} from "../src/StakeManager.sol";
import {LsdToken} from "../src/LsdToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/*
export PRIVATE_KEY=0xXXXXX
export LSD_TOKEN_NAME=Test LSD Token
export LSD_TOKEN_SYMBOL=TLSD

forge script DeployAaveScript \
    --rpc-url <RPC_URL> \
    --broadcast --optimize --optimizer-runs 200 \
    --verify --etherscan-api-key <ETHERSCAN_API_KEY> \
 */

contract DeployAaveScript is Script {
    function run() external {
        string memory lsdTokenName = vm.envString("LSD_TOKEN_NAME");
        string memory lsdTokenSymbol = vm.envString("LSD_TOKEN_SYMBOL");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        if (block.chainid != 11155111 && block.chainid != 1) {
            revert("Invalid chain id");
        }

        address aavePoolAddress = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
        address asset = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        if (block.chainid == 11155111) {
            // Sepolia
            aavePoolAddress = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
            asset = 0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5; // LINK
        }

        ReserveDataLegacy memory reserveData = IAavePool(aavePoolAddress).getReserveData(asset);
        address aTokenAddress = reserveData.aTokenAddress;
        console.log("aToken address:", aTokenAddress);

        StakeManager stakeManager = StakeManager(address(new ERC1967Proxy(address(new StakeManager()), "")));
        AaveStakePool stakePool = AaveStakePool(address(new ERC1967Proxy(address(new AaveStakePool()), "")));
        LsdToken lsdToken = new LsdToken(lsdTokenName, lsdTokenSymbol);
        lsdToken.initMinter(address(stakeManager));

        address[] memory stablecoins = new address[](1);
        stablecoins[0] = asset;
        stakeManager.initialize(address(lsdToken), address(stakePool), admin, stablecoins, admin);

        stakePool.initialize(address(stakeManager), aavePoolAddress, admin);

        console.log("StakeManager deployed at:", address(stakeManager));
        console.log("StakePool deployed at:", address(stakePool));
        console.log("LsdToken deployed at:", address(lsdToken));
        console.log("Admin:", admin);

        vm.stopBroadcast();
    }
}
