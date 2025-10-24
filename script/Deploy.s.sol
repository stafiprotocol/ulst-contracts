// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {StakePool} from "../src/StakePool.sol";
import {StakeManager} from "../src/StakeManager.sol";
import {LsdNetworkFactory} from "../src/LsdNetworkFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// export PRIVATE_KEY=0xXXXXX
// forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast --optimize --optimizer-runs 200 --verify --etherscan-api-key <ETHERSCAN_API_KEY>

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy logic contracts
        StakePool stakePoolLogic = new StakePool();
        StakeManager stakeManagerLogic = new StakeManager();
        LsdNetworkFactory factoryLogic = new LsdNetworkFactory();

        // Deploy factory proxy
        LsdNetworkFactory factory = LsdNetworkFactory(address(new ERC1967Proxy(address(factoryLogic), "")));

        // Initialize factory with all required parameters
        factory.initialize(admin, address(stakeManagerLogic), address(stakePoolLogic));

        console.log("Factory deployed at:", address(factory));
        console.log("Admin:", admin);

        vm.stopBroadcast();
    }
}
