// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {LIQDStaking} from "../src/LIQDStaking.sol";

contract AddRewards is Script {
    // Default amount of ETH to send as rewards (0.1 ETH)
    uint256 constant DEFAULT_REWARD_AMOUNT = 0.1 ether;
    
    // Hardcoded staking contract address
    address payable constant STAKING_ADDRESS = payable(0x27a9760F866DCdc655eD117c85D5592f8b4CDD1B);

    function run() external {
        // Get reward amount from env var or use default
        uint256 rewardAmount = vm.envOr("REWARD_AMOUNT", DEFAULT_REWARD_AMOUNT);
        
        // Get the LIQDStaking contract
        LIQDStaking staking = LIQDStaking(STAKING_ADDRESS);
        
        console.log("=== Adding Rewards to LIQDStaking Contract ===");
        console.log("LIQDStaking Contract:", STAKING_ADDRESS);
        console.log("Reward Amount:", rewardAmount / 1e18, "ETH");
        console.log("Sender:", msg.sender);
        console.log("Sender ETH Balance:", msg.sender.balance / 1e18, "ETH");
        
        // Ensure sender has enough ETH
        require(msg.sender.balance >= rewardAmount, "Insufficient ETH balance for rewards");
        
        vm.startBroadcast();
        
        // Call addReward function with ETH value
        staking.addReward{value: rewardAmount}();
        
        vm.stopBroadcast();
        
        console.log("=== Rewards Added Successfully ===");
    }
}

// Usage:
// 1. Set environment variables (optional):
//    export REWARD_AMOUNT=200000000000000000 (0.2 ETH, optional)
//
// 2. Run the script:
//    forge script script/AddRewards.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv 