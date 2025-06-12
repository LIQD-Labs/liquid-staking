// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {LIQDStaking} from "../src/LIQDStaking.sol";

contract DeployStakingOnly is Script {
    // The existing LIQD token address to use
    address public constant LIQD_TOKEN_ADDRESS = 0x1Ecd15865D7F8019D546f76d095d9c93cc34eDFa;
    
    function run() external returns (LIQDStaking) {
        console.log("Deployer account:", msg.sender);
        console.log("Deployer balance:", msg.sender.balance);
        console.log("Using existing LIQD token at address:", LIQD_TOKEN_ADDRESS);

        vm.startBroadcast();

        // Deploy LIQDStaking contract with the existing LIQD token
        LIQDStaking staking = new LIQDStaking(LIQD_TOKEN_ADDRESS);
        console.log("LIQDStaking contract deployed at:", address(staking));

        vm.stopBroadcast();

        console.log("Deployment completed successfully");
        
        return staking;
    }
}

// Example command to run this script:
// forge script script/DeployStakingOnly.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv 