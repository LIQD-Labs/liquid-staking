// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {LIQDStaking} from "../src/LIQDStaking.sol";
import {MockLIQD} from "../src/MockLIQD.sol";

contract DeployLIQDStaking is Script {
    // Amount to mint (100,000 tokens with 18 decimals)
    uint256 constant MINT_AMOUNT = 100000 * 10**18;
    
    // The specific address that will receive minted tokens
    address public constant RECIPIENT = 0xcED0104a114EeB8Fd12be0882886d39473Ef1EAc;
    
    function run() external returns (LIQDStaking, MockLIQD) {
        console.log("Deployer account:", msg.sender);
        console.log("Deployer balance:", msg.sender.balance);
        console.log("Recipient address:", RECIPIENT);

        vm.startBroadcast();

        // 1. Deploy MockLIQD token
        MockLIQD liqd = new MockLIQD("Mock LIQD", "mLIQD", msg.sender);
        console.log("MockLIQD token deployed at:", address(liqd));
        
        // 2. Deploy LIQDStaking contract with the MockLIQD token
        LIQDStaking staking = new LIQDStaking(address(liqd));
        console.log("LIQDStaking contract deployed at:", address(staking));
        
        // 3. Mint tokens to the specified recipient address only
        liqd.mint(RECIPIENT, MINT_AMOUNT);
        console.log("Minted", MINT_AMOUNT, "tokens to", RECIPIENT);

        vm.stopBroadcast();

        console.log("Deployment and minting completed successfully");
        
        return (staking, liqd);
    }
}

// Example command to run this script:
// forge script script/DeployLIQDStaking.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv 