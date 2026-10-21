// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title YieldFarmingPool
 * @dev Implementation of the yield farming pool contract.
 */
contract YieldFarmingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Pool {
        address token;
        uint256 totalStaked;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        bool isActive;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastClaimedTime;
    }

    IERC20 public immutable rewardToken;
    mapping(bytes32 => Pool) public pools;
    mapping(bytes32 => mapping(address => UserInfo)) public userInfo;
    bytes32[] public activePools;

    // Events
    event PoolCreated(bytes32 indexed poolId, address indexed token, uint256 rewardRate);
    event PoolUpdated(bytes32 indexed poolId, uint256 rewardRate, bool isActive);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Withdrawn(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardClaimed(bytes32 indexed poolId, address indexed user, uint256 reward);

    constructor(address _rewardToken) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
    }

    /**
     * @dev Creates a new yield farming pool.
     * @param token The address of the token to be staked.
     * @param rewardRate The rate at which rewards are distributed.
     * @return poolId The ID of the newly created pool.
     */
    function createPool(address token, uint256 rewardRate) external onlyOwner returns (bytes32 poolId) {
        require(token != address(0), "Invalid token address");
        require(rewardRate > 0, "Reward rate must be greater than zero");

        poolId = keccak256(abi.encodePacked(token, rewardRate, block.timestamp, block.chainid));

        require(pools[poolId].token == address(0), "Pool already exists");
        pools[poolId] = Pool({
            token: token,
            totalStaked: 0,
            rewardRate: rewardRate,
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            isActive: true
        });
        activePools.push(poolId);
        emit PoolCreated(poolId, token, rewardRate);
    }

    /**
     * @dev Stakes tokens in the specified pool.
     * @param amountToStake The amount of tokens to stake.
     * @param poolId The ID of the pool in which to stake tokens.
     */
    function stakeTokens(uint256 amountToStake, bytes32 poolId) external {
        Pool storage pool = pools[poolId];
        require(pool.isActive, "Pool is not active");
        require(amountToStake > 0, "Amount must be greater than 0");

        UserInfo storage user = userInfo[poolId][msg.sender];

        IERC20(pool.token).safeTransferFrom(msg.sender, address(this), amountToStake);

        user.amount += amountToStake;
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18; // we must remove 1e18 decimals due to multiplication

        pool.lastUpdateTime = block.timestamp;
        pool.totalStaked += amountToStake;

        emit Staked(poolId, msg.sender, amountToStake);
    }

    /**
     * @dev Unstakes tokens from the specified pool.
     * @param amountToUnstake The amount of tokens to unstake.
     * @param poolId The ID of the pool from which to unstake tokens.
     */
    function unstakeTokens(uint256 amountToUnstake, bytes32 poolId) external {
        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][msg.sender];
        require(pool.isActive, "Pool is not active");
        require(amountToUnstake > 0, "Amount must be greater than 0");
        require(user.amount >= amountToUnstake, "Please unstake valid amount");

        _updatePool(poolId);

        // calculate rewards
        uint256 rewardsAmount = _calculateUserPoolRewards(poolId, msg.sender);
        if (rewardsAmount > 0) {
            // transfer the reward token to the user
            _safeRewardTransfer(msg.sender, rewardsAmount);
        }

        user.amount -= amountToUnstake;
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18;

        pool.totalStaked -= amountToUnstake;

        // transfer the deposited tokens back to the user
        IERC20(pool.token).safeTransfer(msg.sender, amountToUnstake);
        emit Withdrawn(poolId, msg.sender, amountToUnstake);
    }

    /**
     * @dev Claims rewards for the specified pool.
     * @param poolId The ID of the pool for which to claim rewards.
     */
    function claimRewards(bytes32 poolId) external nonReentrant {
        _updatePool(poolId);

        uint256 rewardsAmount = _calculateUserPoolRewards(poolId, msg.sender);
        require(rewardsAmount > 0, "No rewards to claim");

        UserInfo storage user = userInfo[poolId][msg.sender];
        user.rewardDebt = user.amount * pools[poolId].rewardPerTokenStored / 1e18;
        user.lastClaimedTime = block.timestamp;

        _safeRewardTransfer(msg.sender, rewardsAmount);

        emit RewardClaimed(poolId, msg.sender, rewardsAmount);
    }

    /**
     * @dev Returns the encoded data of a specific pool.
     * @param poolId The ID of the pool to retrieve.
     * @return encodedData The encoded data of the pool.
     */
    function getPoolEncodedData(bytes32 poolId) external view returns (bytes memory encodedData) {
        Pool storage pool = pools[poolId];
        encodedData = abi.encodePacked(
            pool.token, pool.totalStaked, pool.rewardRate, pool.lastUpdateTime, pool.rewardPerTokenStored, pool.isActive
        );
    }

    /**
     * @dev Returns the hash of a specific user in a pool.
     * @param poolId The ID of the pool.
     * @param userAddress The address of the user.
     * @return userHash The hash of the user.
     */
    function getUserHash(bytes32 poolId, address userAddress) external pure returns (bytes32 userHash) {
        userHash = keccak256(abi.encodePacked(poolId, userAddress, "YIELD_FARMING_USER"));
    }

    /**
     * @dev Returns the count of active pools.
     * @return The number of active pools.
     */
    function getActivePoolsCount() external view returns (uint256) {
        return activePools.length;
    }

    /**
     * @dev Returns the list of active pools.
     * @return The array of active pool IDs.
     */
    function getActivePools() external view returns (bytes32[] memory) {
        return activePools;
    }

    /**
     * @dev Withdraws tokens from the contract in case of emergency.
     * @param token The address of the token to withdraw.
     * @param amount The amount of tokens to withdraw.
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Updates the reward rate for a specific pool.
     * @param poolId The ID of the pool to update.
     * @param newRewardRate The new reward rate.
     */
    function updatePoolRewardRate(bytes32 poolId, uint256 newRewardRate) external onlyOwner {
        Pool storage pool = pools[poolId];
        require(pool.isActive, "Pool is not active");
        require(newRewardRate > 0, "Reward rate must be greater than zero");

        _updatePool(poolId);
        pool.rewardRate = newRewardRate;

        emit PoolUpdated(poolId, newRewardRate, pool.isActive);
    }

    /**
     * @dev Internal function to safely transfer reward tokens.
     * @param to The address to which the reward tokens will be transferred.
     * @param amount The amount of reward tokens to transfer.
     */
    function _safeRewardTransfer(address to, uint256 amount) internal {
        IERC20(rewardToken).safeTransferFrom(address(this), to, amount);
    }

    /**
     * @dev Internal function to calculate rewards for a user in a specific pool.
     * @param poolId The ID of the pool.
     * @param userAddress The address of the user.
     * @return The amount of rewards the user is entitled to.
     */
    function _calculateUserPoolRewards(bytes32 poolId, address userAddress) internal view returns (uint256) {
        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][userAddress];

        uint256 rewardPerToken = pool.rewardPerTokenStored;
        if (pool.totalStaked > 0) {
            rewardPerToken += (block.timestamp - pool.lastUpdateTime) * pool.rewardRate * 1e18 / pool.totalStaked;
        }

        return (user.amount * rewardPerToken / 1e18) - user.rewardDebt;
    }

    /**
     * @dev Internal function to update the pool's reward information.
     * @param poolId The ID of the pool to update.
     */
    function _updatePool(bytes32 poolId) internal {
        Pool storage pool = pools[poolId];
        if (block.timestamp > pool.lastUpdateTime) {
            if (pool.totalStaked > 0) {
                pool.rewardPerTokenStored += (block.timestamp - pool.lastUpdateTime) * pool.rewardRate * 1e18
                    / pool.totalStaked;
            }
            pool.lastUpdateTime = block.timestamp;
        }
    }
}
