// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LIQDStakingBase.t.sol";

contract LIQDStakingRewardsTest is LIQDStakingBaseTest {
    function setUp() public override {
        super.setUp();
    }
    
    /*//////////////////////////////////////////////////////////////
                         REWARDS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_RewardDistributionSingleStaker() public {
        // First stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Check rewards
        uint256 aliceRewards = staking.earned(alice);
        assertEq(aliceRewards, REWARD_AMOUNT, "Rewards not correctly assigned to single staker");
    }
    
    function test_RewardDistributionMultipleStakers() public {
        // Alice stakes
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Bob stakes
        vm.startPrank(bob);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Check rewards
        uint256 aliceRewards = staking.earned(alice);
        uint256 bobRewards = staking.earned(bob);
        
        assertEq(aliceRewards, REWARD_AMOUNT / 2, "Alice rewards incorrect");
        assertEq(bobRewards, REWARD_AMOUNT / 2, "Bob rewards incorrect");
    }
    
    function test_RewardDistributionProportional() public {
        // Alice stakes 1/3
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Bob stakes 2/3
        vm.startPrank(bob);
        staking.stake(STAKE_AMOUNT * 2);
        vm.stopPrank();
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Check rewards
        uint256 aliceRewards = staking.earned(alice);
        uint256 bobRewards = staking.earned(bob);
        
        // Calculate rewards exactly as the contract does
        // 1. Calculate rewardPerToken increase
        uint256 rewardPerTokenIncrease = Math.mulDiv(REWARD_AMOUNT, 1e18, STAKE_AMOUNT * 3);
        
        // 2. Calculate each user's expected rewards based on their stake and the rewardPerToken
        uint256 expectedAliceRewards = Math.mulDiv(STAKE_AMOUNT, rewardPerTokenIncrease, 1e18);
        uint256 expectedBobRewards = Math.mulDiv(STAKE_AMOUNT * 2, rewardPerTokenIncrease, 1e18);
        
        assertEq(aliceRewards, expectedAliceRewards, "Alice rewards incorrect");
        assertEq(bobRewards, expectedBobRewards, "Bob rewards incorrect");
    }
    
    function test_RewardAccumulatesOverTime() public {
        // Alice stakes
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Add first reward
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Add second reward
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Check rewards
        uint256 aliceRewards = staking.earned(alice);
        assertEq(aliceRewards, REWARD_AMOUNT * 2, "Rewards should accumulate");
    }
    
    function test_RewardBeforeAndAfterStaking() public {
        // Alice stakes first (required in the new contract behavior)
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Add first reward batch
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Add second reward batch
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Check rewards
        uint256 aliceRewards = staking.earned(alice);
        assertEq(aliceRewards, REWARD_AMOUNT * 2, "Alice should get both reward batches");
    }
    
    /*//////////////////////////////////////////////////////////////
                         CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ClaimRewards() public {
        // Alice stakes
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Alice claims
        vm.startPrank(alice);
        uint256 balanceBefore = alice.balance;
        staking.claim();
        uint256 balanceAfter = alice.balance;
        vm.stopPrank();
        
        assertEq(balanceAfter - balanceBefore, REWARD_AMOUNT, "Claimed rewards incorrect");
        assertEq(staking.earned(alice), 0, "Rewards should be reset after claiming");
    }
    
    function test_ClaimWithNoRewards() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("NoPendingRewards()"));
        staking.claim();
        vm.stopPrank();
    }
    
    function test_ClaimUpdatesTracking() public {
        // Alice stakes
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Add rewards
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Alice claims
        vm.startPrank(alice);
        staking.claim();
        vm.stopPrank();
        
        // Check global stats
        (,, uint256 distributed, uint256 claimed, uint256 unclaimed,) = staking.getStakingStats();
        assertEq(distributed, REWARD_AMOUNT, "Total distributed incorrect");
        assertEq(claimed, REWARD_AMOUNT, "Total claimed incorrect");
        assertEq(unclaimed, 0, "Unclaimed should be zero");
        
        // Check user stats
        (,,,,, uint256 totalRewards,) = staking.getAccountInfo(alice);
        assertEq(totalRewards, REWARD_AMOUNT, "User total rewards incorrect");
    }
    
    /*//////////////////////////////////////////////////////////////
                    RECEIVE AND FALLBACK TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_RejectRewardsWithNoStakers() public {
        // Try to add rewards before anyone stakes
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        
        // Expect revert with NoStakers error
        vm.expectRevert(abi.encodeWithSignature("NoStakers()"));
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Try to send ETH directly to contract before anyone stakes
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        
        // Expect revert with NoStakers error
        vm.expectRevert(abi.encodeWithSignature("NoStakers()"));
        // We must capture the return value but don't need to use it
        bool callSuccess;
        (callSuccess,) = address(staking).call{value: REWARD_AMOUNT}("");
        vm.stopPrank();
        
        // Now have Alice stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Now rewards should be accepted
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        staking.addReward{value: REWARD_AMOUNT}();
        vm.stopPrank();
        
        // Check that Alice got the rewards
        uint256 aliceRewards = staking.earned(alice);
        assertEq(aliceRewards, REWARD_AMOUNT, "Rewards not distributed to staker");
    }
    
    function test_ReceiveFunction() public {
        // Alice stakes
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Send ETH directly to contract
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        (bool success,) = address(staking).call{value: REWARD_AMOUNT}("");
        require(success, "ETH transfer failed");
        vm.stopPrank();
        
        // Check that rewards were properly distributed
        uint256 aliceRewards = staking.earned(alice);
        assertEq(aliceRewards, REWARD_AMOUNT, "Rewards not properly distributed via receive function");
    }
    
    function test_FallbackFunction() public {
        // Alice stakes
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Send ETH with data to trigger fallback function
        // We use a non-existent function to trigger the fallback
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        (bool success,) = address(staking).call{value: REWARD_AMOUNT}(abi.encodeWithSignature("nonExistentFunction()"));
        require(success, "ETH transfer failed");
        vm.stopPrank();
        
        // Check that rewards were properly distributed
        uint256 aliceRewards = staking.earned(alice);
        assertEq(aliceRewards, REWARD_AMOUNT, "Rewards not properly distributed via fallback function");
    }
    
    function test_FallbackFunctionRevertWithNoStakers() public {
        // Try to send ETH with data to contract before anyone stakes
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        
        // Expect revert with NoStakers error
        vm.expectRevert(abi.encodeWithSignature("NoStakers()"));
        // We must capture the return value but don't need to use it
        bool callSuccess;
        (callSuccess,) = address(staking).call{value: REWARD_AMOUNT}(abi.encodeWithSignature("nonExistentFunction()"));
        vm.stopPrank();
    }
    
    function test_FallbackAndReceiveCombined() public {
        // Alice and Bob stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(bob);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Send ETH directly (receive function)
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        (bool success1,) = address(staking).call{value: REWARD_AMOUNT}("");
        require(success1, "ETH transfer via receive failed");
        vm.stopPrank();
        
        // Send ETH with data (fallback function)
        vm.deal(owner, REWARD_AMOUNT);
        vm.startPrank(owner);
        (bool success2,) = address(staking).call{value: REWARD_AMOUNT}(abi.encodeWithSignature("nonExistentFunction()"));
        require(success2, "ETH transfer via fallback failed");
        vm.stopPrank();
        
        // Check that rewards were properly distributed
        // Each user should have half of the total rewards (REWARD_AMOUNT * 2)
        uint256 aliceRewards = staking.earned(alice);
        uint256 bobRewards = staking.earned(bob);
        
        assertEq(aliceRewards, REWARD_AMOUNT, "Alice rewards incorrect");
        assertEq(bobRewards, REWARD_AMOUNT, "Bob rewards incorrect");
    }
} 