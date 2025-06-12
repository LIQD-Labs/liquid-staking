// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LIQDStakingBase.t.sol";

contract LIQDStakingCoreTest is LIQDStakingBaseTest {
    function setUp() public override {
        super.setUp();
    }
    
    /*//////////////////////////////////////////////////////////////
                         STAKING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_StakeSuccessful() public {
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        assertEq(staking.stakedAmount(alice), STAKE_AMOUNT, "Staked amount incorrect");
        assertEq(staking.totalStaked(), STAKE_AMOUNT, "Total staked incorrect");
        assertEq(liqd.balanceOf(address(staking)), STAKE_AMOUNT, "Contract token balance incorrect");
    }
    
    function test_StakeZeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        staking.stake(0);
        vm.stopPrank();
    }
    
    function test_StakeMultipleUsers() public {
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(bob);
        staking.stake(STAKE_AMOUNT * 2);
        vm.stopPrank();
        
        assertEq(staking.stakedAmount(alice), STAKE_AMOUNT, "Alice staked amount incorrect");
        assertEq(staking.stakedAmount(bob), STAKE_AMOUNT * 2, "Bob staked amount incorrect");
        assertEq(staking.totalStaked(), STAKE_AMOUNT * 3, "Total staked incorrect");
    }
    
    function test_StakeMultipleTimesSameUser() public {
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        assertEq(staking.stakedAmount(alice), STAKE_AMOUNT * 2, "Staked amount incorrect after multiple stakes");
        assertEq(staking.totalStaked(), STAKE_AMOUNT * 2, "Total staked incorrect after multiple stakes");
    }
    
    /*//////////////////////////////////////////////////////////////
                         UNSTAKING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_UnstakeSuccessful() public {
        // First stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        
        // Then unstake
        staking.unstake(STAKE_AMOUNT / 2);
        vm.stopPrank();
        
        assertEq(staking.stakedAmount(alice), STAKE_AMOUNT / 2, "Remaining staked amount incorrect");
        assertEq(staking.totalStaked(), STAKE_AMOUNT / 2, "Total staked incorrect after unstake");
        
        // Get account info
        (,, uint256 pendingAmount, uint256 unlockTime, bool isClaimable,,) = staking.getAccountInfo(alice);
        assertEq(pendingAmount, STAKE_AMOUNT / 2, "Pending withdrawal amount incorrect");
        assertEq(unlockTime, block.timestamp + 7 days, "Unlock time incorrect");
        assertEq(isClaimable, false, "Should not be claimable yet");
    }
    
    function test_UnstakeAll() public {
        // First stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        
        // Then unstake all
        staking.unstake(0); // 0 means unstake all
        vm.stopPrank();
        
        assertEq(staking.stakedAmount(alice), 0, "Staked amount should be zero after unstaking all");
        assertEq(staking.totalStaked(), 0, "Total staked should be zero after unstaking all");
        
        // Get account info
        (,, uint256 pendingAmount,,,, ) = staking.getAccountInfo(alice);
        assertEq(pendingAmount, STAKE_AMOUNT, "Pending withdrawal amount incorrect");
    }
    
    function test_UnstakeMoreThanStaked() public {
        // First stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        
        // Try to unstake more than staked
        vm.expectRevert(abi.encodeWithSelector(LIQDStaking.InsufficientBalance.selector, STAKE_AMOUNT, STAKE_AMOUNT * 2));
        staking.unstake(STAKE_AMOUNT * 2);
        vm.stopPrank();
    }
    
    function test_MultipleUnstakesIncreaseAmount() public {
        // First stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        
        // First unstake
        staking.unstake(STAKE_AMOUNT / 2);
        
        // Second unstake
        staking.unstake(STAKE_AMOUNT / 4);
        vm.stopPrank();
        
        // Get account info
        (,, uint256 pendingAmount,,,, ) = staking.getAccountInfo(alice);
        assertEq(pendingAmount, STAKE_AMOUNT * 3 / 4, "Pending withdrawal amount should accumulate");
        assertEq(staking.stakedAmount(alice), STAKE_AMOUNT / 4, "Remaining staked amount incorrect");
    }
    
    /*//////////////////////////////////////////////////////////////
                         WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_WithdrawalAfterTimelock() public {
        // First stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        
        // Unstake
        staking.unstake(STAKE_AMOUNT);
        
        // Move time forward
        vm.warp(block.timestamp + 7 days + 1);
        
        // Withdraw
        uint256 balanceBefore = liqd.balanceOf(alice);
        staking.withdraw();
        uint256 balanceAfter = liqd.balanceOf(alice);
        vm.stopPrank();
        
        assertEq(balanceAfter - balanceBefore, STAKE_AMOUNT, "Withdrawn amount incorrect");
        
        // Get account info
        (,, uint256 pendingAmount,,,, ) = staking.getAccountInfo(alice);
        assertEq(pendingAmount, 0, "Pending withdrawal should be cleared after withdrawal");
    }
    
    function test_WithdrawalBeforeTimelock() public {
        // First stake
        vm.startPrank(alice);
        staking.stake(STAKE_AMOUNT);
        
        // Unstake
        staking.unstake(STAKE_AMOUNT);
        
        // Try to withdraw before timelock expires
        vm.expectRevert(abi.encodeWithSelector(LIQDStaking.WithdrawalLocked.selector, block.timestamp + 7 days, block.timestamp));
        staking.withdraw();
        vm.stopPrank();
    }
    
    function test_WithdrawalWithoutUnstaking() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("NoPendingWithdrawal()"));
        staking.withdraw();
        vm.stopPrank();
    }
} 