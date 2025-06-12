# LIQDStaking: Liquid Staking Protocol for LIQD Tokens

LIQDStaking is a liquid staking solution that enables LIQD token holders to stake their assets while earning HYPE rewards.

## Overview

LIQDStaking implements a liquid staking protocol with the following key features:

- **Direct Staking**: Stake LIQD tokens directly and earn HYPE rewards
- **Reward Distribution**: Earn HYPE rewards proportional to your staked amount
- **Two-Step Withdrawal**: Secure unstaking process with a configurable timelock (up to 7 days)
- **Reward Management**: Claim HYPE rewards at any time without affecting staked tokens
- **Enhanced Security**: Uses ReentrancyGuard and follows checks-effects-interactions pattern

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) for development and testing
- Node.js and npm (optional, for additional scripting)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/liquid-staking.git
   cd liquid-staking
   ```

2. Install dependencies:
   ```bash
   forge install
   ```

## Usage

### Build

Compile the contracts:

```bash
forge build
```

### Test

Run the comprehensive test suite:

```bash
forge test --match-path "test/shisho/*.sol" -v
```

The test suite includes:
- Core staking functionality (`LIQDStakingCore.t.sol`)
- Reward distribution (`LIQDStakingRewards.t.sol`)
- Admin functions (`LIQDStakingAdmin.t.sol`)
- Complex scenarios (`LIQDStakingComplex.t.sol`)
- Fuzz testing (`LIQDStakingFuzz.t.sol`)
- View functions (`LIQDStakingView.t.sol`)

You can run specific test files:

```bash
# Example: Run only the reward tests
forge test --match-path "test/shisho/LIQDStakingRewards.t.sol" -v
```

### Test Coverage

To generate a test coverage report:

```bash
forge coverage --match-path "test/shisho/*.sol"
```

Current coverage metrics for the main contract:

| File                | % Lines          | % Statements     | % Branches     | % Funcs         |
|---------------------|------------------|------------------|----------------|-----------------|
| src/LIQDStaking.sol | 99.23% (129/130) | 94.93% (131/138) | 78.57% (22/28) | 100.00% (17/17) |

The coverage report shows excellent test coverage with:
- 99.23% of lines covered
- 94.93% of statements covered
- 78.57% of branches covered
- 100% of functions covered

### Deploy

Deploy the LIQDStaking contract using the provided script:

```bash
# Set the LIQD token address as an environment variable
export LIQD_TOKEN_ADDRESS=0x...

# Deploy to a testnet (e.g., Sepolia)
forge script script/DeployLIQDStaking.s.sol:DeployLIQDStaking \
  --rpc-url <RPC_URL> \
  --broadcast \
  --private-key <PRIVATE_KEY> \
  --etherscan-api-key <API_KEY> \
  --verify

# For local development with a mock token
forge script script/DeployLIQDStaking.s.sol:DeployLIQDStaking \
  --rpc-url http://localhost:8545 \
  --broadcast \
  --private-key <ANVIL_PRIVATE_KEY>
```

## Smart Contract Overview

### LIQDStaking.sol

The main contract implementing the liquid staking protocol:

- **Staking**: `stake(uint256 amount)` to stake LIQD tokens
- **Unstaking**: Two-step process with `unstake(uint256 amount)` and `withdraw()`
- **Rewards**: Earn HYPE rewards proportional to staked amount
- **Reward Management**: `claim()` to withdraw rewards, `sync()` to update reward state

### Key Features

- **Reward Distribution**: Rewards are distributed proportionally to all stakers
- **Configurable Timelock**: Withdrawal delay can be set up to 7 days (can be reduced or disabled by owner)
- **Enhanced Security**: 
  - Uses ReentrancyGuard for all external functions
  - Implements checks-effects-interactions pattern
  - SafeERC20 for token transfers
  - Owner cannot increase timelock beyond 7 days
- **Comprehensive Testing**: Extensive test suite including fuzz testing and complex scenarios

### Admin Functions

- `transferOwnership(address newOwner)`: Transfer contract ownership
- `setWithdrawalDelay(uint256 newDelay)`: Configure withdrawal timelock (up to 7 days)

## Documentation

The protocol is thoroughly documented through:
- Comprehensive NatSpec comments in the smart contracts
- Extensive test suite demonstrating all functionality
- This README for high-level overview and usage instructions

For security considerations and responsible disclosure, please see [SECURITY.md](./SECURITY.md).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
