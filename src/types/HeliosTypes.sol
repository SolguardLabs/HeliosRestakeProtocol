// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library HeliosConstants {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant MAX_COMMISSION_BPS = 2000;
    uint256 internal constant MAX_SLASH_BPS = 9000;
    uint256 internal constant MIN_WITHDRAWAL_DELAY = 1 hours;
    uint256 internal constant MAX_WITHDRAWAL_DELAY = 14 days;
    uint256 internal constant MIN_SLASH_DELAY = 2 hours;
    uint256 internal constant MAX_SLASH_DELAY = 7 days;

    bytes32 internal constant GOVERNOR_ROLE = keccak256("HELIOS_GOVERNOR_ROLE");
    bytes32 internal constant GUARDIAN_ROLE = keccak256("HELIOS_GUARDIAN_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("HELIOS_OPERATOR_ROLE");
    bytes32 internal constant SLASHER_ROLE = keccak256("HELIOS_SLASHER_ROLE");
    bytes32 internal constant REWARDER_ROLE = keccak256("HELIOS_REWARDER_ROLE");
    bytes32 internal constant KEEPER_ROLE = keccak256("HELIOS_KEEPER_ROLE");
    bytes32 internal constant MODULE_ROLE = keccak256("HELIOS_MODULE_ROLE");
}

enum OperatorStatus {
    Unset,
    Active,
    Paused,
    Retired
}

enum DelegationStatus {
    None,
    Active,
    CoolingDown
}

enum WithdrawalStatus {
    Unset,
    Pending,
    Claimable,
    Claimed,
    Cancelled
}

enum SlashRequestStatus {
    Unset,
    Queued,
    Executed,
    Cancelled
}

struct OperatorConfig {
    address controller;
    address feeRecipient;
    uint32 commissionBps;
    uint96 maxDelegatedShares;
    uint64 registeredAt;
    uint64 updatedAt;
    OperatorStatus status;
    bytes32 metadataHash;
}

struct OperatorAccounting {
    uint256 delegatedShares;
    uint256 queuedExitShares;
    uint256 activeAssets;
    uint256 cumulativeRewards;
    uint256 cumulativeSlashed;
    uint256 slashCount;
    uint256 lastRewardEpoch;
    uint256 lastSlashAt;
}

struct DelegationAccount {
    address operator;
    uint256 shares;
    uint256 rewardDebt;
    uint64 delegatedAt;
    uint64 updatedAt;
    uint64 undelegateReadyAt;
    DelegationStatus status;
}

struct WithdrawalRequest {
    uint256 id;
    address owner;
    address receiver;
    address operatorAtRequest;
    uint256 shares;
    uint256 assetsAtRequest;
    uint256 minAssets;
    uint64 requestedAt;
    uint64 claimableAt;
    uint64 expiresAt;
    uint64 epoch;
    WithdrawalStatus status;
}

struct WithdrawalRound {
    uint64 epoch;
    uint256 sharesQueued;
    uint256 assetsReserved;
    uint256 sharesClaimed;
    uint256 assetsClaimed;
    uint256 requestCount;
}

struct EpochData {
    uint64 epochId;
    uint64 startsAt;
    uint64 endsAt;
    uint256 rewardAmount;
    uint256 eligibleShares;
    uint256 accRewardPerShare;
    bool funded;
    bool finalized;
}

struct SlashRequest {
    uint256 id;
    address operator;
    address proposer;
    uint16 slashBps;
    uint64 queuedAt;
    uint64 executableAt;
    uint64 executedAt;
    bytes32 evidenceHash;
    SlashRequestStatus status;
    uint256 assetsSlashed;
}

struct VaultSnapshot {
    uint256 totalPooledAssets;
    uint256 totalReceiptSupply;
    uint256 totalActiveShares;
    uint256 totalLockedShares;
    uint256 totalDelegatedShares;
    uint256 totalQueuedShares;
    uint256 cumulativeDeposits;
    uint256 cumulativeWithdrawals;
    uint256 cumulativeSlashed;
    uint256 exchangeRateRay;
}

struct ProtocolHealth {
    bool initialized;
    bool depositsPaused;
    bool withdrawalsPaused;
    bool delegationsPaused;
    bool slashingPaused;
    uint256 idleAssets;
    uint256 pooledAssets;
    uint256 tokenBalance;
    uint256 reserveBalance;
    uint256 queuedAssets;
    uint256 estimatedSolvencyBuffer;
}
