// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    DelegationAccount,
    EpochData,
    OperatorAccounting,
    OperatorConfig,
    ProtocolHealth,
    SlashRequest,
    VaultSnapshot,
    WithdrawalRequest
} from "../types/HeliosTypes.sol";
import { DelegationManager } from "../core/DelegationManager.sol";
import { EpochRewarder } from "../core/EpochRewarder.sol";
import { HeliosRestakeVault } from "../core/HeliosRestakeVault.sol";
import { OperatorRegistry } from "../core/OperatorRegistry.sol";
import { ReserveVault } from "../core/ReserveVault.sol";
import { SlashingController } from "../core/SlashingController.sol";
import { WithdrawalQueue } from "../core/WithdrawalQueue.sol";

contract HeliosLens {
    struct UserPosition {
        uint256 receiptBalance;
        uint256 activeShares;
        uint256 lockedShares;
        uint256 freeShares;
        uint256 delegatedShares;
        uint256 assetsIfRedeemed;
        uint256 claimableRewards;
        address delegatedOperator;
        DelegationAccount delegation;
    }

    struct OperatorView {
        address operator;
        OperatorConfig config;
        OperatorAccounting accounting;
        uint256 estimatedDelegatedAssets;
        uint256 queuedSlashRequests;
    }

    struct WithdrawalPage {
        uint256[] requestIds;
        WithdrawalRequest[] requests;
    }

    HeliosRestakeVault public immutable vault;
    OperatorRegistry public immutable registry;
    DelegationManager public immutable delegation;
    WithdrawalQueue public immutable queue;
    EpochRewarder public immutable rewarder;
    ReserveVault public immutable reserve;
    SlashingController public immutable slashing;

    constructor(
        address vault_,
        address registry_,
        address delegation_,
        address queue_,
        address rewarder_,
        address reserve_,
        address slashing_
    ) {
        vault = HeliosRestakeVault(vault_);
        registry = OperatorRegistry(registry_);
        delegation = DelegationManager(delegation_);
        queue = WithdrawalQueue(queue_);
        rewarder = EpochRewarder(rewarder_);
        reserve = ReserveVault(reserve_);
        slashing = SlashingController(slashing_);
    }

    function userPosition(address user) external view returns (UserPosition memory position) {
        uint256 receiptBalance = vault.receiptToken().balanceOf(user);
        uint256 lockedShares = vault.receiptToken().lockedBalanceOf(user);
        uint256 activeShares = vault.receiptToken().activeBalanceOf(user);
        uint256 delegatedShares = delegation.delegatedSharesOf(user);

        position = UserPosition({
            receiptBalance: receiptBalance,
            activeShares: activeShares,
            lockedShares: lockedShares,
            freeShares: delegation.freeSharesOf(user),
            delegatedShares: delegatedShares,
            assetsIfRedeemed: vault.previewRedeem(receiptBalance),
            claimableRewards: rewarder.previewAccrued(user),
            delegatedOperator: delegation.operatorOf(user),
            delegation: delegation.delegationOf(user)
        });
    }

    function operatorView(address operator) external view returns (OperatorView memory viewData) {
        OperatorAccounting memory accounting = registry.accountingOf(operator);
        viewData = OperatorView({
            operator: operator,
            config: registry.configOf(operator),
            accounting: accounting,
            estimatedDelegatedAssets: vault.previewRedeem(accounting.delegatedShares),
            queuedSlashRequests: slashing.operatorRequestCount(operator)
        });
    }

    function operatorViews(uint256 offset, uint256 limit)
        external
        view
        returns (OperatorView[] memory result)
    {
        uint256 count = registry.operatorCount();
        if (offset >= count) return new OperatorView[](0);
        uint256 end = offset + limit;
        if (end > count) end = count;

        result = new OperatorView[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            address operator = registry.operatorAt(i);
            OperatorAccounting memory accounting = registry.accountingOf(operator);
            result[i - offset] = OperatorView({
                operator: operator,
                config: registry.configOf(operator),
                accounting: accounting,
                estimatedDelegatedAssets: vault.previewRedeem(accounting.delegatedShares),
                queuedSlashRequests: slashing.operatorRequestCount(operator)
            });
        }
    }

    function withdrawalPage(address owner, uint256 offset, uint256 limit)
        external
        view
        returns (WithdrawalPage memory page)
    {
        uint256 total = queue.ownerRequestCount(owner);
        if (offset >= total) {
            page.requestIds = new uint256[](0);
            page.requests = new WithdrawalRequest[](0);
            return page;
        }

        uint256 end = offset + limit;
        if (end > total) end = total;

        page.requestIds = new uint256[](end - offset);
        page.requests = new WithdrawalRequest[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            uint256 requestId = queue.ownerRequestAt(owner, i);
            page.requestIds[i - offset] = requestId;
            page.requests[i - offset] = queue.request(requestId);
        }
    }

    function slashRequests(address operator, uint256 offset, uint256 limit)
        external
        view
        returns (SlashRequest[] memory result)
    {
        uint256 total = slashing.operatorRequestCount(operator);
        if (offset >= total) return new SlashRequest[](0);
        uint256 end = offset + limit;
        if (end > total) end = total;

        result = new SlashRequest[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            result[i - offset] = slashing.request(slashing.operatorRequestAt(operator, i));
        }
    }

    function epochRange(uint64 startEpoch, uint64 count)
        external
        view
        returns (EpochData[] memory result)
    {
        result = new EpochData[](count);
        for (uint64 i = 0; i < count; ++i) {
            result[i] = rewarder.epoch(startEpoch + i);
        }
    }

    function protocolSnapshot() external view returns (VaultSnapshot memory) {
        return vault.protocolSnapshot();
    }

    function protocolHealth() external view returns (ProtocolHealth memory health) {
        VaultSnapshot memory snapshot = vault.protocolSnapshot();
        uint256 tokenBalance = vault.stakingToken().balanceOf(address(vault));
        uint256 reserveBalance = vault.stakingToken().balanceOf(address(reserve));
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
}
