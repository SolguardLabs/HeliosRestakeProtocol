// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20, IERC20Metadata } from "../interfaces/IERC20.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { HeliosMath } from "../libraries/HeliosMath.sol";
import { HeliosAccess } from "../security/HeliosAccess.sol";
import { HeliosReceiptToken } from "../token/HeliosReceiptToken.sol";
import { HeliosConstants, VaultSnapshot, WithdrawalRequest } from "../types/HeliosTypes.sol";
import { DelegationManager } from "./DelegationManager.sol";
import { EpochRewarder } from "./EpochRewarder.sol";
import { OperatorRegistry } from "./OperatorRegistry.sol";
import { ReserveVault } from "./ReserveVault.sol";
import { SlashingController } from "./SlashingController.sol";
import { WithdrawalQueue } from "./WithdrawalQueue.sol";

contract HeliosRestakeVault {
    using SafeTransferLib for IERC20;

    error ZeroAddress();
    error InvalidAmount();
    error InvalidReceiver();
    error AlreadyInitialized();
    error NotInitialized();
    error DepositsPaused();
    error WithdrawalsPaused();
    error DelegationsPaused();
    error SlashingPaused();
    error OnlyGovernor(address sender);
    error OnlyGuardian(address sender);
    error OnlySlashingController(address sender);
    error InsufficientShares(uint256 available, uint256 required);
    error InsufficientPoolAssets(uint256 available, uint256 required);
    error UnsupportedToken(address token);
    error Reentrancy();
    error ModuleMismatch(address module);
    error SameToken();

    event ModulesInitialized(
        address indexed receiptToken,
        address indexed operatorRegistry,
        address indexed delegationManager,
        address withdrawalQueue,
        address rewarder,
        address reserveVault,
        address slashingController
    );
    event StakeDeposited(
        address indexed caller, address indexed receiver, uint256 assets, uint256 shares
    );
    event SharesDelegated(address indexed owner, address indexed operator, uint256 shares);
    event SharesUndelegated(address indexed owner, address indexed operator, uint256 shares);
    event WithdrawalRequested(
        uint256 indexed requestId,
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 assets
    );
    event WithdrawalCancelled(uint256 indexed requestId, address indexed owner, uint256 shares);
    event WithdrawalExecuted(
        uint256 indexed requestId,
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 assets
    );
    event RewardClaimed(address indexed owner, address indexed receiver, uint256 amount);
    event OperatorSlashed(
        address indexed operator,
        uint16 slashBps,
        uint256 operatorAssets,
        uint256 assetsSlashed,
        bytes32 indexed evidenceHash
    );
    event PauseStateUpdated(
        bool depositsPaused, bool withdrawalsPaused, bool delegationsPaused, bool slashingPaused
    );
    event EpochAdvanced(uint64 previousEpoch, uint64 nextEpoch);
    event TokenRecovered(address indexed token, address indexed recipient, uint256 amount);

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;
    uint8 public immutable stakingDecimals;
    HeliosAccess public immutable accessManager;

    HeliosReceiptToken public receiptToken;
    OperatorRegistry public operatorRegistry;
    DelegationManager public delegationManager;
    WithdrawalQueue public withdrawalQueue;
    EpochRewarder public rewarder;
    ReserveVault public reserveVault;
    SlashingController public slashingController;

    bool public initialized;
    bool public depositsPaused;
    bool public withdrawalsPaused;
    bool public delegationsPaused;
    bool public slashingPaused;

    uint64 public currentEpoch = 1;
    uint256 public totalPooledAssets;
    uint256 public cumulativeDeposits;
    uint256 public cumulativeWithdrawals;
    uint256 public cumulativeQueuedWithdrawals;
    uint256 public cumulativeSlashed;
    uint256 public cumulativeRewardClaims;

    uint256 private _reentrancyState = 1;

    constructor(address stakingToken_, address rewardToken_, address accessManager_) {
        if (
            stakingToken_ == address(0) || rewardToken_ == address(0)
                || accessManager_ == address(0)
        ) revert ZeroAddress();
        if (stakingToken_ == rewardToken_) revert SameToken();

        uint8 decimals_;
        try IERC20Metadata(stakingToken_).decimals() returns (uint8 value) {
            decimals_ = value;
        } catch {
            decimals_ = 18;
        }

        stakingToken = IERC20(stakingToken_);
        rewardToken = IERC20(rewardToken_);
        stakingDecimals = decimals_;
        accessManager = HeliosAccess(accessManager_);
    }

    modifier nonReentrant() {
        if (_reentrancyState != 1) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    modifier onlyInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }

    modifier onlyGovernor() {
        if (!accessManager.hasRole(HeliosConstants.GOVERNOR_ROLE, msg.sender)) {
            revert OnlyGovernor(msg.sender);
        }
        _;
    }

    modifier onlyGuardianOrGovernor() {
        if (
            !accessManager.hasRole(HeliosConstants.GUARDIAN_ROLE, msg.sender)
                && !accessManager.hasRole(HeliosConstants.GOVERNOR_ROLE, msg.sender)
        ) revert OnlyGuardian(msg.sender);
        _;
    }

    function initializeModules(
        address receiptToken_,
        address operatorRegistry_,
        address delegationManager_,
        address withdrawalQueue_,
        address rewarder_,
        address reserveVault_,
        address slashingController_
    ) external onlyGovernor {
        if (initialized) revert AlreadyInitialized();
        if (
            receiptToken_ == address(0) || operatorRegistry_ == address(0)
                || delegationManager_ == address(0) || withdrawalQueue_ == address(0)
                || rewarder_ == address(0) || reserveVault_ == address(0)
                || slashingController_ == address(0)
        ) revert ZeroAddress();

        receiptToken = HeliosReceiptToken(receiptToken_);
        operatorRegistry = OperatorRegistry(operatorRegistry_);
        delegationManager = DelegationManager(delegationManager_);
        withdrawalQueue = WithdrawalQueue(withdrawalQueue_);
        rewarder = EpochRewarder(rewarder_);
        reserveVault = ReserveVault(reserveVault_);
        slashingController = SlashingController(slashingController_);

        if (receiptToken.vault() != address(this)) revert ModuleMismatch(receiptToken_);
        if (delegationManager.vault() != address(this)) revert ModuleMismatch(delegationManager_);
        if (withdrawalQueue.vault() != address(this)) revert ModuleMismatch(withdrawalQueue_);
        if (rewarder.vault() != address(this)) revert ModuleMismatch(rewarder_);
        if (reserveVault.vault() != address(this)) revert ModuleMismatch(reserveVault_);
        if (slashingController.vault() != address(this)) {
            revert ModuleMismatch(slashingController_);
        }

        initialized = true;
        emit ModulesInitialized(
            receiptToken_,
            operatorRegistry_,
            delegationManager_,
            withdrawalQueue_,
            rewarder_,
            reserveVault_,
            slashingController_
        );
    }

    function setPauseState(
        bool depositsPaused_,
        bool withdrawalsPaused_,
        bool delegationsPaused_,
        bool slashingPaused_
    ) external onlyGuardianOrGovernor {
        depositsPaused = depositsPaused_;
        withdrawalsPaused = withdrawalsPaused_;
        delegationsPaused = delegationsPaused_;
        slashingPaused = slashingPaused_;
        emit PauseStateUpdated(
            depositsPaused_, withdrawalsPaused_, delegationsPaused_, slashingPaused_
        );
    }

    function advanceEpoch(uint64 nextEpoch) external onlyGovernor {
        if (nextEpoch <= currentEpoch) revert InvalidAmount();
        uint64 previous = currentEpoch;
        currentEpoch = nextEpoch;
        emit EpochAdvanced(previous, nextEpoch);
    }

    function stake(uint256 assets, address receiver)
        external
        nonReentrant
        onlyInitialized
        returns (uint256 shares)
    {
        if (depositsPaused) revert DepositsPaused();
        if (receiver == address(0)) revert InvalidReceiver();
        if (assets == 0) revert InvalidAmount();

        shares = previewDeposit(assets);
        if (shares == 0) revert InvalidAmount();

        stakingToken.safeTransferFrom(msg.sender, address(this), assets);
        totalPooledAssets += assets;
        cumulativeDeposits += assets;
        receiptToken.mint(receiver, shares);

        emit StakeDeposited(msg.sender, receiver, assets, shares);
    }

    function delegate(address operator, uint256 shares)
        external
        nonReentrant
        onlyInitialized
        returns (uint256 delegatedShares)
    {
        if (delegationsPaused) revert DelegationsPaused();
        if (shares == 0) revert InvalidAmount();

        rewarder.checkpoint(msg.sender);
        delegationManager.delegateFor(msg.sender, operator, shares);
        delegatedShares = delegationManager.delegatedSharesOf(msg.sender);
        _refreshOperatorAssets(operator);

        emit SharesDelegated(msg.sender, operator, shares);
    }

    function undelegate(uint256 shares)
        external
        nonReentrant
        onlyInitialized
        returns (uint256 remainingDelegatedShares)
    {
        if (shares == 0) revert InvalidAmount();
        address operator = delegationManager.operatorOf(msg.sender);
        rewarder.checkpoint(msg.sender);
        delegationManager.undelegateFor(msg.sender, shares);
        remainingDelegatedShares = delegationManager.delegatedSharesOf(msg.sender);
        if (operator != address(0)) _refreshOperatorAssets(operator);

        emit SharesUndelegated(msg.sender, operator, shares);
    }

    function requestWithdrawal(uint256 shares, address receiver, uint256 minAssets)
        external
        nonReentrant
        onlyInitialized
        returns (uint256 requestId)
    {
        if (withdrawalsPaused) revert WithdrawalsPaused();
        if (shares == 0) revert InvalidAmount();
        if (receiver == address(0)) revert InvalidReceiver();

        rewarder.checkpoint(msg.sender);
        uint256 freeShares = delegationManager.freeSharesOf(msg.sender);
        if (freeShares < shares) revert InsufficientShares(freeShares, shares);

        uint256 assets = previewRedeem(shares);
        if (assets == 0) revert InvalidAmount();

        address operator = delegationManager.operatorOf(msg.sender);
        receiptToken.lock(msg.sender, shares);
        requestId = withdrawalQueue.open(
            msg.sender, receiver, operator, shares, assets, minAssets, currentEpoch
        );
        cumulativeQueuedWithdrawals += assets;

        emit WithdrawalRequested(requestId, msg.sender, receiver, shares, assets);
    }

    function cancelWithdrawal(uint256 requestId)
        external
        nonReentrant
        onlyInitialized
        returns (uint256 shares)
    {
        WithdrawalRequest memory req = withdrawalQueue.cancel(requestId, msg.sender);
        receiptToken.unlock(req.owner, req.shares);
        shares = req.shares;
        emit WithdrawalCancelled(requestId, req.owner, req.shares);
    }

    function executeWithdrawal(uint256 requestId)
        external
        nonReentrant
        onlyInitialized
        returns (uint256 assets)
    {
        WithdrawalRequest memory req = withdrawalQueue.claim(requestId);
        assets = req.assetsAtRequest;
        if (totalPooledAssets < assets) revert InsufficientPoolAssets(totalPooledAssets, assets);

        totalPooledAssets -= assets;
        cumulativeWithdrawals += assets;
        receiptToken.burnLocked(req.owner, req.shares);
        stakingToken.safeTransfer(req.receiver, assets);

        emit WithdrawalExecuted(requestId, req.owner, req.receiver, req.shares, assets);
    }

    function claim(address receiver)
        external
        nonReentrant
        onlyInitialized
        returns (uint256 amount)
    {
        if (receiver == address(0)) revert InvalidReceiver();
        amount = rewarder.claimFor(msg.sender, receiver);
        cumulativeRewardClaims += amount;
        emit RewardClaimed(msg.sender, receiver, amount);
    }

    function applyOperatorSlash(address operator, uint16 slashBps, bytes32 evidenceHash)
        external
        nonReentrant
        onlyInitialized
        returns (uint256 assetsSlashed)
    {
        if (msg.sender != address(slashingController)) {
            revert OnlySlashingController(msg.sender);
        }
        if (slashingPaused) revert SlashingPaused();
        if (slashBps == 0 || slashBps > HeliosConstants.MAX_SLASH_BPS) revert InvalidAmount();

        uint256 delegatedShares = operatorRegistry.delegatedSharesOf(operator);
        uint256 operatorAssets = previewRedeem(delegatedShares);
        assetsSlashed = HeliosMath.applyBps(operatorAssets, slashBps);
        if (assetsSlashed > totalPooledAssets) assetsSlashed = totalPooledAssets;

        if (assetsSlashed != 0) {
            totalPooledAssets -= assetsSlashed;
            cumulativeSlashed += assetsSlashed;
            stakingToken.safeTransfer(address(reserveVault), assetsSlashed);
            reserveVault.creditSlash(operator, assetsSlashed, evidenceHash);
        }

        uint256 remainingOperatorAssets =
            operatorAssets > assetsSlashed ? operatorAssets - assetsSlashed : 0;
        operatorRegistry.recordOperatorAssets(operator, remainingOperatorAssets);
        operatorRegistry.recordSlash(operator, assetsSlashed, slashBps);

        emit OperatorSlashed(operator, slashBps, operatorAssets, assetsSlashed, evidenceHash);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        uint256 supply = initialized ? receiptToken.totalSupply() : 0;
        if (supply == 0 || totalPooledAssets == 0) return assets;
        return assets * supply / totalPooledAssets;
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        uint256 supply = initialized ? receiptToken.totalSupply() : 0;
        if (supply == 0) return shares;
        return shares * totalPooledAssets / supply;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return previewRedeem(shares);
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        return previewDeposit(assets);
    }

    function exchangeRateRay() public view returns (uint256) {
        uint256 supply = initialized ? receiptToken.totalSupply() : 0;
        if (supply == 0) return HeliosConstants.RAY;
        return HeliosMath.toRay(totalPooledAssets, supply);
    }

    function totalSupply() external view returns (uint256) {
        return initialized ? receiptToken.totalSupply() : 0;
    }

    function totalLockedShares() external view returns (uint256) {
        return initialized ? receiptToken.totalLocked() : 0;
    }

    function activeSharesOf(address owner) external view returns (uint256) {
        return initialized ? receiptToken.activeBalanceOf(owner) : 0;
    }

    function freeSharesOf(address owner) external view returns (uint256) {
        return initialized ? delegationManager.freeSharesOf(owner) : 0;
    }

    function protocolSnapshot() public view returns (VaultSnapshot memory snapshot) {
        uint256 supply = initialized ? receiptToken.totalSupply() : 0;
        uint256 locked = initialized ? receiptToken.totalLocked() : 0;
        snapshot = VaultSnapshot({
            totalPooledAssets: totalPooledAssets,
            totalReceiptSupply: supply,
            totalActiveShares: supply - locked,
            totalLockedShares: locked,
            totalDelegatedShares: initialized ? delegationManager.totalDelegatedShares() : 0,
            totalQueuedShares: initialized ? withdrawalQueue.totalQueuedShares() : 0,
            cumulativeDeposits: cumulativeDeposits,
            cumulativeWithdrawals: cumulativeWithdrawals,
            cumulativeSlashed: cumulativeSlashed,
            exchangeRateRay: supply == 0
                ? HeliosConstants.RAY
                : HeliosMath.toRay(totalPooledAssets, supply)
        });
    }

    function recoverForeignToken(address token, address recipient, uint256 amount)
        external
        onlyGovernor
    {
        if (recipient == address(0)) revert InvalidReceiver();
        if (token == address(stakingToken) || token == address(rewardToken)) {
            revert UnsupportedToken(token);
        }
        IERC20(token).safeTransfer(recipient, amount);
        emit TokenRecovered(token, recipient, amount);
    }

    function _refreshOperatorAssets(address operator) internal {
        uint256 delegatedShares = operatorRegistry.delegatedSharesOf(operator);
        uint256 activeAssets = previewRedeem(delegatedShares);
        operatorRegistry.recordOperatorAssets(operator, activeAssets);
    }
}
