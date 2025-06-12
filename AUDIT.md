# LIQDStaking Protocol Audit Preparation Document

This document serves as a guide for security auditors reviewing the LIQDStaking protocol. It outlines key protocol invariants, security considerations, and areas that should receive special attention during the audit.

## Protocol Overview

LIQDStaking enables LIQD token holders to stake their tokens and earn HYPE rewards. The core functionality includes:
- Staking LIQD tokens
- Earning HYPE rewards proportionally to staked amount
- Two-step withdrawal process with configurable timelock
- Reward distribution and claiming

## Key Components

1. **Core Staking Logic**: `stake()`, `unstake()`, `withdraw()`
2. **Reward Management**: `_updateReward()`, `_syncReward()`, `claim()`
3. **Admin Functions**: `transferOwnership()`, `setWithdrawalDelay()`
4. **Fallback Mechanisms**: `receive()`, `fallback()`

## Protocol Invariants

These invariants should always hold true throughout the contract's lifecycle:

### State Integrity Invariants

1. `totalStaked == sum(stakedAmount[user]) for all users`
2. For any user with a pending withdrawal: `pendingWithdrawals[user].amount > 0 && pendingWithdrawals[user].unlockTime >= block.timestamp at time of unstaking`
3. Contract's stakingToken balance ≥ `totalStaked + sum(pendingWithdrawals[user].amount) for all users`
4. `totalRewardsDistributed >= totalRewardsClaimed`
5. For each user: `totalRewardsEarned[user] >= claimed rewards for that user`
6. `withdrawalDelay <= MAX_WITHDRAWAL_DELAY` (7 days)

### Reward Calculation Invariants

1. When `totalStaked == 0`, no rewards can be added
2. Rewards are distributed proportionally to staked amounts
3. When a user unstakes, they do not lose access to rewards earned up to that point
4. Reward calculations are accurate even with extreme values or timing conditions

## Trust Assumptions

1. The LIQD token contract behaves correctly according to ERC-20 standard
2. The owner role is trusted to:
   - Manage the withdrawalDelay parameter (can only decrease or keep it unchanged)
   - Transfer ownership to another address

## Security Considerations

### Critical Functions

| Function | Criticality | Notes |
|----------|-------------|-------|
| `stake()` | High | Handles user funds, updates reward state |
| `unstake()` | High | Updates user positions, modifies total staked amount |
| `withdraw()` | High | Transfers tokens back to users |
| `claim()` | Medium-High | Transfers reward tokens to users |
| `_updateReward()` | High | Core accounting function for reward calculations |
| `setWithdrawalDelay()` | Medium | Can affect user withdrawal timing |

### Potential Attack Vectors

1. **Reward Manipulation**
   - Attempt to manipulate reward distribution through precision issues
   - Front-running reward distributions or claims
   - Timing attacks around reward rate calculations

2. **Liquidity Attacks**
   - Flash deposit/withdrawal to steal rewards
   - Precision attacks using very small/large amounts
   - Sandwich attacks around reward distribution events

3. **Reentrancy**
   - While ReentrancyGuard is used, verify all functions are properly protected
   - Check for cross-function reentrancy vulnerabilities

4. **Token Standard Compliance**
   - Verify handling of non-standard or fee-on-transfer tokens
   - Check for proper error handling of failed transfers

5. **Timelock Manipulation**
   - Attempts to bypass the withdrawal timelock
   - Front-running timelock changes

### Edge Cases to Consider

1. **Zero Values**
   - Staking 0 tokens (should revert)
   - Unstaking 0 tokens (should revert or be handled properly)
   - Claiming 0 rewards (should revert)

2. **Boundary Conditions**
   - First staker / last unstaker edge cases
   - Extreme amounts (very small or very large)
   - Effects of block timestamp manipulation

3. **Administrative Controls**
   - Owner renouncing ownership (setting to zero address)
   - Impact of withdrawal delay changes on existing pending withdrawals

## Known Limitations

1. **Gas Costs**
   - When many users have staked, reward distribution calculations might become expensive

2. **Reward Distribution**
   - If total staked amount is 0, incoming rewards will be rejected
   - Rewards can only be distributed if at least one user has tokens staked

3. **Withdrawal Process**
   - The two-step withdrawal process with timelock could impact user experience
   - Timelock can be set to zero by the owner, which would remove the security benefit but improve UX

## Test Coverage

Current test coverage metrics:
- 99.23% line coverage
- 94.93% statement coverage
- 78.57% branch coverage
- 100% function coverage

The remaining untested branches should be specifically targeted by auditors to ensure no edge cases exist there.

## Areas for Special Focus

1. **Reward Calculation Logic**
   - Review mathematical correctness of formulas
   - Check for rounding errors or precision loss
   - Test extreme conditions (very small stakes, very large stakes)

2. **Two-Step Withdrawal Process**
   - Verify timelock enforcement
   - Check interaction between unstake and withdraw
   - Ensure proper state management across multiple unstake calls

3. **Reentrancy Protection**
   - Verify effectiveness across all state-changing functions
   - Check for cross-function reentrancy vulnerabilities

4. **Access Controls**
   - Verify owner-only functions cannot be called by unauthorized users
   - Check for proper validation of ownership transfers

## Conclusion

This LIQD Staking protocol has been implemented with security as a priority, following best practices such as using SafeERC20 for transfers, implementing ReentrancyGuard, following the checks-effects-interactions pattern, and implementing comprehensive tests.

We welcome a thorough review focusing on the mathematical correctness of reward calculations, validation of the staking/unstaking flows, and verification that all invariants are properly maintained throughout the contract's lifecycle. 