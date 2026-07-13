// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "../interfaces/IERC20.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { HeliosAccess } from "../security/HeliosAccess.sol";
import { DelegationManager } from "./DelegationManager.sol";
import { HeliosConstants, EpochData } from "../types/HeliosTypes.sol";

contract EpochRewarder {
    using SafeTransferLib for IERC20;

    error ZeroAddress();
    error OnlyVault(address sender);
    error UnauthorizedRewarder(address sender);
    error EpochAlreadyFunded(uint64 epochId);
    error EpochNotFunded(uint64 epochId);
    error EpochAlreadyFinalized(uint64 epochId);
    error InvalidEpochWindow(uint64 startsAt, uint64 endsAt);
    error InvalidReceiver();

    event VaultConfigured(address indexed vault);
    event DelegationManagerConfigured(address indexed delegationManager);
    event EpochFunded(
        uint64 indexed epochId,
        address indexed funder,
        uint256 amount,
        uint64 startsAt,
        uint64 endsAt
    );
    event EpochFinalized(
        uint64 indexed epochId,
        uint256 rewardAmount,
        uint256 eligibleShares,
        uint256 accRewardPerShare
    );
    event UserCheckpointed(address indexed user, uint256 shares, uint256 accrued, uint256 index);
    event RewardClaimed(address indexed user, address indexed receiver, uint256 amount);

    IERC20 public immutable rewardToken;
    HeliosAccess public immutable accessManager;
    DelegationManager public delegationManager;
    address public vault;

    uint64 public currentEpoch;
    uint256 public globalRewardIndex;
    uint256 public totalFundedRewards;
    uint256 public totalClaimedRewards;
    uint256 public unallocatedRewards;

    mapping(uint64 => EpochData) private _epochs;
    mapping(address => uint256) public userRewardIndex;
    mapping(address => uint256) public claimableRewards;

    constructor(address rewardToken_, address accessManager_) {
        if (rewardToken_ == address(0) || accessManager_ == address(0)) revert ZeroAddress();
        rewardToken = IERC20(rewardToken_);
        accessManager = HeliosAccess(accessManager_);
    }

    modifier onlyGovernor() {
        accessManager.checkRole(HeliosConstants.GOVERNOR_ROLE, msg.sender);
        _;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault(msg.sender);
        _;
    }

    function setVault(address vault_) external onlyGovernor {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
        emit VaultConfigured(vault_);
    }

    function setDelegationManager(address delegationManager_) external onlyGovernor {
        if (delegationManager_ == address(0)) revert ZeroAddress();
        delegationManager = DelegationManager(delegationManager_);
        emit DelegationManagerConfigured(delegationManager_);
    }

    function fundEpoch(uint64 epochId, uint256 amount, uint64 startsAt, uint64 endsAt) external {
        if (
            !accessManager.hasRole(HeliosConstants.REWARDER_ROLE, msg.sender)
                && !accessManager.hasRole(HeliosConstants.GOVERNOR_ROLE, msg.sender)
        ) revert UnauthorizedRewarder(msg.sender);
        if (_epochs[epochId].funded) revert EpochAlreadyFunded(epochId);
        if (startsAt >= endsAt) revert InvalidEpochWindow(startsAt, endsAt);

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        totalFundedRewards += amount;
        if (epochId > currentEpoch) currentEpoch = epochId;

        _epochs[epochId] = EpochData({
            epochId: epochId,
            startsAt: startsAt,
            endsAt: endsAt,
            rewardAmount: amount,
            eligibleShares: 0,
            accRewardPerShare: 0,
            funded: true,
            finalized: false
        });

        emit EpochFunded(epochId, msg.sender, amount, startsAt, endsAt);
    }

    function finalizeEpoch(uint64 epochId) external {
        if (
            !accessManager.hasRole(HeliosConstants.REWARDER_ROLE, msg.sender)
                && !accessManager.hasRole(HeliosConstants.KEEPER_ROLE, msg.sender)
                && !accessManager.hasRole(HeliosConstants.GOVERNOR_ROLE, msg.sender)
        ) revert UnauthorizedRewarder(msg.sender);

        EpochData storage epochData = _epochs[epochId];
        if (!epochData.funded) revert EpochNotFunded(epochId);
        if (epochData.finalized) revert EpochAlreadyFinalized(epochId);

        uint256 eligibleShares = delegationManager.totalDelegatedShares();
        epochData.eligibleShares = eligibleShares;
        epochData.finalized = true;

        if (eligibleShares == 0) {
            unallocatedRewards += epochData.rewardAmount;
            emit EpochFinalized(epochId, epochData.rewardAmount, 0, globalRewardIndex);
            return;
        }

        uint256 deltaIndex = epochData.rewardAmount * HeliosConstants.RAY / eligibleShares;
        globalRewardIndex += deltaIndex;
        epochData.accRewardPerShare = globalRewardIndex;

        emit EpochFinalized(epochId, epochData.rewardAmount, eligibleShares, globalRewardIndex);
    }

    function checkpoint(address user) external onlyVault returns (uint256 accrued) {
        accrued = _checkpoint(user, delegationManager.delegatedSharesOf(user));
    }

    function checkpointWithShares(address user, uint256 shares)
        external
        onlyVault
        returns (uint256 accrued)
    {
        accrued = _checkpoint(user, shares);
    }

    function claimFor(address user, address receiver) external onlyVault returns (uint256 amount) {
        if (receiver == address(0)) revert InvalidReceiver();
        _checkpoint(user, delegationManager.delegatedSharesOf(user));
        amount = claimableRewards[user];
        if (amount == 0) return 0;

        claimableRewards[user] = 0;
        totalClaimedRewards += amount;
        rewardToken.safeTransfer(receiver, amount);

        emit RewardClaimed(user, receiver, amount);
    }

    function previewAccrued(address user) external view returns (uint256) {
        uint256 shares = delegationManager.delegatedSharesOf(user);
        uint256 storedIndex = userRewardIndex[user];
        uint256 pending = shares * (globalRewardIndex - storedIndex) / HeliosConstants.RAY;
        return claimableRewards[user] + pending;
    }

    function epoch(uint64 epochId) external view returns (EpochData memory) {
        return _epochs[epochId];
    }

    function _checkpoint(address user, uint256 shares) internal returns (uint256 accrued) {
        uint256 index = globalRewardIndex;
        uint256 previousIndex = userRewardIndex[user];

        if (index > previousIndex && shares > 0) {
            accrued = shares * (index - previousIndex) / HeliosConstants.RAY;
            claimableRewards[user] += accrued;
        }

        userRewardIndex[user] = index;
        emit UserCheckpointed(user, shares, accrued, index);
    }
}
