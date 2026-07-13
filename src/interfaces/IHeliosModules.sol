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

interface IHeliosReceiptToken {
    function totalSupply() external view returns (uint256);
    function totalLocked() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function activeBalanceOf(address owner) external view returns (uint256);
    function lockedBalanceOf(address owner) external view returns (uint256);
}

interface IHeliosOperatorRegistry {
    function operatorCount() external view returns (uint256);
    function operatorAt(uint256 index) external view returns (address);
    function configOf(address operator) external view returns (OperatorConfig memory);
    function accountingOf(address operator) external view returns (OperatorAccounting memory);
    function delegatedSharesOf(address operator) external view returns (uint256);
}

interface IHeliosDelegationManager {
    function totalDelegatedShares() external view returns (uint256);
    function delegationOf(address owner) external view returns (DelegationAccount memory);
    function freeSharesOf(address owner) external view returns (uint256);
    function delegatedSharesOf(address owner) external view returns (uint256);
    function operatorOf(address owner) external view returns (address);
}

interface IHeliosWithdrawalQueue {
    function nextRequestId() external view returns (uint256);
    function totalQueuedShares() external view returns (uint256);
    function totalQueuedAssets() external view returns (uint256);
    function request(uint256 requestId) external view returns (WithdrawalRequest memory);
    function ownerRequestCount(address owner) external view returns (uint256);
    function ownerRequestAt(address owner, uint256 index) external view returns (uint256);
}

interface IHeliosEpochRewarder {
    function currentEpoch() external view returns (uint64);
    function globalRewardIndex() external view returns (uint256);
    function totalFundedRewards() external view returns (uint256);
    function totalClaimedRewards() external view returns (uint256);
    function claimableRewards(address user) external view returns (uint256);
    function previewAccrued(address user) external view returns (uint256);
    function epoch(uint64 epochId) external view returns (EpochData memory);
}

interface IHeliosSlashingController {
    function nextRequestId() external view returns (uint256);
    function slashDelay() external view returns (uint64);
    function slashingPaused() external view returns (bool);
    function request(uint256 requestId) external view returns (SlashRequest memory);
    function operatorRequestCount(address operator) external view returns (uint256);
    function operatorRequestAt(address operator, uint256 index) external view returns (uint256);
}

interface IHeliosRestakeVault {
    function initialized() external view returns (bool);
    function depositsPaused() external view returns (bool);
    function withdrawalsPaused() external view returns (bool);
    function delegationsPaused() external view returns (bool);
    function slashingPaused() external view returns (bool);
    function totalPooledAssets() external view returns (uint256);
    function cumulativeDeposits() external view returns (uint256);
    function cumulativeWithdrawals() external view returns (uint256);
    function cumulativeSlashed() external view returns (uint256);
    function currentEpoch() external view returns (uint64);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function exchangeRateRay() external view returns (uint256);
    function protocolSnapshot() external view returns (VaultSnapshot memory);
}

interface IHeliosReserveVault {
    function totalSlashed() external view returns (uint256);
    function totalFees() external view returns (uint256);
    function totalReleased() external view returns (uint256);
    function accountedBalance() external view returns (uint256);
    function slashedByOperator(address operator) external view returns (uint256);
}

interface IHeliosMonitor {
    function protocolHealth() external view returns (ProtocolHealth memory);
    function hasAccountingDrift() external view returns (bool);
    function operatorRisk(address operator)
        external
        view
        returns (uint256 delegatedShares, uint256 estimatedAssets, uint256 cumulativeSlashed);
}
