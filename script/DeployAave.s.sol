// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {AaveStakePool} from "../src/AaveStakePool.sol";
import {StakeManager} from "../src/StakeManager.sol";
import {LsdToken} from "../src/LsdToken.sol";
import {LsdNetworkFactory} from "../src/LsdNetworkFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/*
export PRIVATE_KEY=0xXXXXX
export LSD_TOKEN_NAME=Test LSD Token
export LSD_TOKEN_SYMBOL=TLSD

forge script script/DeployAave.s.sol \
    --rpc-url <RPC_URL> \
    --broadcast --optimize --optimizer-runs 200 \
    --verify --etherscan-api-key <ETHERSCAN_API_KEY> \
 */

contract DeployScript is Script {
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
        address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address aUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;
        if (block.chainid == 11155111) {
            // Sepolia
            aavePoolAddress = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
            USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
            aUSDT = 0x9844386d29EEd970B9F6a2B9a676083b0478210e;
        }

        StakeManager stakeManager = StakeManager(address(new ERC1967Proxy(address(new StakeManager()), "")));
        AaveStakePool stakePool = AaveStakePool(address(new ERC1967Proxy(address(new AaveStakePool()), "")));
        LsdToken lsdToken = new LsdToken(lsdTokenName, lsdTokenSymbol);
        lsdToken.initMinter(address(stakeManager));

        address[] memory stablecoins = new address[](1);
        stablecoins[0] = USDT;
        stakeManager.initialize(address(lsdToken), address(stakePool), admin, stablecoins, admin);

        stakePool.initialize(address(stakeManager), aavePoolAddress, admin);
        stakePool.setStablecoinToAaveToken(USDT, address(aUSDT));

        console.log("StakeManager deployed at:", address(stakeManager));
        console.log("StakePool deployed at:", address(stakePool));
        console.log("LsdToken deployed at:", address(lsdToken));
        console.log("Admin:", admin);

        vm.stopBroadcast();
    }
}
