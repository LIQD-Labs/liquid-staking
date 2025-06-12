// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/LIQDStaking.sol";
import "../../src/MockLIQD.sol";

abstract contract LIQDStakingBaseTest is Test {
    LIQDStaking public staking;
    MockLIQD public liqd;
    
    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    address public dave;
    
    uint256 public constant INITIAL_MINT = 10000 ether;
    uint256 public constant STAKE_AMOUNT = 1000 ether;
    uint256 public constant REWARD_AMOUNT = 100 ether;
    
    function setUp() public virtual {
        // Set up accounts
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        dave = makeAddr("dave");
        
        // Deploy mock LIQD token with correct constructor arguments
        liqd = new MockLIQD("Mock LIQD", "mLIQD", owner);
        
        // Deploy staking contract
        staking = new LIQDStaking(address(liqd));
        
        // Mint tokens to test accounts
        liqd.mint(alice, INITIAL_MINT);
        liqd.mint(bob, INITIAL_MINT);
        liqd.mint(charlie, INITIAL_MINT);
        liqd.mint(dave, INITIAL_MINT);
        
        // Approve staking contract to spend tokens
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
    }
} 