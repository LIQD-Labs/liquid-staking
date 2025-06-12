// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/LIQDStaking.sol";
import "../../src/MockLIQD.sol";

contract LIQDStakingFuzzTest is Test {
    LIQDStaking public staking;
    MockLIQD public liqd;
    
    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    address public dave;
    address public eve;
    
    uint256 public constant INITIAL_MINT = 10000 ether;
    uint256 public constant BASE_STAKE_AMOUNT = 1000 ether;
    uint256 public constant BASE_REWARD_AMOUNT = 100 ether;
    
    function setUp() public {
        // Set up accounts
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        dave = makeAddr("dave");
        eve = makeAddr("eve");
        
        // Deploy mock LIQD token with correct constructor arguments
        liqd = new MockLIQD("Mock LIQD", "mLIQD", owner);
        
        // Deploy staking contract
        staking = new LIQDStaking(address(liqd));
        
        // Mint tokens to test accounts
        liqd.mint(alice, INITIAL_MINT);
        liqd.mint(bob, INITIAL_MINT);
        liqd.mint(charlie, INITIAL_MINT);
        liqd.mint(dave, INITIAL_MINT);
        liqd.mint(eve, INITIAL_MINT);
        
        // Approve staking contract to spend tokens for all test accounts
        vm.startPrank(alice);
        liqd.approve(address(staking), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(bob);
        liqd.approve(address(staking), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(charlie);
        liqd.approve(address(staking), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(dave);
        liqd.approve(address(staking), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(eve);
        liqd.approve(address(staking), type(uint256).max);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                         FUZZ TESTING
    //////////////////////////////////////////////////////////////*/
    
    // Fuzz test for staking different amounts
    function testFuzz_StakeRandomAmounts(uint256 amount) public {
        // Bound amount to be between 1 and INITIAL_MINT
        amount = bound(amount, 1, INITIAL_MINT);
        
        vm.startPrank(alice);
        staking.stake(amount);
        vm.stopPrank();
        
        assertEq(staking.stakedAmount(alice), amount, "Staked amount incorrect");
        assertEq(staking.totalStaked(), amount, "Total staked incorrect");
    }
    
    // Fuzz test for staking and unstaking with random amounts
    function testFuzz_StakeAndUnstakeRandomAmounts(uint256 stakeAmount, uint256 unstakeAmount) public {
        // Bound stake amount to be between 1 and INITIAL_MINT
        stakeAmount = bound(stakeAmount, 1, INITIAL_MINT);
        
        vm.startPrank(alice);
        staking.stake(stakeAmount);
        
        // Bound unstake amount to be between 1 and stakeAmount
        unstakeAmount = bound(unstakeAmount, 1, stakeAmount);
        
        staking.unstake(unstakeAmount);
        vm.stopPrank();
        
        assertEq(staking.stakedAmount(alice), stakeAmount - unstakeAmount, "Remaining staked amount incorrect");
        assertEq(staking.totalStaked(), stakeAmount - unstakeAmount, "Total staked incorrect");
        
        // Get account info
        (,, uint256 pendingAmount, uint256 unlockTime, bool isClaimable,,) = staking.getAccountInfo(alice);
        assertEq(pendingAmount, unstakeAmount, "Pending withdrawal amount incorrect");
        assertEq(unlockTime, block.timestamp + 7 days, "Unlock time incorrect");
        assertEq(isClaimable, false, "Should not be claimable yet");
    }
    
    // Helper function to validate rewards for a single user
    function _validateUserReward(
        address user,
        uint256 userStake,
        uint256 rewardPerTokenIncrease
    ) internal view returns (uint256) {
        // Get actual rewards from contract
        uint256 actualReward = staking.earned(user);
        
        // Calculate expected rewards using the same formula as the contract
        uint256 expectedReward = Math.mulDiv(userStake, rewardPerTokenIncrease, 1e18);
        
        // Verify rewards match exactly
        assertEq(actualReward, expectedReward, "User rewards incorrect");
        
        return actualReward;
    }
    
    // Fuzz test for reward distribution with multiple stakers
    function testFuzz_RewardDistributionMultipleStakers(
        uint256 aliceStake, 
        uint256 bobStake, 
        uint256 charlieStake, 
        uint256 rewardAmount
    ) public {
        // Bound inputs to realistic values
        aliceStake = bound(aliceStake, 1 ether, 1000 ether);
        bobStake = bound(bobStake, 1 ether, 1000 ether);
        charlieStake = bound(charlieStake, 1 ether, 1000 ether);
        rewardAmount = bound(rewardAmount, 0.1 ether, 10 ether);
        
        // Users stake different amounts
        vm.startPrank(alice);
        staking.stake(aliceStake);
        vm.stopPrank();
        
        vm.startPrank(bob);
        staking.stake(bobStake);
        vm.stopPrank();
        
        vm.startPrank(charlie);
        staking.stake(charlieStake);
        vm.stopPrank();
        
        // Record total staked and initial rewardPerToken
        uint256 totalStaked = staking.totalStaked();
        uint256 initialRewardPerToken = staking.rewardRate();
        
        // Add rewards
        vm.deal(owner, rewardAmount);
        vm.startPrank(owner);
        staking.addReward{value: rewardAmount}();
        vm.stopPrank();
        
        // Calculate the reward per token increase
        uint256 rewardPerTokenIncrease = staking.rewardRate() - initialRewardPerToken;
        
        // Validate reward per token calculation
        uint256 expectedIncrease = Math.mulDiv(rewardAmount, 1e18, totalStaked);
        assertEq(rewardPerTokenIncrease, expectedIncrease, "Reward per token increase mismatch");
        
        // Validate individual user rewards
        uint256 aliceRewards = _validateUserReward(alice, aliceStake, rewardPerTokenIncrease);
        uint256 bobRewards = _validateUserReward(bob, bobStake, rewardPerTokenIncrease);
        uint256 charlieRewards = _validateUserReward(charlie, charlieStake, rewardPerTokenIncrease);
        
        // Validate total rewards
        (,, uint256 distributed,,, ) = staking.getStakingStats();
        assertEq(distributed, rewardAmount, "Total distributed rewards incorrect");
        
        // Check dust from rounding
        uint256 totalUserRewards = aliceRewards + bobRewards + charlieRewards;
        assertLe(totalUserRewards, rewardAmount, "Total user rewards should not exceed reward amount");
        
        // Dust should be minimal
        uint256 dust = rewardAmount - totalUserRewards;
        assertLe(dust, rewardAmount / 1000, "Too much dust from reward calculations");
    }
    
    /*//////////////////////////////////////////////////////////////
                    ADDITIONAL TEST SCENARIOS
    //////////////////////////////////////////////////////////////*/
    
    // Test rewards with multiple reward additions and changing stakes
    function test_DynamicStakingAndRewards() public {
        // Setup initial stakes for multiple users
        vm.startPrank(alice);
        staking.stake(100 ether);
        vm.stopPrank();
        
        vm.startPrank(bob);
        staking.stake(200 ether);
        vm.stopPrank();
        
        // Add first reward
        vm.deal(owner, 10 ether);
        vm.startPrank(owner);
        staking.addReward{value: 10 ether}();
        vm.stopPrank();
        
        // Check initial rewards
        uint256 aliceReward1 = staking.earned(alice);
        uint256 bobReward1 = staking.earned(bob);
        
        // Charlie stakes after first rewards
        vm.startPrank(charlie);
        staking.stake(300 ether);
        vm.stopPrank();
        
        // Add second reward
        vm.deal(owner, 15 ether);
        vm.startPrank(owner);
        staking.addReward{value: 15 ether}();
        vm.stopPrank();
        
        // Alice increases stake
        vm.startPrank(alice);
        staking.stake(150 ether);
        vm.stopPrank();
        
        // Bob partially unstakes
        vm.startPrank(bob);
        staking.unstake(50 ether);
        vm.stopPrank();
        
        // Add third reward
        vm.deal(owner, 20 ether);
        vm.startPrank(owner);
        staking.addReward{value: 20 ether}();
        vm.stopPrank();
        
        // Check final rewards
        uint256 aliceReward3 = staking.earned(alice);
        uint256 bobReward3 = staking.earned(bob);
        uint256 charlieReward3 = staking.earned(charlie);
        
        // Alice should have all three reward distributions
        assertGt(aliceReward3, aliceReward1, "Alice's rewards should increase");
        
        // Bob should have all three reward distributions
        assertGt(bobReward3, bobReward1, "Bob's rewards should increase");
        
        // Charlie should have only the second and third reward distributions
        assertGt(charlieReward3, 0, "Charlie should have rewards from later distributions");
        
        // Total rewards in the system should match what we added
        (,, uint256 distributed, uint256 claimed, uint256 unclaimed,) = staking.getStakingStats();
        assertEq(distributed, 45 ether, "Total distributed rewards incorrect");
        assertEq(claimed, 0, "No rewards should be claimed yet");
        assertEq(unclaimed, 45 ether, "All rewards should be unclaimed");
        
        // The total of all user rewards should be close to the total rewards added
        assertApproxEqAbs(
            aliceReward3 + bobReward3 + charlieReward3, 
            45 ether, 
            1000, // Allow for small rounding errors
            "Sum of user rewards should match total rewards"
        );
    }
    
    // Test claiming rewards after many actions
    function test_ClaimingAfterComplexScenario() public {
        // Initial setup
        vm.startPrank(alice);
        staking.stake(100 ether);
        vm.stopPrank();
        
        vm.startPrank(bob);
        staking.stake(200 ether);
        vm.stopPrank();
        
        // Add first reward
        vm.deal(owner, 10 ether);
        vm.startPrank(owner);
        staking.addReward{value: 10 ether}();
        vm.stopPrank();
        
        // Charlie stakes
        vm.startPrank(charlie);
        staking.stake(300 ether);
        vm.stopPrank();
        
        // Add second reward
        vm.deal(owner, 15 ether);
        vm.startPrank(owner);
        staking.addReward{value: 15 ether}();
        vm.stopPrank();
        
        // Alice claims her rewards
        uint256 aliceRewardsBeforeClaim = staking.earned(alice);
        
        vm.startPrank(alice);
        uint256 aliceBalanceBefore = alice.balance;
        staking.claim();
        uint256 aliceBalanceAfter = alice.balance;
        vm.stopPrank();
        
        assertEq(aliceBalanceAfter - aliceBalanceBefore, aliceRewardsBeforeClaim, "Alice claimed incorrect amount");
        assertEq(staking.earned(alice), 0, "Alice should have no pending rewards after claim");
        
        // Add third reward
        vm.deal(owner, 20 ether);
        vm.startPrank(owner);
        staking.addReward{value: 20 ether}();
        vm.stopPrank();
        
        // Alice should now have new rewards from the third distribution
        assertGt(staking.earned(alice), 0, "Alice should have new rewards after claiming");
        
        // Bob claims his rewards
        uint256 bobRewardsBeforeClaim = staking.earned(bob);
        
        vm.startPrank(bob);
        uint256 bobBalanceBefore = bob.balance;
        staking.claim();
        uint256 bobBalanceAfter = bob.balance;
        vm.stopPrank();
        
        assertEq(bobBalanceAfter - bobBalanceBefore, bobRewardsBeforeClaim, "Bob claimed incorrect amount");
        
        // Check global stats
        (,, uint256 distributed, uint256 claimed, uint256 unclaimed,) = staking.getStakingStats();
        assertEq(distributed, 45 ether, "Total distributed rewards incorrect");
        assertEq(claimed, aliceRewardsBeforeClaim + bobRewardsBeforeClaim, "Claimed rewards incorrect");
        assertEq(unclaimed, 45 ether - (aliceRewardsBeforeClaim + bobRewardsBeforeClaim), "Unclaimed rewards incorrect");
    }
    
    // Test stake, unstake, and restake cycle
    function test_StakeUnstakeRestakeCycle() public {
        // Alice stakes
        vm.startPrank(alice);
        staking.stake(100 ether);
        vm.stopPrank();
        
        // Add first reward
        vm.deal(owner, 10 ether);
        vm.startPrank(owner);
        staking.addReward{value: 10 ether}();
        vm.stopPrank();
        
        // Alice unstakes half
        vm.startPrank(alice);
        staking.unstake(50 ether);
        vm.stopPrank();
        
        // Add second reward
        vm.deal(owner, 10 ether);
        vm.startPrank(owner);
        staking.addReward{value: 10 ether}();
        vm.stopPrank();
        
        // Alice restakes more than what she has left staked
        vm.startPrank(alice);
        staking.stake(150 ether);
        vm.stopPrank();
        
        // Check her staked amount
        assertEq(staking.stakedAmount(alice), 200 ether, "Alice's staked amount incorrect after restaking");
        
        // Skip time to allow withdrawal
        vm.warp(block.timestamp + 7 days + 1);
        
        // Alice withdraws unstaked tokens
        vm.startPrank(alice);
        staking.withdraw();
        vm.stopPrank();
        
        // Add third reward
        vm.deal(owner, 10 ether);
        vm.startPrank(owner);
        staking.addReward{value: 10 ether}();
        vm.stopPrank();
        
        // Alice claims rewards
        uint256 aliceRewards = staking.earned(alice);
        
        vm.startPrank(alice);
        uint256 balanceBefore = alice.balance;
        staking.claim();
        uint256 balanceAfter = alice.balance;
        vm.stopPrank();
        
        assertEq(balanceAfter - balanceBefore, aliceRewards, "Alice claimed incorrect rewards");
    }
    
    // Test multiple users staking, unstaking, and claiming in a complex sequence
    function test_ComplexMultiUserScenario() public {
        // Initial stakes
        vm.startPrank(alice);
        staking.stake(100 ether);
        vm.stopPrank();
        
        vm.startPrank(bob);
        staking.stake(200 ether);
        vm.stopPrank();
        
        vm.startPrank(charlie);
        staking.stake(300 ether);
        vm.stopPrank();
        
        // First reward
        vm.deal(owner, 30 ether);
        vm.startPrank(owner);
        staking.addReward{value: 30 ether}();
        vm.stopPrank();
        
        // Alice unstakes all
        vm.startPrank(alice);
        staking.unstake(0); // 0 means all
        vm.stopPrank();
        
        // Dave joins
        vm.startPrank(dave);
        staking.stake(400 ether);
        vm.stopPrank();
        
        // Second reward
        vm.deal(owner, 40 ether);
        vm.startPrank(owner);
        staking.addReward{value: 40 ether}();
        vm.stopPrank();
        
        // Bob unstakes half
        vm.startPrank(bob);
        staking.unstake(100 ether);
        vm.stopPrank();
        
        // Charlie claims rewards
        uint256 charlieRewards = staking.earned(charlie);
        
        vm.startPrank(charlie);
        uint256 charlieBalanceBefore = charlie.balance;
        staking.claim();
        uint256 charlieBalanceAfter = charlie.balance;
        vm.stopPrank();
        
        assertEq(charlieBalanceAfter - charlieBalanceBefore, charlieRewards, "Charlie claimed incorrect rewards");
        
        // Third reward (by direct ETH transfer)
        vm.deal(owner, 20 ether);
        vm.startPrank(owner);
        (bool success,) = address(staking).call{value: 20 ether}("");
        require(success, "ETH transfer failed");
        vm.stopPrank();
        
        // Fast forward time for withdrawals
        vm.warp(block.timestamp + 7 days + 1);
        
        // Alice withdraws
        vm.startPrank(alice);
        staking.withdraw();
        vm.stopPrank();
        
        // Bob withdraws
        vm.startPrank(bob);
        staking.withdraw();
        vm.stopPrank();
        
        // Fourth reward (via fallback function)
        vm.deal(owner, 10 ether);
        vm.startPrank(owner);
        (bool success2,) = address(staking).call{value: 10 ether}(abi.encodeWithSignature("nonExistentFunction()"));
        require(success2, "ETH transfer via fallback failed");
        vm.stopPrank();
        
        // Dave claims rewards
        uint256 daveRewards = staking.earned(dave);
        
        vm.startPrank(dave);
        uint256 daveBalanceBefore = dave.balance;
        staking.claim();
        uint256 daveBalanceAfter = dave.balance;
        vm.stopPrank();
        
        assertEq(daveBalanceAfter - daveBalanceBefore, daveRewards, "Dave claimed incorrect rewards");
        
        // Final reward stats check
        (,, uint256 distributed, uint256 claimed,,) = staking.getStakingStats();
        assertEq(distributed, 100 ether, "Total distributed incorrect");
        assertGt(claimed, 0, "Should have claimed rewards");
        assertLt(claimed, distributed, "Not all rewards should be claimed");
    }
    
    // Test edge cases for reward calculation
    function test_RewardEdgeCases() public {
        // Part 1: Test single tiny staker with large reward
        vm.startPrank(alice);
        staking.stake(1); // Just 1 wei
        vm.stopPrank();
        
        vm.deal(owner, 1 ether);
        vm.startPrank(owner);
        staking.addReward{value: 1 ether}();
        vm.stopPrank();
        
        // Alice should get all rewards
        assertEq(staking.earned(alice), 1 ether, "Alice should get all rewards");
        
        // Part 2: Test adding a large staker and tiny reward
        vm.startPrank(bob);
        staking.stake(1000 ether);
        vm.stopPrank();
        
        uint256 rewardPerTokenBefore = staking.rewardRate();
        
        vm.deal(owner, 1 gwei);
        vm.startPrank(owner);
        staking.addReward{value: 1 gwei}();
        vm.stopPrank();
        
        // Validate bob's reward
        uint256 rewardIncrease = staking.rewardRate() - rewardPerTokenBefore;
        uint256 expectedBobReward = Math.mulDiv(1000 ether, rewardIncrease, 1e18);
        uint256 bobReward = staking.earned(bob);
        
        assertEq(bobReward, expectedBobReward, "Bob reward incorrect");
        assertGt(bobReward, 0, "Bob should get a reward");
        
        // Part 3: Add huge reward and check final distribution
        vm.deal(owner, 1000 ether);
        vm.startPrank(owner);
        staking.addReward{value: 1000 ether}();
        vm.stopPrank();
        
        // Verify final rewards state
        (,, uint256 distributed,,, ) = staking.getStakingStats();
        assertEq(distributed, 1 ether + 1 gwei + 1000 ether, "Total distributed rewards incorrect");
        
        // Verify users got more rewards
        assertGt(staking.earned(alice), 1 ether, "Alice should have more rewards");
        assertGt(staking.earned(bob), bobReward, "Bob should have more rewards");
    }
} 