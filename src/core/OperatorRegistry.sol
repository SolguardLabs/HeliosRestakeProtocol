// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosAccess } from "../security/HeliosAccess.sol";
import {
    HeliosConstants,
    OperatorAccounting,
    OperatorConfig,
    OperatorStatus
} from "../types/HeliosTypes.sol";

contract OperatorRegistry {
    error ZeroAddress();
    error OperatorAlreadyRegistered(address operator);
    error OperatorNotRegistered(address operator);
    error OperatorNotActive(address operator);
    error InvalidCommission(uint256 commissionBps);
    error CapacityExceeded(address operator, uint256 requested, uint256 maximum);
    error OnlyAccountingModule(address sender);
    error OnlyConfiguredModule(address sender);

    event OperatorRegistered(
        address indexed operator,
        address indexed controller,
        address indexed feeRecipient,
        uint32 commissionBps,
        uint96 maxDelegatedShares,
        bytes32 metadataHash
    );
    event OperatorStatusUpdated(
        address indexed operator, OperatorStatus previous, OperatorStatus next
    );
    event OperatorLimitUpdated(address indexed operator, uint96 previous, uint96 next);
    event OperatorCommissionUpdated(address indexed operator, uint32 previous, uint32 next);
    event OperatorControllerUpdated(address indexed operator, address previous, address next);
    event OperatorAccountingModuleUpdated(address indexed module);
    event OperatorDelegationIncreased(
        address indexed operator, uint256 shares, uint256 totalShares
    );
    event OperatorDelegationDecreased(
        address indexed operator, uint256 shares, uint256 totalShares
    );
    event OperatorSlashRecorded(
        address indexed operator, uint256 amount, uint16 bps, uint256 count
    );
    event OperatorRewardsRecorded(address indexed operator, uint256 amount, uint64 epoch);

    HeliosAccess public immutable accessManager;

    address public accountingModule;
    address public vault;
    address[] private _operators;

    mapping(address => OperatorConfig) private _configs;
    mapping(address => OperatorAccounting) private _accounting;
    mapping(address => uint256) private _operatorIndexPlusOne;

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

    modifier onlyAccountingModule() {
        if (msg.sender != accountingModule && msg.sender != vault) {
            revert OnlyAccountingModule(msg.sender);
        }
        _;
    }

    function setAccountingModule(address module, address vault_) external onlyGovernor {
        if (module == address(0) || vault_ == address(0)) revert ZeroAddress();
        accountingModule = module;
        vault = vault_;
        emit OperatorAccountingModuleUpdated(module);
    }

    function registerOperator(
        address operator,
        address controller,
        address feeRecipient,
        uint32 commissionBps,
        uint96 maxDelegatedShares,
        bytes32 metadataHash
    ) external onlyGovernor {
        if (operator == address(0) || controller == address(0) || feeRecipient == address(0)) {
            revert ZeroAddress();
        }
        if (_operatorIndexPlusOne[operator] != 0) revert OperatorAlreadyRegistered(operator);
        if (commissionBps > HeliosConstants.MAX_COMMISSION_BPS) {
            revert InvalidCommission(commissionBps);
        }

        _operatorIndexPlusOne[operator] = _operators.length + 1;
        _operators.push(operator);
        _configs[operator] = OperatorConfig({
            controller: controller,
            feeRecipient: feeRecipient,
            commissionBps: commissionBps,
            maxDelegatedShares: maxDelegatedShares,
            registeredAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp),
            status: OperatorStatus.Active,
            metadataHash: metadataHash
        });

        emit OperatorRegistered(
            operator, controller, feeRecipient, commissionBps, maxDelegatedShares, metadataHash
        );
    }

    function setOperatorStatus(address operator, OperatorStatus status)
        external
        onlyGuardianOrGovernor
    {
        _requireRegistered(operator);
        OperatorStatus previous = _configs[operator].status;
        _configs[operator].status = status;
        _configs[operator].updatedAt = uint64(block.timestamp);
        emit OperatorStatusUpdated(operator, previous, status);
    }

    function setOperatorLimit(address operator, uint96 maxDelegatedShares) external onlyGovernor {
        _requireRegistered(operator);
        uint96 previous = _configs[operator].maxDelegatedShares;
        _configs[operator].maxDelegatedShares = maxDelegatedShares;
        _configs[operator].updatedAt = uint64(block.timestamp);
        emit OperatorLimitUpdated(operator, previous, maxDelegatedShares);
    }

    function setOperatorCommission(address operator, uint32 commissionBps) external onlyGovernor {
        _requireRegistered(operator);
        if (commissionBps > HeliosConstants.MAX_COMMISSION_BPS) {
            revert InvalidCommission(commissionBps);
        }
        uint32 previous = _configs[operator].commissionBps;
        _configs[operator].commissionBps = commissionBps;
        _configs[operator].updatedAt = uint64(block.timestamp);
        emit OperatorCommissionUpdated(operator, previous, commissionBps);
    }

    function setOperatorController(address operator, address controller) external onlyGovernor {
        _requireRegistered(operator);
        if (controller == address(0)) revert ZeroAddress();
        address previous = _configs[operator].controller;
        _configs[operator].controller = controller;
        _configs[operator].updatedAt = uint64(block.timestamp);
        emit OperatorControllerUpdated(operator, previous, controller);
    }

    function increaseDelegated(address operator, uint256 shares) external onlyAccountingModule {
        OperatorConfig memory config = requireActiveOperator(operator);
        OperatorAccounting storage accounting = _accounting[operator];
        uint256 nextShares = accounting.delegatedShares + shares;
        if (nextShares > config.maxDelegatedShares) {
            revert CapacityExceeded(operator, nextShares, config.maxDelegatedShares);
        }
        accounting.delegatedShares = nextShares;
        emit OperatorDelegationIncreased(operator, shares, nextShares);
    }

    function decreaseDelegated(address operator, uint256 shares) external onlyAccountingModule {
        _requireRegistered(operator);
        OperatorAccounting storage accounting = _accounting[operator];
        uint256 current = accounting.delegatedShares;
        if (shares > current) shares = current;
        unchecked {
            accounting.delegatedShares = current - shares;
        }
        emit OperatorDelegationDecreased(operator, shares, accounting.delegatedShares);
    }

    function setQueuedExitShares(address operator, uint256 queuedShares)
        external
        onlyAccountingModule
    {
        _requireRegistered(operator);
        _accounting[operator].queuedExitShares = queuedShares;
    }

    function recordOperatorAssets(address operator, uint256 activeAssets)
        external
        onlyAccountingModule
    {
        _requireRegistered(operator);
        _accounting[operator].activeAssets = activeAssets;
    }

    function recordSlash(address operator, uint256 assets, uint16 bps)
        external
        onlyAccountingModule
    {
        _requireRegistered(operator);
        OperatorAccounting storage accounting = _accounting[operator];
        accounting.cumulativeSlashed += assets;
        accounting.slashCount += 1;
        accounting.lastSlashAt = block.timestamp;
        emit OperatorSlashRecorded(operator, assets, bps, accounting.slashCount);
    }

    function recordRewards(address operator, uint256 assets, uint64 epoch)
        external
        onlyAccountingModule
    {
        _requireRegistered(operator);
        OperatorAccounting storage accounting = _accounting[operator];
        accounting.cumulativeRewards += assets;
        accounting.lastRewardEpoch = epoch;
        emit OperatorRewardsRecorded(operator, assets, epoch);
    }

    function requireActiveOperator(address operator)
        public
        view
        returns (OperatorConfig memory config)
    {
        config = _configs[operator];
        if (_operatorIndexPlusOne[operator] == 0) revert OperatorNotRegistered(operator);
        if (config.status != OperatorStatus.Active) revert OperatorNotActive(operator);
    }

    function isOperator(address operator) external view returns (bool) {
        return _operatorIndexPlusOne[operator] != 0;
    }

    function isActiveOperator(address operator) external view returns (bool) {
        return
            _operatorIndexPlusOne[operator] != 0
                && _configs[operator].status == OperatorStatus.Active;
    }

    function operatorCount() external view returns (uint256) {
        return _operators.length;
    }

    function operatorAt(uint256 index) external view returns (address) {
        return _operators[index];
    }

    function operators() external view returns (address[] memory result) {
        result = new address[](_operators.length);
        for (uint256 i = 0; i < _operators.length; ++i) {
            result[i] = _operators[i];
        }
    }

    function configOf(address operator) external view returns (OperatorConfig memory) {
        _requireRegistered(operator);
        return _configs[operator];
    }

    function accountingOf(address operator) external view returns (OperatorAccounting memory) {
        _requireRegistered(operator);
        return _accounting[operator];
    }

    function delegatedSharesOf(address operator) external view returns (uint256) {
        return _accounting[operator].delegatedShares;
    }

    function feeRecipientOf(address operator) external view returns (address) {
        _requireRegistered(operator);
        return _configs[operator].feeRecipient;
    }

    function commissionBpsOf(address operator) external view returns (uint256) {
        _requireRegistered(operator);
        return _configs[operator].commissionBps;
    }

    function _requireRegistered(address operator) internal view {
        if (_operatorIndexPlusOne[operator] == 0) revert OperatorNotRegistered(operator);
    }
}
