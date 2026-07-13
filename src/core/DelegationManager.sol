// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosReceiptToken } from "../token/HeliosReceiptToken.sol";
import { HeliosAccess } from "../security/HeliosAccess.sol";
import { DelegationAccount, DelegationStatus, HeliosConstants } from "../types/HeliosTypes.sol";
import { OperatorRegistry } from "./OperatorRegistry.sol";

contract DelegationManager {
    error ZeroAddress();
    error OnlyVault(address sender);
    error DelegationsPaused();
    error InvalidShares();
    error IncompatibleOperator(address current, address next);
    error InsufficientDelegatedShares(uint256 available, uint256 required);
    error InsufficientFreeShares(uint256 available, uint256 required);

    event VaultConfigured(address indexed vault);
    event DelegationPauseUpdated(bool paused);
    event SharesDelegated(
        address indexed owner,
        address indexed operator,
        uint256 shares,
        uint256 ownerDelegatedShares
    );
    event SharesUndelegated(
        address indexed owner,
        address indexed operator,
        uint256 shares,
        uint256 ownerDelegatedShares
    );
    event DelegationCleared(address indexed owner, address indexed operator);

    HeliosAccess public immutable accessManager;
    HeliosReceiptToken public immutable receiptToken;
    OperatorRegistry public immutable operatorRegistry;

    address public vault;
    bool public delegationsPaused;
    uint256 public totalDelegatedShares;

    mapping(address => DelegationAccount) private _delegations;
    mapping(address => address[]) private _operatorDelegators;
    mapping(address => mapping(address => bool)) private _operatorHasDelegator;

    constructor(address accessManager_, address receiptToken_, address operatorRegistry_) {
        if (
            accessManager_ == address(0) || receiptToken_ == address(0)
                || operatorRegistry_ == address(0)
        ) revert ZeroAddress();
        accessManager = HeliosAccess(accessManager_);
        receiptToken = HeliosReceiptToken(receiptToken_);
        operatorRegistry = OperatorRegistry(operatorRegistry_);
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

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault(msg.sender);
        _;
    }

    function setVault(address vault_) external onlyGovernor {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
        emit VaultConfigured(vault_);
    }

    function setDelegationsPaused(bool paused) external onlyGuardianOrGovernor {
        delegationsPaused = paused;
        emit DelegationPauseUpdated(paused);
    }

    function delegateFor(address owner, address operator, uint256 shares)
        external
        onlyVault
        returns (DelegationAccount memory account)
    {
        if (delegationsPaused) revert DelegationsPaused();
        if (shares == 0) revert InvalidShares();
        operatorRegistry.requireActiveOperator(operator);

        DelegationAccount storage current = _delegations[owner];
        if (current.operator != address(0) && current.operator != operator) {
            revert IncompatibleOperator(current.operator, operator);
        }

        uint256 activeBalance = receiptToken.activeBalanceOf(owner);
        uint256 freeShares = activeBalance - current.shares;
        if (freeShares < shares) revert InsufficientFreeShares(freeShares, shares);

        current.operator = operator;
        current.shares += shares;
        current.updatedAt = uint64(block.timestamp);
        current.delegatedAt =
            current.delegatedAt == 0 ? uint64(block.timestamp) : current.delegatedAt;
        current.status = DelegationStatus.Active;
        current.undelegateReadyAt = 0;

        totalDelegatedShares += shares;
        _trackDelegator(operator, owner);
        operatorRegistry.increaseDelegated(operator, shares);

        emit SharesDelegated(owner, operator, shares, current.shares);
        return current;
    }

    function undelegateFor(address owner, uint256 shares)
        external
        onlyVault
        returns (DelegationAccount memory account)
    {
        if (shares == 0) revert InvalidShares();
        DelegationAccount storage current = _delegations[owner];
        uint256 delegated = current.shares;
        if (delegated < shares) revert InsufficientDelegatedShares(delegated, shares);

        address operator = current.operator;
        current.shares = delegated - shares;
        current.updatedAt = uint64(block.timestamp);
        totalDelegatedShares -= shares;
        operatorRegistry.decreaseDelegated(operator, shares);

        emit SharesUndelegated(owner, operator, shares, current.shares);

        if (current.shares == 0) {
            current.status = DelegationStatus.None;
            current.operator = address(0);
            current.undelegateReadyAt = uint64(block.timestamp);
            emit DelegationCleared(owner, operator);
        }

        return current;
    }

    function forceClearDelegation(address owner)
        external
        onlyVault
        returns (address operator, uint256 shares)
    {
        DelegationAccount storage current = _delegations[owner];
        operator = current.operator;
        shares = current.shares;
        if (operator == address(0) || shares == 0) return (operator, shares);

        current.operator = address(0);
        current.shares = 0;
        current.updatedAt = uint64(block.timestamp);
        current.undelegateReadyAt = uint64(block.timestamp);
        current.status = DelegationStatus.None;
        totalDelegatedShares -= shares;
        operatorRegistry.decreaseDelegated(operator, shares);

        emit SharesUndelegated(owner, operator, shares, 0);
        emit DelegationCleared(owner, operator);
    }

    function freeSharesOf(address owner) public view returns (uint256) {
        uint256 active = receiptToken.activeBalanceOf(owner);
        uint256 delegated = _delegations[owner].shares;
        return active > delegated ? active - delegated : 0;
    }

    function delegatedSharesOf(address owner) external view returns (uint256) {
        return _delegations[owner].shares;
    }

    function operatorOf(address owner) external view returns (address) {
        return _delegations[owner].operator;
    }

    function delegationOf(address owner) external view returns (DelegationAccount memory) {
        return _delegations[owner];
    }

    function operatorDelegatorCount(address operator) external view returns (uint256) {
        return _operatorDelegators[operator].length;
    }

    function operatorDelegatorAt(address operator, uint256 index) external view returns (address) {
        return _operatorDelegators[operator][index];
    }

    function operatorDelegators(address operator) external view returns (address[] memory result) {
        address[] storage source = _operatorDelegators[operator];
        result = new address[](source.length);
        for (uint256 i = 0; i < source.length; ++i) {
            result[i] = source[i];
        }
    }

    function _trackDelegator(address operator, address owner) internal {
        if (_operatorHasDelegator[operator][owner]) return;
        _operatorHasDelegator[operator][owner] = true;
        _operatorDelegators[operator].push(owner);
    }
}
