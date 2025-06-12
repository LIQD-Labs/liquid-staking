// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LIQDStakingBase.t.sol";

contract LIQDStakingViewTest is LIQDStakingBaseTest {
    function setUp() public override {
        super.setUp();
    }
    
    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_RewardRate() public {
        // Alice stakes
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Initially the reward rate should be 0
        assertEq(staking.rewardRate(), 0, "Initial reward rate should be 0");
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Expected reward per token
        uint256 expectedRewardRate = Math.mulDiv(REWARD_AMOUNT, 1e18, STAKE_AMOUNT);
        
        // Check that reward rate matches expected value
        assertEq(staking.rewardRate(), expectedRewardRate, "Reward rate incorrect after adding rewards");
        
        // Add more rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Expected reward rate should double
        assertEq(staking.rewardRate(), expectedRewardRate * 2, "Reward rate incorrect after second reward");
    }
    
    function test_Earned() public {
        // Alice and Bob stake different amounts
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(bob);
        staking.stake(STAKE_AMOUNT * 2);
        vm.stopPrank();
        
        // Initially earned should be 0
        assertEq(staking.earned(alice), 0, "Initial earned should be 0");
        assertEq(staking.earned(bob), 0, "Initial earned should be 0");
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Calculate expected rewards
        uint256 totalStaked = STAKE_AMOUNT * 3;
        uint256 rewardPerToken = Math.mulDiv(REWARD_AMOUNT, 1e18, totalStaked);
        uint256 expectedAliceReward = Math.mulDiv(STAKE_AMOUNT, rewardPerToken, 1e18);
        uint256 expectedBobReward = Math.mulDiv(STAKE_AMOUNT * 2, rewardPerToken, 1e18);
        
        // Check earned values
        assertEq(staking.earned(alice), expectedAliceReward, "Alice earned amount incorrect");
        assertEq(staking.earned(bob), expectedBobReward, "Bob earned amount incorrect");
        
        // Verify bob's reward is approximately double alice's (allowing for rounding)
        assertApproxEqRel(staking.earned(bob), staking.earned(alice) * 2, 0.01e18, "Bob's reward should be ~2x Alice's");
        
        // After claiming, earned should reset to 0
        vm.startPrank(alice);
        staking.claim();
        vm.stopPrank();
        
        assertEq(staking.earned(alice), 0, "Earned should be 0 after claiming");
        
        // Add more rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Alice should have new rewards now
        assertGt(staking.earned(alice), 0, "Alice should have new rewards after new distribution");
    }
    
    function test_GetAccountInfo() public {
        // First stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Check initial account info
        (
            uint256 stakedTokens,
            uint256 currentRewards,
            uint256 pendingWithdrawalAmount,
            uint256 withdrawalUnlockTime,
            bool isWithdrawalClaimable,
            uint256 totalLifetimeRewards,
            uint256 remainingLockTime
        ) = staking.getAccountInfo(alice);
        
        assertEq(stakedTokens, STAKE_AMOUNT, "Staked tokens incorrect");
        assertEq(currentRewards, REWARD_AMOUNT, "Current rewards incorrect");
        assertEq(pendingWithdrawalAmount, 0, "Should have no pending withdrawal");
        assertEq(withdrawalUnlockTime, 0, "Unlock time should be 0 with no pending withdrawal");
        assertEq(isWithdrawalClaimable, false, "Nothing to claim without unstaking");
        assertEq(totalLifetimeRewards, REWARD_AMOUNT, "Total lifetime rewards incorrect");
        assertEq(remainingLockTime, 0, "No remaining lock time without unstaking");
        
        // Now unstake half
        vm.startPrank(alice);
        staking.unstake(STAKE_AMOUNT / 2);
        vm.stopPrank();
        
        // Check updated account info
        (
            stakedTokens,
            currentRewards,
            pendingWithdrawalAmount,
            withdrawalUnlockTime,
            isWithdrawalClaimable,
            totalLifetimeRewards,
            remainingLockTime
        ) = staking.getAccountInfo(alice);
        
        assertEq(stakedTokens, STAKE_AMOUNT / 2, "Staked tokens incorrect after unstaking");
        assertEq(currentRewards, REWARD_AMOUNT, "Rewards should not change just from unstaking");
        assertEq(pendingWithdrawalAmount, STAKE_AMOUNT / 2, "Pending withdrawal amount incorrect");
        assertEq(withdrawalUnlockTime, block.timestamp + 7 days, "Unlock time incorrect");
        assertEq(isWithdrawalClaimable, false, "Should not be claimable before timelock expires");
        assertEq(totalLifetimeRewards, REWARD_AMOUNT, "Total lifetime rewards should be unchanged");
        assertEq(remainingLockTime, 7 days, "Remaining lock time incorrect");
        
        // Fast forward time to make withdrawal claimable
        vm.warp(block.timestamp + 7 days + 1);
        
        // Check account info after timelock expires
        (
            stakedTokens,
            currentRewards,
            pendingWithdrawalAmount,
            withdrawalUnlockTime,
            isWithdrawalClaimable,
            totalLifetimeRewards,
            remainingLockTime
        ) = staking.getAccountInfo(alice);
        
        assertEq(stakedTokens, STAKE_AMOUNT / 2, "Staked tokens should be unchanged");
        assertEq(pendingWithdrawalAmount, STAKE_AMOUNT / 2, "Pending withdrawal amount should be unchanged");
        assertEq(isWithdrawalClaimable, true, "Should be claimable after timelock expires");
        assertEq(remainingLockTime, 0, "Remaining lock time should be 0 after timelock expires");
        
        // Claim rewards and check updated info
        vm.startPrank(alice);
        staking.claim();
        vm.stopPrank();
        
        (
            stakedTokens,
            currentRewards,
            pendingWithdrawalAmount,
            withdrawalUnlockTime,
            isWithdrawalClaimable,
            totalLifetimeRewards,
            remainingLockTime
        ) = staking.getAccountInfo(alice);
        
        assertEq(currentRewards, 0, "Current rewards should be 0 after claiming");
        assertEq(totalLifetimeRewards, REWARD_AMOUNT, "Total lifetime rewards should include claimed rewards");
        
        // Withdraw unstaked tokens and check final state
        vm.startPrank(alice);
        staking.withdraw();
        vm.stopPrank();
        
        (
            stakedTokens,
            currentRewards,
            pendingWithdrawalAmount,
            withdrawalUnlockTime,
            isWithdrawalClaimable,
            totalLifetimeRewards,
            remainingLockTime
        ) = staking.getAccountInfo(alice);
        
        assertEq(stakedTokens, STAKE_AMOUNT / 2, "Staked tokens should be unchanged after withdrawal");
        assertEq(pendingWithdrawalAmount, 0, "Pending withdrawal amount should be 0 after withdrawal");
        assertEq(isWithdrawalClaimable, false, "Nothing to claim after withdrawal");
        assertEq(remainingLockTime, 0, "No remaining lock time after withdrawal");
    }
    
    function test_GetStakingStats() public {
        // Initially, all stats should be 0
        (
            uint256 totalStakedTokens,
            uint256 currentRewardRate,
            uint256 totalDistributed,
            uint256 totalClaimed,
            uint256 totalUnclaimed,
            uint256 contractBalance
        ) = staking.getStakingStats();
        
        assertEq(totalStakedTokens, 0, "Initial staked tokens should be 0");
        assertEq(currentRewardRate, 0, "Initial reward rate should be 0");
        assertEq(totalDistributed, 0, "Initial distributed rewards should be 0");
        assertEq(totalClaimed, 0, "Initial claimed rewards should be 0");
        assertEq(totalUnclaimed, 0, "Initial unclaimed rewards should be 0");
        assertEq(contractBalance, 0, "Initial contract balance should be 0");
        
        // Alice and Bob stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(bob);
        staking.stake(STAKE_AMOUNT * 2);
        vm.stopPrank();
        
        // Check stats after staking
        (
            totalStakedTokens,
            currentRewardRate,
            totalDistributed,
            totalClaimed,
            totalUnclaimed,
            contractBalance
        ) = staking.getStakingStats();
        
        assertEq(totalStakedTokens, STAKE_AMOUNT * 3, "Total staked incorrect after users stake");
        assertEq(currentRewardRate, 0, "Reward rate should still be 0 before rewards added");
        assertEq(totalDistributed, 0, "No rewards distributed yet");
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Check stats after adding rewards
        (
            totalStakedTokens,
            currentRewardRate,
            totalDistributed,
            totalClaimed,
            totalUnclaimed,
            contractBalance
        ) = staking.getStakingStats();
        
        assertEq(totalStakedTokens, STAKE_AMOUNT * 3, "Total staked should be unchanged");
        assertGt(currentRewardRate, 0, "Reward rate should be non-zero after adding rewards");
        assertEq(totalDistributed, REWARD_AMOUNT, "Distributed rewards incorrect");
        assertEq(totalClaimed, 0, "No rewards claimed yet");
        assertEq(totalUnclaimed, REWARD_AMOUNT, "All rewards should be unclaimed");
        assertEq(contractBalance, REWARD_AMOUNT, "Contract balance should match rewards added");
        
        // Alice claims rewards
        uint256 aliceRewards = staking.earned(alice);
        vm.startPrank(alice);
        staking.claim();
        vm.stopPrank();
        
        // Check stats after claiming
        (
            totalStakedTokens,
            currentRewardRate,
            totalDistributed,
            totalClaimed,
            totalUnclaimed,
            contractBalance
        ) = staking.getStakingStats();
        
        assertEq(totalClaimed, aliceRewards, "Claimed rewards should match Alice's claim");
        assertEq(totalUnclaimed, REWARD_AMOUNT - aliceRewards, "Unclaimed rewards incorrect after Alice claims");
        assertEq(contractBalance, REWARD_AMOUNT - aliceRewards, "Contract balance should be reduced by claimed amount");
        
        // Add more rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Check stats after adding more rewards
        (
            totalStakedTokens,
            currentRewardRate,
            totalDistributed,
            totalClaimed,
            totalUnclaimed,
            contractBalance
        ) = staking.getStakingStats();
        
        assertEq(totalDistributed, REWARD_AMOUNT * 2, "Total distributed should include all rewards");
        assertEq(totalUnclaimed, (REWARD_AMOUNT * 2) - aliceRewards, "Unclaimed rewards incorrect after second reward");
        assertEq(contractBalance, (REWARD_AMOUNT * 2) - aliceRewards, "Contract balance incorrect after second reward");
    }
    
    // Split the complex test into multiple smaller tests to avoid stack too deep error
    function test_ViewFunctionsMultiUserSetup() public {
        // Setup: Multiple users stake different amounts
        vm.startPrank(alice);
        staking.stake(100 ether);
        vm.stopPrank();
        
        vm.startPrank(bob);
        staking.stake(200 ether);
        vm.stopPrank();
        
        vm.startPrank(charlie);
        staking.stake(300 ether);
        vm.stopPrank();
        
        // Add rewards
        vm.deal(owner, 60 ether);
        vm.startPrank(owner);
        staking.addReward{value: 60 ether}();
        vm.stopPrank();
        
        // Check each user's earned rewards
        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned = staking.earned(bob);
        uint256 charlieEarned = staking.earned(charlie);
        
        // Verify proportions - Alice:Bob:Charlie = 1:2:3
        assertApproxEqRel(aliceEarned * 2, bobEarned, 0.01e18, "Bob's rewards should be ~2x Alice's");
        assertApproxEqRel(aliceEarned * 3, charlieEarned, 0.01e18, "Charlie's rewards should be ~3x Alice's");
        
        // Sum of all earned rewards should equal total rewards (allowing for tiny rounding errors)
        assertApproxEqAbs(aliceEarned + bobEarned + charlieEarned, 60 ether, 10, "Sum of rewards should equal total");
    }
    
    function test_ViewFunctionsStakingStats() public {
        // Setup
        test_ViewFunctionsMultiUserSetup();
        
        // Check getStakingStats
        (
            uint256 totalStakedTokens,
            ,  // Skip unusedRewardRate
            uint256 totalDistributed,
            ,  // Skip unusedClaimed
            uint256 totalUnclaimed,
            uint256 contractBalance
        ) = staking.getStakingStats();
        
        assertEq(totalStakedTokens, 600 ether, "Total staked incorrect");
        assertEq(totalDistributed, 60 ether, "Total distributed incorrect");
        assertEq(totalUnclaimed, 60 ether, "All rewards should be unclaimed");
        assertEq(contractBalance, 60 ether, "Contract balance incorrect");
    }
    
    function test_ViewFunctionsAfterClaim() public {
        // Setup
        test_ViewFunctionsMultiUserSetup();
        
        // Get Alice's earned amount before claiming
        uint256 aliceEarned = staking.earned(alice);
        
        // Alice claims rewards
        vm.startPrank(alice);
        staking.claim();
        vm.stopPrank();
        
        // Check getStakingStats after claim
        (
            ,,, // Skip first 3 values
            uint256 totalClaimed,
            uint256 updatedTotalUnclaimed,
            uint256 updatedContractBalance
        ) = staking.getStakingStats();
        
        assertEq(totalClaimed, aliceEarned, "Total claimed should equal Alice's rewards");
        assertEq(updatedTotalUnclaimed, 60 ether - aliceEarned, "Unclaimed rewards incorrect after Alice's claim");
        assertEq(updatedContractBalance, 60 ether - aliceEarned, "Contract balance incorrect after Alice's claim");
    }
    
    function test_ViewFunctionsAccountInfo() public {
        // Setup
        test_ViewFunctionsMultiUserSetup();
        
        // Get Alice's earned amount before claiming
        uint256 aliceEarned = staking.earned(alice);
        
        // Alice claims rewards
        vm.startPrank(alice);
        staking.claim();
        vm.stopPrank();
        
        // Verify Alice's getAccountInfo after claim
        (
            uint256 stakedTokens,
            uint256 currentRewards,
            ,,, // Skip unusedPendingAmount, unusedUnlockTime, unusedClaimable
            uint256 totalLifetimeRewards,
            // Skip unusedRemainingTime
        ) = staking.getAccountInfo(alice);
        
        assertEq(stakedTokens, 100 ether, "Alice's staked tokens incorrect");
        assertEq(currentRewards, 0, "Alice should have no current rewards after claiming");
        assertEq(totalLifetimeRewards, aliceEarned, "Alice's lifetime rewards incorrect");
    }
    
    function test_StakingStatsWithEqualClaimedAndDistributed() public {
        // Alice stakes
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Alice claims all rewards
        vm.startPrank(alice);
        staking.claim();
        vm.stopPrank();
        
        // Get staking stats and explicitly store each return value
        uint256 totalStakedTokens;
        uint256 currentRewardRate;
        uint256 totalDistributed;
        uint256 totalClaimed;
        uint256 totalUnclaimed;
        uint256 contractBalance;
        
        // Use multiple statements to ensure the return statement is covered
        (totalStakedTokens, currentRewardRate, totalDistributed, totalClaimed, totalUnclaimed, contractBalance) = staking.getStakingStats();
        
        // Use all returned values to ensure the compiler doesn't optimize them away
        console.log("Total staked tokens:", totalStakedTokens);
        console.log("Current reward rate:", currentRewardRate);
        console.log("Total distributed:", totalDistributed);
        console.log("Total claimed:", totalClaimed);
        console.log("Total unclaimed:", totalUnclaimed);
        console.log("Contract balance:", contractBalance);
        
        // Verify that totalClaimed equals totalDistributed
        assertEq(totalClaimed, totalDistributed, "Total claimed should equal total distributed");
        
        // This should test the branch where totalUnclaimed is set to 0 because totalDistributed == totalClaimed
        assertEq(totalUnclaimed, 0, "Total unclaimed should be 0 when all rewards are claimed");
        
        // Verify other stats
        assertEq(totalStakedTokens, STAKE_AMOUNT, "Total staked incorrect");
        assertGt(currentRewardRate, 0, "Current reward rate should be greater than 0");
        assertEq(contractBalance, 0, "Contract balance should be 0 after all claims");
    }
    
    function test_DirectReturnFromGetStakingStats() public {
        // Alice stakes
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Alice claims all rewards
        vm.startPrank(alice);
        staking.claim();
        vm.stopPrank();
        
        // Call the function directly and immediately use the return values
        (
            uint256 totalStakedTokens,
            uint256 currentRewardRate,
            uint256 totalDistributed,
            uint256 totalClaimed,
            uint256 totalUnclaimed,
            uint256 contractBalance
        ) = directlyCallGetStakingStats();
        
        // Use all the values to ensure they're not optimized away
        assertEq(totalStakedTokens + currentRewardRate + totalDistributed + totalClaimed + totalUnclaimed + contractBalance, 
                 STAKE_AMOUNT + currentRewardRate + REWARD_AMOUNT + REWARD_AMOUNT + 0 + 0, 
                 "Values should match expected");
    }
    
    // Helper function that directly returns the values from getStakingStats
    function directlyCallGetStakingStats() internal view returns (
        uint256 totalStakedTokens,
        uint256 currentRewardRate,
        uint256 totalDistributed,
        uint256 totalClaimed,
        uint256 totalUnclaimed,
        uint256 contractBalance
    ) {
        return staking.getStakingStats();
    }
} 