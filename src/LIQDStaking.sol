// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title LIQDStaking
 * @notice A staking contract for LIQD tokens with HYPE rewards distribution
 * @dev This contract implements a direct staking mechanism where users stake LIQD
 * and earn HYPE rewards proportional to their stake. It includes configurable 
 * timelock for withdrawals and standard security protections against reentrancy.
 *
 * Core Mechanics:
 * 1. Stake LIQD tokens directly
 * 2. Earn HYPE rewards proportional to staked LIQD amount
 * 3. Two-step withdrawal process with configurable timelock (up to 7 days)
 * 4. One-step claim process for rewards
 *
 * -----------------------------------------------------------------------------------
 * DEVELOPER DOCUMENTATION
 * -----------------------------------------------------------------------------------
 *
 * === STAKING MECHANISM ===
 *
 * Users stake LIQD tokens directly. The contract tracks each user's staked amount
 * and the total staked LIQD. All staked tokens remain in the contract until withdrawn.
 *
 * === REWARD SYSTEM ===
 *
 * Rewards are distributed in HYPE and tracked using:
 * - rewardPerTokenAccumulated: Global accumulator for rewards per token
 * - userRewardPerTokenPaid: User's checkpoint of the global accumulator
 * - rewards: User's accumulated rewards pending
 * - totalRewardsDistributed: Global tracker for total rewards distributed
 * - totalRewardsEarned: Total rewards earned by each user lifetime
 *
 * The reward calculation: earned = rewards + (stakedAmount * (rewardPerTokenAccumulated - userRewardPerTokenPaid) / 1e18)
 *
 * Rewards can only be added if there are active stakers in the contract.
 * Any HYPE sent to the contract (via addReward, direct transfer, or fallback function) will be 
 * distributed as rewards proportionally to all stakers based on their stake.
 *
 * === REWARD CLAIMING ===
 *
 * Rewards are claimed through a simple one-step process using the claim() function.
 * Users can claim their earned HYPE rewards at any time without affecting their staked LIQD.
 *
 * === WITHDRAWAL PROCESS ===
 *
 * Two-step process:
 * 1. Initiate unstaking: Creates a timelock based on current withdrawalDelay (up to 7 days)
 * 2. Complete withdrawal: After timelock expires, withdraw original LIQD tokens
 *
 * This timelock provides security against certain attack vectors and can be configured by the contract owner.
 * The owner can reduce the timelock delay or disable it entirely, but cannot increase it beyond 7 days.
 * Note that modifying the timelock only affects new unstaking operations; existing pending withdrawals 
 * maintain their original timelock period.
 *
 * === SECURITY CONSIDERATIONS ===
 *
 * - The contract uses ReentrancyGuard to prevent reentrancy attacks
 * - SafeERC20 is used for all token transfers to handle non-compliant tokens
 * - Owner cannot increase the withdrawal timelock beyond 7 days
 * - Token approval should be set to the exact amount to be staked for additional security
 * -----------------------------------------------------------------------------------
 */
