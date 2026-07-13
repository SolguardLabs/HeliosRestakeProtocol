// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosAccess } from "../security/HeliosAccess.sol";
import { HeliosConstants } from "../types/HeliosTypes.sol";

contract HeliosAccounting {
    error ZeroAddress();
    error UnauthorizedReporter(address sender);
    error InvalidEpoch();

    struct EpochLedger {
        uint64 epochId;
        uint256 deposits;
        uint256 withdrawalsRequested;
        uint256 withdrawalsExecuted;
        uint256 sharesMinted;
        uint256 sharesBurned;
        uint256 sharesDelegated;
        uint256 sharesUndelegated;
        uint256 rewardsFunded;
        uint256 rewardsClaimed;
        uint256 assetsSlashed;
        uint256 slashEvents;
        uint256 requestCount;
        uint256 claimCount;
    }

    struct OperatorLedger {
        uint256 delegatedIn;
        uint256 delegatedOut;
        uint256 rewardsAttributed;
        uint256 assetsSlashed;
        uint256 slashEvents;
        uint256 lastUpdatedEpoch;
    }

    struct UserLedger {
        uint256 deposits;
        uint256 withdrawalRequests;
        uint256 withdrawalsClaimed;
        uint256 sharesMinted;
        uint256 sharesBurned;
        uint256 sharesDelegated;
        uint256 sharesUndelegated;
        uint256 rewardsClaimed;
        uint256 lastUpdatedEpoch;
    }

    event ReporterUpdated(address indexed reporter, bool enabled);
    event DepositRecorded(
        uint64 indexed epoch, address indexed user, uint256 assets, uint256 shares
    );
    event WithdrawalRequestedRecorded(
        uint64 indexed epoch, address indexed user, uint256 assets, uint256 shares
    );
    event WithdrawalExecutedRecorded(
        uint64 indexed epoch, address indexed user, uint256 assets, uint256 shares
    );
    event DelegationRecorded(
        uint64 indexed epoch, address indexed user, address indexed operator, uint256 shares
    );
    event UndelegationRecorded(
        uint64 indexed epoch, address indexed user, address indexed operator, uint256 shares
    );
    event RewardFundedRecorded(uint64 indexed epoch, uint256 assets);
    event RewardClaimRecorded(uint64 indexed epoch, address indexed user, uint256 assets);
    event SlashRecorded(uint64 indexed epoch, address indexed operator, uint256 assets);

    HeliosAccess public immutable accessManager;
    mapping(address => bool) public reporters;
    mapping(uint64 => EpochLedger) private _epochs;
    mapping(address => OperatorLedger) private _operators;
    mapping(address => UserLedger) private _users;
    uint64[] private _epochIds;
    mapping(uint64 => bool) private _seenEpoch;

    constructor(address accessManager_) {
        if (accessManager_ == address(0)) revert ZeroAddress();
        accessManager = HeliosAccess(accessManager_);
    }

    modifier onlyGovernor() {
        accessManager.checkRole(HeliosConstants.GOVERNOR_ROLE, msg.sender);
        _;
    }

    modifier onlyReporter() {
        if (
            !reporters[msg.sender]
                && !accessManager.hasRole(HeliosConstants.GOVERNOR_ROLE, msg.sender)
        ) revert UnauthorizedReporter(msg.sender);
        _;
    }

    function setReporter(address reporter, bool enabled) external onlyGovernor {
        if (reporter == address(0)) revert ZeroAddress();
        reporters[reporter] = enabled;
        emit ReporterUpdated(reporter, enabled);
    }

    function recordDeposit(uint64 epochId, address user, uint256 assets, uint256 shares)
        external
        onlyReporter
    {
        _touchEpoch(epochId);
        EpochLedger storage epoch = _epochs[epochId];
        UserLedger storage ledger = _users[user];

        epoch.deposits += assets;
        epoch.sharesMinted += shares;
        ledger.deposits += assets;
        ledger.sharesMinted += shares;
        ledger.lastUpdatedEpoch = epochId;

        emit DepositRecorded(epochId, user, assets, shares);
    }

    function recordWithdrawalRequest(uint64 epochId, address user, uint256 assets, uint256 shares)
        external
        onlyReporter
    {
        _touchEpoch(epochId);
        EpochLedger storage epoch = _epochs[epochId];
        UserLedger storage ledger = _users[user];

        epoch.withdrawalsRequested += assets;
        epoch.requestCount += 1;
        ledger.withdrawalRequests += assets;
        ledger.lastUpdatedEpoch = epochId;

        emit WithdrawalRequestedRecorded(epochId, user, assets, shares);
    }

    function recordWithdrawalExecution(uint64 epochId, address user, uint256 assets, uint256 shares)
        external
        onlyReporter
    {
        _touchEpoch(epochId);
        EpochLedger storage epoch = _epochs[epochId];
        UserLedger storage ledger = _users[user];

        epoch.withdrawalsExecuted += assets;
        epoch.sharesBurned += shares;
        epoch.claimCount += 1;
        ledger.withdrawalsClaimed += assets;
        ledger.sharesBurned += shares;
        ledger.lastUpdatedEpoch = epochId;

        emit WithdrawalExecutedRecorded(epochId, user, assets, shares);
    }

    function recordDelegation(uint64 epochId, address user, address operator, uint256 shares)
        external
        onlyReporter
    {
        _touchEpoch(epochId);
        EpochLedger storage epoch = _epochs[epochId];
        UserLedger storage userData = _users[user];
        OperatorLedger storage operatorData = _operators[operator];

        epoch.sharesDelegated += shares;
        userData.sharesDelegated += shares;
        userData.lastUpdatedEpoch = epochId;
        operatorData.delegatedIn += shares;
        operatorData.lastUpdatedEpoch = epochId;

        emit DelegationRecorded(epochId, user, operator, shares);
    }

    function recordUndelegation(uint64 epochId, address user, address operator, uint256 shares)
        external
        onlyReporter
    {
        _touchEpoch(epochId);
        EpochLedger storage epoch = _epochs[epochId];
        UserLedger storage userData = _users[user];
        OperatorLedger storage operatorData = _operators[operator];

        epoch.sharesUndelegated += shares;
        userData.sharesUndelegated += shares;
        userData.lastUpdatedEpoch = epochId;
        operatorData.delegatedOut += shares;
        operatorData.lastUpdatedEpoch = epochId;

        emit UndelegationRecorded(epochId, user, operator, shares);
    }

    function recordRewardFunding(uint64 epochId, uint256 assets) external onlyReporter {
        _touchEpoch(epochId);
        _epochs[epochId].rewardsFunded += assets;
        emit RewardFundedRecorded(epochId, assets);
    }

    function recordRewardClaim(uint64 epochId, address user, uint256 assets) external onlyReporter {
        _touchEpoch(epochId);
        EpochLedger storage epoch = _epochs[epochId];
        UserLedger storage ledger = _users[user];

        epoch.rewardsClaimed += assets;
        ledger.rewardsClaimed += assets;
        ledger.lastUpdatedEpoch = epochId;

        emit RewardClaimRecorded(epochId, user, assets);
    }

    function recordSlash(uint64 epochId, address operator, uint256 assets) external onlyReporter {
        _touchEpoch(epochId);
        EpochLedger storage epoch = _epochs[epochId];
        OperatorLedger storage ledger = _operators[operator];

        epoch.assetsSlashed += assets;
        epoch.slashEvents += 1;
        ledger.assetsSlashed += assets;
        ledger.slashEvents += 1;
        ledger.lastUpdatedEpoch = epochId;

        emit SlashRecorded(epochId, operator, assets);
    }

    function epochLedger(uint64 epochId) external view returns (EpochLedger memory) {
        return _epochs[epochId];
    }

    function operatorLedger(address operator) external view returns (OperatorLedger memory) {
        return _operators[operator];
    }

    function userLedger(address user) external view returns (UserLedger memory) {
        return _users[user];
    }

    function epochCount() external view returns (uint256) {
        return _epochIds.length;
    }

    function epochAt(uint256 index) external view returns (uint64) {
        return _epochIds[index];
    }

    function epochPage(uint256 offset, uint256 limit)
        external
        view
        returns (EpochLedger[] memory result)
    {
        uint256 length = _epochIds.length;
        if (offset >= length) return new EpochLedger[](0);
        uint256 end = offset + limit;
        if (end > length) end = length;

        result = new EpochLedger[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            result[i - offset] = _epochs[_epochIds[i]];
        }
    }

    function totals()
        external
        view
        returns (
            uint256 deposits,
            uint256 withdrawals,
            uint256 rewardsFunded,
            uint256 rewardsClaimed,
            uint256 slashed
        )
    {
        for (uint256 i = 0; i < _epochIds.length; ++i) {
            EpochLedger memory epoch = _epochs[_epochIds[i]];
            deposits += epoch.deposits;
            withdrawals += epoch.withdrawalsExecuted;
            rewardsFunded += epoch.rewardsFunded;
            rewardsClaimed += epoch.rewardsClaimed;
            slashed += epoch.assetsSlashed;
        }
    }

    function _touchEpoch(uint64 epochId) internal {
        if (epochId == 0) revert InvalidEpoch();
        if (_seenEpoch[epochId]) return;
        _seenEpoch[epochId] = true;
        _epochs[epochId].epochId = epochId;
        _epochIds.push(epochId);
    }
}
