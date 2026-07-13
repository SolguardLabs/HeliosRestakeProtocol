// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosAccess } from "../security/HeliosAccess.sol";
import { HeliosConstants } from "../types/HeliosTypes.sol";

contract EpochPolicy {
    error ZeroAddress();
    error InvalidDuration();
    error InvalidEpoch();
    error EpochAlreadyClosed(uint64 epochId);
    error EpochNotOpen(uint64 epochId);
    error OperatorPolicyNotFound(address operator);
    error InvalidOperatorWeight(uint256 weight);

    struct EpochWindow {
        uint64 epochId;
        uint64 startsAt;
        uint64 endsAt;
        bool closed;
        bytes32 metadataHash;
    }

    struct OperatorPolicy {
        bool enabled;
        uint32 maxShareBps;
        uint32 rewardWeightBps;
        uint64 updatedAt;
        bytes32 metadataHash;
    }

    event EpochDurationUpdated(uint64 previous, uint64 next);
    event EpochOpened(uint64 indexed epochId, uint64 startsAt, uint64 endsAt, bytes32 metadataHash);
    event EpochClosed(uint64 indexed epochId);
    event OperatorPolicyUpdated(
        address indexed operator,
        bool enabled,
        uint32 maxShareBps,
        uint32 rewardWeightBps,
        bytes32 metadataHash
    );

    HeliosAccess public immutable accessManager;
    uint64 public epochDuration = 1 days;
    uint64 public latestEpoch;

    mapping(uint64 => EpochWindow) private _epochs;
    mapping(address => OperatorPolicy) private _operatorPolicies;
    address[] private _operators;
    mapping(address => bool) private _operatorSeen;

    constructor(address accessManager_) {
        if (accessManager_ == address(0)) revert ZeroAddress();
        accessManager = HeliosAccess(accessManager_);
    }

    modifier onlyGovernor() {
        accessManager.checkRole(HeliosConstants.GOVERNOR_ROLE, msg.sender);
        _;
    }

    modifier onlyGuardianOrGovernor() {
        if (
            !accessManager.hasRole(HeliosConstants.GUARDIAN_ROLE, msg.sender)
                && !accessManager.hasRole(HeliosConstants.GOVERNOR_ROLE, msg.sender)
        ) {
            accessManager.checkRole(HeliosConstants.GUARDIAN_ROLE, msg.sender);
        }
        _;
    }

    function setEpochDuration(uint64 duration) external onlyGovernor {
        if (duration < 1 hours || duration > 30 days) revert InvalidDuration();
        uint64 previous = epochDuration;
        epochDuration = duration;
        emit EpochDurationUpdated(previous, duration);
    }

    function openNextEpoch(bytes32 metadataHash)
        external
        onlyGuardianOrGovernor
        returns (uint64 epochId)
    {
        epochId = latestEpoch + 1;
        uint64 startsAt;
        if (latestEpoch == 0) {
            startsAt = uint64(block.timestamp);
        } else {
            EpochWindow memory previous = _epochs[latestEpoch];
            if (!previous.closed) revert EpochNotOpen(latestEpoch);
            startsAt = previous.endsAt;
        }

        uint64 endsAt = startsAt + epochDuration;
        latestEpoch = epochId;
        _epochs[epochId] = EpochWindow({
            epochId: epochId,
            startsAt: startsAt,
            endsAt: endsAt,
            closed: false,
            metadataHash: metadataHash
        });

        emit EpochOpened(epochId, startsAt, endsAt, metadataHash);
    }

    function closeEpoch(uint64 epochId) external onlyGuardianOrGovernor {
        EpochWindow storage window = _epochs[epochId];
        if (window.epochId == 0) revert InvalidEpoch();
        if (window.closed) revert EpochAlreadyClosed(epochId);
        window.closed = true;
        emit EpochClosed(epochId);
    }

    function configureOperatorPolicy(
        address operator,
        bool enabled,
        uint32 maxShareBps,
        uint32 rewardWeightBps,
        bytes32 metadataHash
    ) external onlyGovernor {
        if (operator == address(0)) revert ZeroAddress();
        if (maxShareBps > HeliosConstants.BPS || rewardWeightBps > HeliosConstants.BPS) {
            revert InvalidOperatorWeight(maxShareBps > HeliosConstants.BPS
                    ? maxShareBps
                    : rewardWeightBps);
        }

        _operatorPolicies[operator] = OperatorPolicy({
            enabled: enabled,
            maxShareBps: maxShareBps,
            rewardWeightBps: rewardWeightBps,
            updatedAt: uint64(block.timestamp),
            metadataHash: metadataHash
        });

        if (!_operatorSeen[operator]) {
            _operatorSeen[operator] = true;
            _operators.push(operator);
        }

        emit OperatorPolicyUpdated(operator, enabled, maxShareBps, rewardWeightBps, metadataHash);
    }

    function requireEpochOpen(uint64 epochId) external view returns (EpochWindow memory window) {
        window = _epochs[epochId];
        if (window.epochId == 0) revert InvalidEpoch();
        if (window.closed) revert EpochAlreadyClosed(epochId);
    }

    function requireOperatorEnabled(address operator)
        external
        view
        returns (OperatorPolicy memory policy)
    {
        policy = _operatorPolicies[operator];
        if (!policy.enabled) revert OperatorPolicyNotFound(operator);
    }

    function epochWindow(uint64 epochId) external view returns (EpochWindow memory) {
        return _epochs[epochId];
    }

    function currentEpochWindow() external view returns (EpochWindow memory) {
        return _epochs[latestEpoch];
    }

    function operatorPolicy(address operator) external view returns (OperatorPolicy memory) {
        return _operatorPolicies[operator];
    }

    function operatorPolicyCount() external view returns (uint256) {
        return _operators.length;
    }

    function operatorPolicyAt(uint256 index) external view returns (address) {
        return _operators[index];
    }

    function operatorPolicyPage(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory operators, OperatorPolicy[] memory policies)
    {
        uint256 length = _operators.length;
        if (offset >= length) {
            operators = new address[](0);
            policies = new OperatorPolicy[](0);
            return (operators, policies);
        }

        uint256 end = offset + limit;
        if (end > length) end = length;
        operators = new address[](end - offset);
        policies = new OperatorPolicy[](end - offset);

        for (uint256 i = offset; i < end; ++i) {
            address operator = _operators[i];
            operators[i - offset] = operator;
            policies[i - offset] = _operatorPolicies[operator];
        }
    }

    function epochIsActive(uint64 epochId) external view returns (bool) {
        EpochWindow memory window = _epochs[epochId];
        return window.epochId != 0 && !window.closed && block.timestamp >= window.startsAt
            && block.timestamp < window.endsAt;
    }

    function secondsUntilEpochEnd(uint64 epochId) external view returns (uint256) {
        EpochWindow memory window = _epochs[epochId];
        if (window.epochId == 0 || block.timestamp >= window.endsAt) return 0;
        return window.endsAt - block.timestamp;
    }
}
