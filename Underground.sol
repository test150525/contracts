// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Underground is OwnableUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // ERC20 Token Interface
    IERC20 public token;

    // Staking parameters
    uint256 public minimumLockPeriod;
    uint256 public minimumStakeAmount; // Minimum amount to stake
    uint256 public minimumUnstakeAmount; // Minimum amount to unstake
    uint256 public minimumClaimRewardAmount; // Minimum amount to claim reward

    // Minimum reward per user during distribution
    uint256 public minimumRewardPerUser;

    // Rewards pool
    uint256 public totalRewardsPool;

    // Title thresholds
    struct Title {
        string name;
        uint256 expThreshold;
        uint256 minStakeAmount; // Minimum staked amount required
        uint256 multiplier; // Multiplier in basis points (e.g., 125 = 1.25x)
    }

    Title[] public titles;

    // User information
    struct UserInfo {
        uint256 stakedAmount;
        uint256 stakeTimestamp;
        uint256 exp;
        uint256 lastUpdated;
        uint256 pendingRewards;
        string currentTitle;
    }

    mapping(address => UserInfo) public users;
    address[] public keys;
    mapping(address => uint256) private keyIndex;

    struct Statistic {
        uint256 membersCount;
        uint256 padaVolume;
    }

    struct AllData {
        uint256 balance;
        uint256 rewards;
        uint256 stakeTimestamp;
        uint256 minimumLockPeriod;
        uint256 minimumStakeAmount;
        uint256 minimumUnstakeAmount;
        uint256 minimumClaimRewardAmount;
    }

    // Total staked tokens
    uint256 public totalStaked;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, bool fullUnstake);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsAdded(uint256 amount);
    event TitleUpdated(address indexed user, string newTitle);
    event TitleAdded(
        string name,
        uint256 expThreshold,
        uint256 minStakeAmount,
        uint256 multiplier
    );
    event TitleRemoved(string name);

    function initialize(
        address initialOwner,
        IERC20 tokenArg,
        uint256 minimumStakeAmountArg,
        uint256 minimumUnstakeAmountArg,
        uint256 minimumClaimRewardAmountArg,
        uint256 minimumRewardPerUserArg
    ) external initializer {
        __Ownable_init(initialOwner);
        __AccessControl_init();
        __ReentrancyGuard_init();

        _transferOwnership(initialOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(ADMIN_ROLE, initialOwner);

        token = tokenArg;
        minimumStakeAmount = minimumStakeAmountArg;
        minimumUnstakeAmount = minimumUnstakeAmountArg;
        minimumClaimRewardAmount = minimumClaimRewardAmountArg;
        minimumRewardPerUser = minimumRewardPerUserArg;
        minimumLockPeriod = 1 days;

        // Initialize titles with minStakeAmount required
        titles.push(Title("Novice", 0, minimumStakeAmountArg, 100)); // 1.00x
        titles.push(Title("Apprentice", 100, minimumStakeAmountArg, 105)); // 1.05x
        titles.push(Title("Adept", 500, minimumStakeAmountArg, 110)); // 1.10x
        titles.push(Title("Expert", 1000, minimumStakeAmountArg * 10, 140)); // 1.40x
        titles.push(Title("Master", 2000, minimumStakeAmountArg * 20, 160)); // 1.60x
    }

    // Function to stake tokens
    function stake(uint256 amountArg) public nonReentrant {
        require(amountArg >= minimumStakeAmount, "Amount is less than the minimum stake"  );

        UserInfo storage user = users[msg.sender];

        // Update user's staked amount and total staked
        user.stakedAmount += amountArg;
        totalStaked += amountArg;

        // Set stake timestamp if it's a new stake
        if (user.stakeTimestamp == 0) {
            user.stakeTimestamp = block.timestamp;
        }

        bool presentInArray = false;
        uint256 len = keys.length;
        for (uint256 i = 0; i < len; i++) {
            if (msg.sender == keys[i]) {
                presentInArray = true;
                break;
            }
        }

        if (!presentInArray) {
            keys.push(msg.sender);
            keyIndex[msg.sender] = keys.length - 1;
        }

        // Update user's title if necessary
        _updateUserTitle(msg.sender);

        // Transfer tokens to contract
        require(token.transferFrom(msg.sender, address(this), amountArg), "Transfer failed");

        emit Staked(msg.sender, amountArg);
    }

    // Function to unstake tokens
    function unstake(uint256 amountArg) public nonReentrant {
        UserInfo storage user = users[msg.sender];
        require(user.stakedAmount >= amountArg, "Insufficient staked amount");

        // Check if minimum lock period has passed
        require(
            block.timestamp >= user.stakeTimestamp + minimumLockPeriod,
            "Tokens are still locked"
        );

        bool fullUnstake = false;

        // Check if it's a full unstake
        if (amountArg == user.stakedAmount) {
            fullUnstake = true;
        } else {
            // Partial unstake: enforce minimum unstake amount
            require(
                amountArg >= minimumUnstakeAmount,
                "Unstake amount is less than the minimum unstake amount"
            );

            // Calculate remaining balance after unstake
            uint256 remainingBalance = user.stakedAmount - amountArg;

            // If remaining balance is less than minimum stake amount, force full unstake
            if (remainingBalance < minimumStakeAmount) {
                amountArg = user.stakedAmount;
                fullUnstake = true;
            }
        }

        if (fullUnstake) {
            // Full unstake: reset user's staking data
            user.stakedAmount = 0;
            user.stakeTimestamp = 0;
            user.lastUpdated = 0;
            user.currentTitle = "Unranked";

            uint256 index = keyIndex[msg.sender];
            uint256 lastIndex = keys.length - 1;
            address lastAddress = keys[lastIndex];

            keys[index] = lastAddress;
            keyIndex[lastAddress] = index;

            keys.pop();
            delete keyIndex[msg.sender];
        } else {
            // Partial unstake: update staked amount
            user.stakedAmount -= amountArg;
            // Update user's title if necessary
            _updateUserTitle(msg.sender);
        }

        // Update total staked
        totalStaked -= amountArg;

        // Transfer tokens back to user
        require(token.transfer(msg.sender, amountArg), "Transfer failed");

        emit Unstaked(msg.sender, amountArg, fullUnstake);
    }

    function getStatistics() public view returns (Statistic memory) {
        return Statistic(keys.length, token.balanceOf(address(this)));
    }

    function getBalance(
        address accountArg
    ) public view returns (uint256 balance) {
        UserInfo storage user = users[accountArg];
        return user.stakedAmount;
    }

    function getReward(address accountArg) public view returns (uint256 reward) {
        UserInfo storage user = users[accountArg];
        return user.pendingRewards;
    }

    function getAllData(address accountArg) public view returns (AllData memory) {
        UserInfo storage user = users[accountArg];
        return AllData(
            user.stakedAmount,
            user.pendingRewards,
            user.stakeTimestamp,
            minimumLockPeriod,
            minimumStakeAmount,
            minimumUnstakeAmount,
            minimumClaimRewardAmount
        );
    }

    // Function to claim rewards
    function claimRewards() public {
        UserInfo storage user = users[msg.sender];

        uint256 rewards = user.pendingRewards;
        require(rewards >= minimumClaimRewardAmount, "Amount is less than the minimum claim reward");
        require(rewards > 0, "No rewards to claim");

        user.pendingRewards = 0;

        emit RewardsClaimed(msg.sender, rewards);
        require(token.transfer(msg.sender, rewards), "Transfer failed");
    }

    // Function to add rewards to the pool (to be called by admin)
    function sendRewards(uint256 amountArg) public onlyRole(ADMIN_ROLE) {
        require(amountArg > 0, "Cannot add zero rewards");

        totalRewardsPool += amountArg;

        _updateRewards();

        emit RewardsAdded(amountArg);
    }

    // Internal function to update rewards for all users
    function _updateRewards() internal {
        uint256 numberOfUsers = keys.length;
        uint256 totalRequiredMinimumRewards = minimumRewardPerUser *
            numberOfUsers;

        if (totalRewardsPool < totalRequiredMinimumRewards) {
            // Insufficient rewards to distribute minimum to all users, hold rewards
            return;
        }

        uint256 remainingRewards = totalRewardsPool -
            totalRequiredMinimumRewards;

        // Calculate total adjusted shares
        uint256 totalAdjustedShares = 0;
        uint256[] memory adjustedShares = new uint256[](numberOfUsers);

        for (uint256 i = 0; i < numberOfUsers; i++) {
            address userAddress = keys[i];
            UserInfo storage user = users[userAddress];

            // Update EXP
            uint256 expGained = _calculateExp(userAddress);
            user.exp += expGained;

            // Update last updated timestamp
            user.lastUpdated = block.timestamp;

            uint256 adjustedShare = _calculateAdjustedShare(userAddress);
            adjustedShares[i] = adjustedShare;
            totalAdjustedShares += adjustedShare;

            // Update user's title if necessary
            _updateUserTitle(userAddress);
        }

        // Distribute remaining rewards based on adjusted shares
        for (uint256 i = 0; i < numberOfUsers; i++) {
            address userAddress = keys[i];
            UserInfo storage user = users[userAddress];

            // Allocate minimum reward
            uint256 totalReward = minimumRewardPerUser;

            // Allocate additional reward if there are remaining rewards
            if (remainingRewards > 0 && totalAdjustedShares > 0) {
                uint256 additionalReward = (adjustedShares[i] *
                    remainingRewards) / totalAdjustedShares;
                totalReward += additionalReward;
            }

            user.pendingRewards += totalReward;
        }

        // Reset totalRewardsPool after distribution
        totalRewardsPool = 0;
    }

    // Internal function to calculate adjusted share with multiplier
    function _calculateAdjustedShare(
        address userArg
    ) internal view returns (uint256) {
        if (totalStaked == 0) {
            return 0;
        }
        UserInfo storage user = users[userArg];
        uint256 multiplier = _getUserMultiplier(userArg);

        return (user.stakedAmount * 1e18 * multiplier) / (totalStaked * 100);
    }

    // Internal function to get user's multiplier based on current title
    function _getUserMultiplier(address userArg) internal view returns (uint256) {
        UserInfo storage user = users[userArg];
        uint256 len = titles.length;
        for (uint256 i = 0; i < len; i++) {
            if (
                keccak256(bytes(user.currentTitle)) ==
                keccak256(bytes(titles[i].name))
            ) {
                return titles[i].multiplier;
            }
        }
        return 100; // Default multiplier (1x) for "Unranked"
    }

    // Internal function to update user's title based on EXP and staked amount
    function _updateUserTitle(address userArg) internal {
        UserInfo storage user = users[userArg];
        string memory previousTitle = user.currentTitle;
        string memory newTitle = _determineTitle(user.exp, user.stakedAmount);

        if (
            keccak256(abi.encodePacked(newTitle)) !=
            keccak256(abi.encodePacked(previousTitle))
        ) {
            user.currentTitle = newTitle;
            emit TitleUpdated(userArg, newTitle);
        }
    }

    // Internal function to determine the appropriate title
    function _determineTitle(
        uint256 expArg,
        uint256 stakedAmountArg
    ) internal view returns (string memory) {
        uint256 len = titles.length;
        for (uint256 i = len; i > 0; i--) {
            Title memory title = titles[i - 1];
            if (
                expArg >= title.expThreshold &&
                stakedAmountArg >= title.minStakeAmount
            ) {
                return title.name;
            }
        }
        return "Unranked";
    }

    // Internal function to calculate user's EXP gain
    function _calculateExp(address userArg) internal view returns (uint256) {
        UserInfo storage user = users[userArg];
        if (user.lastUpdated == 0) {
            return 0;
        }
        uint256 timeDifference = block.timestamp - user.lastUpdated;
        // uint256 daysStaked = timeDifference / 1 days;

        uint256 levelIndex = _getTitleIndex(user.currentTitle);
        uint256 denominator = minimumUnstakeAmount * (levelIndex + 1);
        if (denominator == 0) {
            denominator = 1; // Avoid division by zero
        }

        return (user.stakedAmount * timeDifference) / 1 days / denominator;
    }

    // Internal function to get the index of a title by its name
    function _getTitleIndex(
        string memory titleName
    ) internal view returns (uint256) {
        uint256 len = titles.length;
        for (uint256 i = 0; i < len; i++) {
            if (
                keccak256(bytes(titles[i].name)) == keccak256(bytes(titleName))
            ) {
                return i;
            }
        }
        return 0; // Default to index 0 if title not found
    }

    function addAdmin(address account) external onlyOwner {
        grantRole(ADMIN_ROLE, account);
    }

    function removeAdmin(address account) external onlyOwner {
        revokeRole(ADMIN_ROLE, account);
    }

    function setMinimumRewardPerUser(
        uint256 amountArg
    ) external onlyRole(ADMIN_ROLE) {
        minimumRewardPerUser = amountArg;
    }

    // Function to add a new title at a specific position
    function addTitle(
        uint256 position,
        string memory name,
        uint256 expThreshold,
        uint256 minStakeAmount,
        uint256 multiplier
    ) external onlyRole(ADMIN_ROLE) {
        require(position <= titles.length, "Invalid position");

        // Insert the new title at the specified position
        titles.push(Title("", 0, 0, 0)); // Increase the array size

        uint256 len = titles.length - 1;
        for (uint256 i = len; i > position; i--) {
            titles[i] = titles[i - 1];
        }

        titles[position] = Title(
            name,
            expThreshold,
            minStakeAmount,
            multiplier
        );

        emit TitleAdded(name, expThreshold, minStakeAmount, multiplier);
    }

    // Function to remove a title at a specific position
    function removeTitle(uint256 position) external onlyRole(ADMIN_ROLE) {
        require(position < titles.length, "Invalid position");
        string memory removedTitleName = titles[position].name;

        uint256 len = titles.length - 1;
        for (uint256 i = position; i < len; i++) {
            titles[i] = titles[i + 1];
        }
        titles.pop();

        emit TitleRemoved(removedTitleName);
    }

    // Function to recalculate titles for all users
    function recalculateAllUserTitles() external onlyRole(ADMIN_ROLE) {
        uint256 numberOfUsers = keys.length;

        for (uint256 i = 0; i < numberOfUsers; i++) {
            address userAddress = keys[i];
            _updateUserTitle(userAddress);
        }
    }
}
