// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "../interfaces/IERC20.sol";
import { HeliosRestakeVault } from "../core/HeliosRestakeVault.sol";
import { OperatorRegistry } from "../core/OperatorRegistry.sol";
import { ReserveVault } from "../core/ReserveVault.sol";
import { WithdrawalQueue } from "../core/WithdrawalQueue.sol";
import { OperatorAccounting, ProtocolHealth, VaultSnapshot } from "../types/HeliosTypes.sol";

contract HeliosMonitor {
    event HealthChecked(
        uint256 tokenBalance,
        uint256 pooledAssets,
        uint256 queuedAssets,
        uint256 reserveBalance,
        bool accountingDrift
    );

    HeliosRestakeVault public immutable vault;
    OperatorRegistry public immutable registry;
    WithdrawalQueue public immutable queue;
    ReserveVault public immutable reserve;
    IERC20 public immutable stakingToken;

    constructor(address vault_, address registry_, address queue_, address reserve_) {
        vault = HeliosRestakeVault(vault_);
        registry = OperatorRegistry(registry_);
        queue = WithdrawalQueue(queue_);
        reserve = ReserveVault(reserve_);
        stakingToken = vault.stakingToken();
    }

    function protocolHealth() public view returns (ProtocolHealth memory health) {
        VaultSnapshot memory snapshot = vault.protocolSnapshot();
        uint256 tokenBalance = stakingToken.balanceOf(address(vault));
        uint256 reserveBalance = stakingToken.balanceOf(address(reserve));
        uint256 queuedAssets = queue.totalQueuedAssets();
        uint256 buffer = tokenBalance > queuedAssets ? tokenBalance - queuedAssets : 0;

        health = ProtocolHealth({
            initialized: vault.initialized(),
            depositsPaused: vault.depositsPaused(),
            withdrawalsPaused: vault.withdrawalsPaused(),
            delegationsPaused: vault.delegationsPaused(),
            slashingPaused: vault.slashingPaused(),
            idleAssets: tokenBalance,
            pooledAssets: snapshot.totalPooledAssets,
            tokenBalance: tokenBalance,
            reserveBalance: reserveBalance,
            queuedAssets: queuedAssets,
            estimatedSolvencyBuffer: buffer
        });
    }

    function hasAccountingDrift() public view returns (bool) {
        ProtocolHealth memory health = protocolHealth();
        return health.tokenBalance < health.pooledAssets;
    }

    function operatorRisk(address operator)
        external
        view
        returns (uint256 delegatedShares, uint256 estimatedAssets, uint256 cumulativeSlashed)
    {
        OperatorAccounting memory accounting = registry.accountingOf(operator);
        delegatedShares = accounting.delegatedShares;
        estimatedAssets = vault.previewRedeem(delegatedShares);
        cumulativeSlashed = accounting.cumulativeSlashed;
    }

    function aggregateOperatorShares() external view returns (uint256 totalShares) {
        uint256 count = registry.operatorCount();
        for (uint256 i = 0; i < count; ++i) {
            totalShares += registry.delegatedSharesOf(registry.operatorAt(i));
        }
    }

    function aggregateOperatorAssets() external view returns (uint256 totalAssets) {
        uint256 count = registry.operatorCount();
        for (uint256 i = 0; i < count; ++i) {
            totalAssets += vault.previewRedeem(registry.delegatedSharesOf(registry.operatorAt(i)));
        }
    }

    function checkHealth() external returns (ProtocolHealth memory health, bool accountingDrift) {
        health = protocolHealth();
        accountingDrift = health.tokenBalance < health.pooledAssets;
        emit HealthChecked(
            health.tokenBalance,
            health.pooledAssets,
            health.queuedAssets,
            health.reserveBalance,
            accountingDrift
        );
    }
}
