// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosAccess } from "../security/HeliosAccess.sol";
import { HeliosConstants } from "../types/HeliosTypes.sol";
import { HeliosRestakeVault } from "./HeliosRestakeVault.sol";
import { OperatorRegistry } from "./OperatorRegistry.sol";
import { WithdrawalQueue } from "./WithdrawalQueue.sol";

contract RiskController {
    error ZeroAddress();
    error InvalidBps(uint256 value);
    error InvalidLimit();
    error DepositLimitExceeded(uint256 requested, uint256 maximum);
    error WithdrawalLimitExceeded(uint256 requested, uint256 maximum);
    error QueueLimitExceeded(uint256 requested, uint256 maximum);
    error OperatorUtilizationExceeded(address operator, uint256 requested, uint256 maximum);
    error SlashLimitExceeded(uint256 requested, uint256 maximum);
    error ReserveBufferTooLow(uint256 available, uint256 required);

    struct RiskLimits {
        uint256 maxDepositAssets;
        uint256 maxWithdrawalAssets;
        uint256 maxQueuedWithdrawalBps;
        uint256 maxOperatorUtilizationBps;
        uint256 maxSlashBps;
        uint256 minReserveBufferBps;
    }

    struct RiskPreview {
        bool depositAllowed;
        bool withdrawalAllowed;
        bool queueAllowed;
        bool slashAllowed;
        uint256 currentQueuedAssets;
        uint256 maximumQueuedAssets;
        uint256 operatorAssets;
        uint256 operatorMaximumAssets;
        uint256 reserveBufferAssets;
        uint256 requiredReserveBuffer;
    }

    event VaultConfigured(address indexed vault);
    event QueueConfigured(address indexed queue);
    event RegistryConfigured(address indexed registry);
    event RiskLimitsUpdated(RiskLimits previous, RiskLimits next);
    event DepositChecked(address indexed account, uint256 assets);
    event WithdrawalChecked(address indexed account, uint256 assets);
    event DelegationChecked(address indexed operator, uint256 shares, uint256 estimatedAssets);
    event SlashChecked(address indexed operator, uint256 bps, uint256 estimatedLoss);

    HeliosAccess public immutable accessManager;
    HeliosRestakeVault public vault;
    WithdrawalQueue public queue;
    OperatorRegistry public registry;

    RiskLimits private _limits;

    constructor(address accessManager_) {
        if (accessManager_ == address(0)) revert ZeroAddress();
        accessManager = HeliosAccess(accessManager_);
        _limits = RiskLimits({
            maxDepositAssets: type(uint256).max,
            maxWithdrawalAssets: type(uint256).max,
            maxQueuedWithdrawalBps: 9000,
            maxOperatorUtilizationBps: 9500,
            maxSlashBps: HeliosConstants.MAX_SLASH_BPS,
            minReserveBufferBps: 0
        });
    }

    modifier onlyGovernor() {
        accessManager.checkRole(HeliosConstants.GOVERNOR_ROLE, msg.sender);
        _;
    }

    function configureModules(address vault_, address queue_, address registry_)
        external
        onlyGovernor
    {
        if (vault_ == address(0) || queue_ == address(0) || registry_ == address(0)) {
            revert ZeroAddress();
        }
        vault = HeliosRestakeVault(vault_);
        queue = WithdrawalQueue(queue_);
        registry = OperatorRegistry(registry_);
        emit VaultConfigured(vault_);
        emit QueueConfigured(queue_);
        emit RegistryConfigured(registry_);
    }

    function setRiskLimits(RiskLimits calldata next) external onlyGovernor {
        _validateLimits(next);
        RiskLimits memory previous = _limits;
        _limits = next;
        emit RiskLimitsUpdated(previous, next);
    }

    function limits() external view returns (RiskLimits memory) {
        return _limits;
    }

    function checkDeposit(address account, uint256 assets) external returns (bool) {
        if (assets > _limits.maxDepositAssets) {
            revert DepositLimitExceeded(assets, _limits.maxDepositAssets);
        }
        emit DepositChecked(account, assets);
        return true;
    }

    function checkWithdrawal(address account, uint256 assets) external returns (bool) {
        if (assets > _limits.maxWithdrawalAssets) {
            revert WithdrawalLimitExceeded(assets, _limits.maxWithdrawalAssets);
        }

        uint256 pooledAssets = vault.totalPooledAssets();
        uint256 maxQueuedAssets =
            pooledAssets * _limits.maxQueuedWithdrawalBps / HeliosConstants.BPS;
        uint256 queuedAfter = queue.totalQueuedAssets() + assets;
        if (queuedAfter > maxQueuedAssets) revert QueueLimitExceeded(queuedAfter, maxQueuedAssets);

        emit WithdrawalChecked(account, assets);
        return true;
    }

    function checkDelegation(address operator, uint256 additionalShares) external returns (bool) {
        uint256 currentShares = registry.delegatedSharesOf(operator);
        uint256 nextShares = currentShares + additionalShares;
        uint256 estimatedAssets = vault.previewRedeem(nextShares);
        uint256 maximumAssets =
            vault.totalPooledAssets() * _limits.maxOperatorUtilizationBps / HeliosConstants.BPS;
        if (estimatedAssets > maximumAssets) {
            revert OperatorUtilizationExceeded(operator, estimatedAssets, maximumAssets);
        }

        emit DelegationChecked(operator, additionalShares, estimatedAssets);
        return true;
    }

    function checkSlash(address operator, uint256 slashBps) external returns (bool) {
        if (slashBps > _limits.maxSlashBps) {
            revert SlashLimitExceeded(slashBps, _limits.maxSlashBps);
        }
        if (slashBps > HeliosConstants.MAX_SLASH_BPS) {
            revert SlashLimitExceeded(slashBps, HeliosConstants.MAX_SLASH_BPS);
        }

        uint256 operatorAssets = vault.previewRedeem(registry.delegatedSharesOf(operator));
        uint256 estimatedLoss = operatorAssets * slashBps / HeliosConstants.BPS;
        _checkReserveBuffer(estimatedLoss);

        emit SlashChecked(operator, slashBps, estimatedLoss);
        return true;
    }

    function preview(address operator, uint256 withdrawalAssets, uint256 slashBps)
        external
        view
        returns (RiskPreview memory result)
    {
        RiskLimits memory localLimits = _limits;
        uint256 pooledAssets = vault.totalPooledAssets();
        uint256 queuedAssets = queue.totalQueuedAssets();
        uint256 maxQueuedAssets =
            pooledAssets * localLimits.maxQueuedWithdrawalBps / HeliosConstants.BPS;
        uint256 operatorAssets = vault.previewRedeem(registry.delegatedSharesOf(operator));
        uint256 operatorMaximumAssets =
            pooledAssets * localLimits.maxOperatorUtilizationBps / HeliosConstants.BPS;
        uint256 requiredBuffer =
            pooledAssets * localLimits.minReserveBufferBps / HeliosConstants.BPS;
        uint256 availableBuffer = _availableBuffer();

        result = RiskPreview({
            depositAllowed: localLimits.maxDepositAssets != 0,
            withdrawalAllowed: withdrawalAssets <= localLimits.maxWithdrawalAssets,
            queueAllowed: queuedAssets + withdrawalAssets <= maxQueuedAssets,
            slashAllowed: slashBps <= localLimits.maxSlashBps && availableBuffer >= requiredBuffer,
            currentQueuedAssets: queuedAssets,
            maximumQueuedAssets: maxQueuedAssets,
            operatorAssets: operatorAssets,
            operatorMaximumAssets: operatorMaximumAssets,
            reserveBufferAssets: availableBuffer,
            requiredReserveBuffer: requiredBuffer
        });
    }

    function queueUtilizationBps() external view returns (uint256) {
        uint256 pooledAssets = vault.totalPooledAssets();
        if (pooledAssets == 0) return 0;
        return queue.totalQueuedAssets() * HeliosConstants.BPS / pooledAssets;
    }

    function operatorUtilizationBps(address operator) external view returns (uint256) {
        uint256 pooledAssets = vault.totalPooledAssets();
        if (pooledAssets == 0) return 0;
        uint256 operatorAssets = vault.previewRedeem(registry.delegatedSharesOf(operator));
        return operatorAssets * HeliosConstants.BPS / pooledAssets;
    }

    function reserveBufferBps() external view returns (uint256) {
        uint256 pooledAssets = vault.totalPooledAssets();
        if (pooledAssets == 0) return 0;
        return _availableBuffer() * HeliosConstants.BPS / pooledAssets;
    }

    function _checkReserveBuffer(uint256 projectedLoss) internal view {
        uint256 pooledAssets = vault.totalPooledAssets();
        uint256 required = pooledAssets * _limits.minReserveBufferBps / HeliosConstants.BPS;
        uint256 available = _availableBuffer();
        if (projectedLoss > available) {
            available = 0;
        } else {
            available -= projectedLoss;
        }
        if (available < required) revert ReserveBufferTooLow(available, required);
    }

    function _availableBuffer() internal view returns (uint256) {
        uint256 tokenBalance = vault.stakingToken().balanceOf(address(vault));
        uint256 pooledAssets = vault.totalPooledAssets();
        return tokenBalance > pooledAssets ? tokenBalance - pooledAssets : 0;
    }

    function _validateLimits(RiskLimits calldata next) internal pure {
        if (
            next.maxQueuedWithdrawalBps > HeliosConstants.BPS
                || next.maxOperatorUtilizationBps > HeliosConstants.BPS
                || next.minReserveBufferBps > HeliosConstants.BPS
        ) revert InvalidBps(HeliosConstants.BPS + 1);
        if (next.maxSlashBps > HeliosConstants.MAX_SLASH_BPS) {
            revert SlashLimitExceeded(next.maxSlashBps, HeliosConstants.MAX_SLASH_BPS);
        }
        if (next.maxDepositAssets == 0 || next.maxWithdrawalAssets == 0) revert InvalidLimit();
    }
}