contract LIQDStaking is ReentrancyGuard {
    using Address for address payable;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverted when attempting to use the zero address
    error ZeroAddress();
    
    /// @notice Reverted when attempting to stake/unstake zero tokens
    error ZeroValue();
    
    /// @notice Reverted when attempting to unstake more than staked
    /// @param available The user's current staked balance
    /// @param required The amount the user is trying to unstake
    error InsufficientBalance(uint256 available, uint256 required);
    
    /// @notice Reverted when attempting to withdraw without any pending withdrawal
    error NoPendingWithdrawal();
    
    /// @notice Reverted when attempting to withdraw before timelock expires
    /// @param unlockTime Timestamp when withdrawal becomes available
    /// @param currentTime Current block timestamp
    error WithdrawalLocked(uint256 unlockTime, uint256 currentTime);
    
    /// @notice Reverted when a token transfer fails
    error TransferFailed();
    
    /// @notice Reverted when token approval is insufficient
    /// @param available Current allowance for the contract
    /// @param required Amount needed to complete the operation
    error InsufficientAllowance(uint256 available, uint256 required);
    
    /// @notice Reverted when claiming with no pending rewards
    error NoPendingRewards();
    
    /// @notice Reverted when attempting to add rewards with no stakers
    error NoStakers();
    
    /// @notice Reverted when non-owner calls owner-only functions
    error Unauthorized();
    
    /// @notice Reverted when attempting to set timelock higher than maximum
    error ExceedsMaxDelay();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address that can configure contract parameters
    address public owner;
    
    /// @notice The ERC20 token used for staking (LIQD)
    IERC20 public immutable stakingToken;

    /// @notice Total amount of tokens staked in the contract
    uint256 public totalStaked;
    
    /// @notice Mapping of user address to their staked amount
    mapping(address => uint256) public stakedAmount;
    
    /// @notice Current withdrawal delay in seconds (configurable)
    uint256 public withdrawalDelay = 7 days;
    
    /// @notice Maximum allowed withdrawal delay (7 days, cannot be exceeded)
    uint256 public constant MAX_WITHDRAWAL_DELAY = 7 days;
    
    /// @notice Structure for tracking pending withdrawals
    struct PendingWithdrawal {
        uint256 amount;     // Amount of LIQD tokens pending withdrawal
        uint256 unlockTime; // Timestamp when tokens become available for withdrawal
    }
    
    /// @notice Mapping of user address to their pending withdrawal
    mapping(address => PendingWithdrawal) public pendingWithdrawals;

    /// @notice Global accumulator for rewards per token, scaled by 1e18
    uint256 public rewardPerTokenAccumulated;
    
    /// @notice User's checkpoint of the global accumulator
    mapping(address => uint256) public userRewardPerTokenPaid;
    
    /// @notice User's accumulated rewards pending to be claimed
    mapping(address => uint256) public rewards;
    
    /// @notice Total HYPE rewards distributed to the contract
    uint256 public totalRewardsDistributed;
    
    /// @notice Total rewards earned by each user (lifetime)
    mapping(address => uint256) public totalRewardsEarned;
    
    /// @notice Total rewards claimed by all users
    uint256 public totalRewardsClaimed;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user stakes tokens
    /// @param user Address of the user who staked
    /// @param amount Amount of tokens staked
    event Staked(address indexed user, uint256 amount);
    
    /// @notice Emitted when a user initiates unstaking
    /// @param user Address of the user
    /// @param amount Amount of tokens unstaked
    /// @param unlockTime Timestamp when tokens become available
    event UnstakeInitiated(
        address indexed user,
        uint256 amount,
        uint256 unlockTime
    );
    
    /// @notice Emitted when a user increases their unstaking amount
    /// @param user Address of the user
    /// @param newAmount New total amount pending withdrawal
    /// @param newUnlockTime New unlock timestamp
    event UnstakeAmountIncreased(
        address indexed user,
        uint256 newAmount,
        uint256 newUnlockTime
    );
    
    /// @notice Emitted when a user completes withdrawal
    /// @param user Address of the user
    /// @param amount Amount of tokens withdrawn
    event WithdrawalCompleted(address indexed user, uint256 amount);

    /// @notice Emitted when rewards are paid to a user
    /// @param user Address of the user
    /// @param reward Amount of HYPE rewards paid
    event RewardPaid(address indexed user, uint256 reward);
    
    /// @notice Emitted when rewards are added to the contract
    /// @param amount Amount of HYPE rewards added
    /// @param from Address that sent the rewards
    event RewardAdded(uint256 amount, address indexed from);
    
    /// @notice Emitted when the global reward rate is updated
    /// @param oldValue Previous reward per token value
    /// @param newValue New reward per token value
    event RewardPerTokenUpdated(uint256 oldValue, uint256 newValue);
    
    /// @notice Emitted when ownership is transferred
    /// @param oldOwner Previous owner address
    /// @param newOwner New owner address
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    
    /// @notice Emitted when withdrawal delay is updated
    /// @param oldDelay Previous delay in seconds
    /// @param newDelay New delay in seconds
    event WithdrawalDelayUpdated(uint256 oldDelay, uint256 newDelay);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the staking contract
     * @dev Sets up the staking token using the provided address and assigns the deployer as owner
     * @param _stakingToken Address of the LIQD token
     */
    constructor(address _stakingToken) {
        if (_stakingToken == address(0)) revert ZeroAddress();
        stakingToken = IERC20(_stakingToken);
        owner = msg.sender; // Set deployer as the initial owner
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Modifier to restrict access to owner only
     * @dev Reverts with Unauthorized if caller is not the owner
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /**
     * @notice Transfers ownership of the contract to a new account
     * @dev Can only be called by the current owner
     * @param newOwner The address of the new owner (cannot be zero address)
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @notice Modifies the global timelock for withdrawals
     * @dev Can set to 0 to disable timelock or any value up to MAX_WITHDRAWAL_DELAY (7 days)
     * @dev This only affects new unstaking operations; existing pending withdrawals are unaffected
     * @param newDelay The new timelock period in seconds
     */
    function setWithdrawalDelay(uint256 newDelay) external onlyOwner {
        if (newDelay > MAX_WITHDRAWAL_DELAY) revert ExceedsMaxDelay();
        uint256 oldDelay = withdrawalDelay;
        withdrawalDelay = newDelay;
        emit WithdrawalDelayUpdated(oldDelay, newDelay);
    }

    /*//////////////////////////////////////////////////////////////
                        CORE STAKING OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows a user to stake LIQD tokens
     * @dev Updates staked amount tracking and transfers tokens to the contract
     * @dev Rewards are updated before staking to ensure accurate reward calculation
     * @param amount The amount of LIQD tokens to stake (non-zero)
     */
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroValue();

        // Update reward state before staking
        _syncReward(msg.sender);

        // Update staking data
        stakedAmount[msg.sender] += amount;
        totalStaked += amount;

        // Check allowance before transferring tokens
        uint256 allowance = stakingToken.allowance(msg.sender, address(this));
        if (allowance < amount) revert InsufficientAllowance(allowance, amount);

        // Transfer staking tokens from user to contract using SafeERC20
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Initiates the unstaking process (step 1 of withdrawal)
     * @dev Updates rewards and creates/updates pending withdrawal with current timelock
     * @dev Passing 0 as amount will unstake all of the user's staked tokens
     * @param amount Amount of LIQD tokens to unstake (0 = all)
     */
    function unstake(uint256 amount) external nonReentrant {
        // Get user staked amount
        uint256 userStakedAmount = stakedAmount[msg.sender];

        // Explicitly validate input parameter
        if (amount > 0) {
            // Check if user has sufficient balance for the specified amount
            if (userStakedAmount < amount)
                revert InsufficientBalance(userStakedAmount, amount);
        }

        // Update rewards before unstaking
        _syncReward(msg.sender);

        // Determine amount to unstake (if 0, unstake all)
        uint256 unstakeAmount = amount;
        if (unstakeAmount == 0) {
            unstakeAmount = userStakedAmount;
        }

        // Double check again to ensure we're not unstaking zero
        if (unstakeAmount == 0) revert ZeroValue();

        // Get current unlock time (using the current withdrawal delay)
        uint256 unlockTime = block.timestamp + withdrawalDelay;

        // Check if user already has a pending withdrawal
        PendingWithdrawal storage withdrawal = pendingWithdrawals[msg.sender];
        if (withdrawal.amount > 0) {
            // Update the existing withdrawal by combining amounts and resetting the timer
            withdrawal.amount += unstakeAmount;
            withdrawal.unlockTime = unlockTime;

            emit UnstakeAmountIncreased(
                msg.sender,
                withdrawal.amount,
                unlockTime
            );
        } else {
            // Create a new pending withdrawal
            pendingWithdrawals[msg.sender] = PendingWithdrawal({
                amount: unstakeAmount,
                unlockTime: unlockTime
            });

            emit UnstakeInitiated(msg.sender, unstakeAmount, unlockTime);
        }

        // Update staking data
        stakedAmount[msg.sender] -= unstakeAmount;
        totalStaked -= unstakeAmount;
    }

    /**
     * @notice Completes the withdrawal process (step 2 of withdrawal)
     * @dev After the timelock period expires, allows user to withdraw their LIQD tokens
     * @dev Reverts if no pending withdrawal exists or timelock hasn't expired
     */
    function withdraw() external nonReentrant {
        // Get the user's pending withdrawal
        PendingWithdrawal storage withdrawal = pendingWithdrawals[msg.sender];

        // Verify there is a pending withdrawal
        if (withdrawal.amount == 0) revert NoPendingWithdrawal();

        // Check if the lock period has passed
        if (block.timestamp < withdrawal.unlockTime) {
            revert WithdrawalLocked(withdrawal.unlockTime, block.timestamp);
        }

        // Get the withdrawal amount and clear the pending withdrawal
        uint256 amount = withdrawal.amount;
        delete pendingWithdrawals[msg.sender];

        // Transfer the staking tokens (LIQD) back to the user
        stakingToken.safeTransfer(msg.sender, amount);

        emit WithdrawalCompleted(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        REWARD MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows anyone to add HYPE rewards to the staking contract
     * @dev Reverts if there are no stakers or if no value is sent
     * @dev Distributes rewards proportionally to all stakers based on their stake
     */
    function addReward() external payable nonReentrant {
        if (msg.value == 0) revert ZeroValue();
        if (totalStaked == 0) revert NoStakers();

        // Process the reward
        _distribute(msg.value, msg.sender);
        
        // Track total rewards distributed
        unchecked {
            totalRewardsDistributed += msg.value;
        }
    }

    /**
     * @notice Claims earned HYPE rewards
     * @dev Single-step claim process for rewards
     * @dev Rewards are updated before claiming to ensure all earned rewards are included
     */
    function claim() external nonReentrant {
        // First sync rewards to update the user's reward state
        _syncReward(msg.sender);
        
        // Get the current rewards
        uint256 reward = rewards[msg.sender];
        if (reward == 0) revert NoPendingRewards();
        
        // Clear rewards
        rewards[msg.sender] = 0;
        
        // Safety check to verify the contract has enough balance
        if (address(this).balance < reward) revert TransferFailed();

        // Update total rewards claimed and earned
        unchecked {
            totalRewardsClaimed += reward;
            totalRewardsEarned[msg.sender] += reward;
        }

        // Send rewards to user
        (bool success, ) = payable(msg.sender).call{value: reward}("");
        if (!success) revert TransferFailed();

        emit RewardPaid(msg.sender, reward);
    }

    /**
     * @notice Allows the contract to receive HYPE rewards via direct transfers
     * @dev Processes the HYPE as rewards, reverts if there are no stakers
     * @dev Has same effect as calling addReward()
     */
    receive() external payable nonReentrant {
        if (msg.value > 0) {
            if (totalStaked == 0) revert NoStakers();
            
            // Process the reward
            _distribute(msg.value, msg.sender);
            
            // Track total rewards distributed
            unchecked {
                totalRewardsDistributed += msg.value;
            }
        }
    }

    /**
     * @notice Fallback function to handle HYPE sent with function calls that don't exist
     * @dev Processes the HYPE as rewards exactly like receive(), reverts if there are no stakers
     */
    fallback() external payable nonReentrant {
        if (msg.value > 0) {
            if (totalStaked == 0) revert NoStakers();
            
            // Process the reward
            _distribute(msg.value, msg.sender);
            
            // Track total rewards distributed
            unchecked {
                totalRewardsDistributed += msg.value;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the current reward per staked token
     * @return Current reward per token value
     */
    function rewardRate() public view returns (uint256) {
        return rewardPerTokenAccumulated;
    }

    /**
     * @notice Calculates the HYPE rewards earned by an account
     * @dev Includes stored rewards based on current staked amount
     * @param account The address to calculate rewards for
     * @return Total earned HYPE rewards for the account
     */
    function earned(address account) public view returns (uint256) {
        // Cache values to avoid multiple storage reads
        uint256 userStaked = stakedAmount[account];
        uint256 currentRewards = rewards[account];
        uint256 userRewardPaid = userRewardPerTokenPaid[account];
        uint256 currentRewardPerToken = rewardRate();

        // If user has no staked tokens, they can only have what's already accumulated in rewards
        if (userStaked == 0) {
            return currentRewards;
        }

        // Calculate new earnings based on the increase in rewardPerToken since last update
        uint256 rewardPerTokenDelta;
        unchecked {
            // Safe because rewards can only increase
            rewardPerTokenDelta = currentRewardPerToken - userRewardPaid;
        }
        uint256 newEarnings = Math.mulDiv(
            userStaked,
            rewardPerTokenDelta,
            1e18
        );

        // Safe because rewards can only increase
        unchecked {
            return currentRewards + newEarnings;
        }
    }

    /**
     * @notice Gets comprehensive account information in a single call
     * @dev Convenient function for UI integration
     * @param account The address to check
     * @return stakedTokens The account's staked tokens
     * @return currentRewards The account's accruing HYPE rewards
     * @return pendingWithdrawalAmount Amount of LIQD tokens pending withdrawal
     * @return withdrawalUnlockTime Timestamp when tokens become available
     * @return isWithdrawalClaimable Whether the pending withdrawal can be claimed now
     * @return totalLifetimeRewards Total rewards earned by the user (claimed + pending)
     * @return remainingLockTime Time in seconds until withdrawal is available (0 if ready or no pending withdrawal)
     */
    function getAccountInfo(
        address account
    )
        external
        view
        returns (
            uint256 stakedTokens,
            uint256 currentRewards,
            uint256 pendingWithdrawalAmount,
            uint256 withdrawalUnlockTime,
            bool isWithdrawalClaimable,
            uint256 totalLifetimeRewards,
            uint256 remainingLockTime
        )
    {
        stakedTokens = stakedAmount[account];
        currentRewards = earned(account);

        // Read withdrawal info in a single storage access
        PendingWithdrawal storage withdrawal = pendingWithdrawals[account];
        pendingWithdrawalAmount = withdrawal.amount;
        withdrawalUnlockTime = withdrawal.unlockTime;
        
        // Calculate claimable status and remaining lock time
        isWithdrawalClaimable = (pendingWithdrawalAmount > 0) && (block.timestamp >= withdrawalUnlockTime);
        
        // Calculate remaining lock time
        if (pendingWithdrawalAmount == 0 || block.timestamp >= withdrawalUnlockTime) {
            remainingLockTime = 0;
        } else {
            remainingLockTime = withdrawalUnlockTime - block.timestamp;
        }
        
        // Calculate total lifetime rewards
        totalLifetimeRewards = totalRewardsEarned[account] + currentRewards;

        return (
            stakedTokens,
            currentRewards,
            pendingWithdrawalAmount,
            withdrawalUnlockTime,
            isWithdrawalClaimable,
            totalLifetimeRewards,
            remainingLockTime
        );
    }

    /**
     * @notice Gets comprehensive staking statistics in a single call
     * @dev Convenient function for UI integration
     * @return totalStakedTokens Total tokens staked in the contract
     * @return currentRewardRate Current reward per token accumulated
     * @return totalDistributed Total rewards distributed to the contract
     * @return totalClaimed Total rewards claimed by all users
     * @return totalUnclaimed Total rewards not yet claimed
     * @return contractBalance Current contract balance in HYPE
     */
    function getStakingStats()
        external
        view
        returns (
            uint256 totalStakedTokens,
            uint256 currentRewardRate,
            uint256 totalDistributed,
            uint256 totalClaimed,
            uint256 totalUnclaimed,
            uint256 contractBalance
        )
    {
        totalStakedTokens = totalStaked;
        currentRewardRate = rewardPerTokenAccumulated;
        totalDistributed = totalRewardsDistributed;
        totalClaimed = totalRewardsClaimed;
        totalUnclaimed = totalDistributed > totalClaimed ? totalDistributed - totalClaimed : 0;
        contractBalance = address(this).balance;
        
        return (
            totalStakedTokens,
            currentRewardRate,
            totalDistributed,
            totalClaimed,
            totalUnclaimed,
            contractBalance
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Processes rewards and updates the global accumulator
     * @param amount Amount of HYPE to add as rewards
     * @param sender Address that sent the rewards
     */
    function _distribute(
        uint256 amount,
        address sender
    ) internal {
        // Emit event before state changes to prevent potential reentrancy issues with listeners
        emit RewardAdded(amount, sender);

        // Calculate reward per token based on current total staked
        uint256 oldValue = rewardPerTokenAccumulated;
        unchecked {
            // Math.mulDiv ensures safe multiplication/division
            rewardPerTokenAccumulated += Math.mulDiv(
                amount,
                1e18,
                totalStaked
            );
        }
        emit RewardPerTokenUpdated(oldValue, rewardPerTokenAccumulated);
    }

    /**
     * @dev Updates reward state for an account
     * @param account The address to update rewards for
     * @notice This function calculates the current pending rewards for an account and updates the reward state.
     * It is called before any stake/unstake operation and before claiming rewards.
     */
    function _syncReward(address account) internal {
        // Cache the current reward per token
        uint256 currentRewardPerToken = rewardRate();

        // Calculate earned rewards
        uint256 userRewards = rewards[account];
        uint256 userStaked = stakedAmount[account];

        if (userStaked > 0) {
            uint256 rewardDelta;
            unchecked {
                // Safe because rewards always increase
                rewardDelta =
                    currentRewardPerToken -
                    userRewardPerTokenPaid[account];
            }

            if (rewardDelta > 0) {
                uint256 newEarnings = Math.mulDiv(
                    userStaked,
                    rewardDelta,
                    1e18
                );
                unchecked {
                    // Safe because we're only adding positive values
                    userRewards += newEarnings;
                }
            }
        }

        // Update user's rewards and checkpoint
        rewards[account] = userRewards;
        userRewardPerTokenPaid[account] = currentRewardPerToken;
    }
} 