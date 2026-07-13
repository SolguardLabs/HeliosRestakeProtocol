// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "../interfaces/IERC20.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { HeliosAccess } from "../security/HeliosAccess.sol";
import { HeliosConstants } from "../types/HeliosTypes.sol";
import { OperatorRegistry } from "./OperatorRegistry.sol";

contract FeeController {
    using SafeTransferLib for IERC20;

    error ZeroAddress();
    error InvalidBps(uint256 value);
    error InvalidRecipient();
    error UnauthorizedReporter(address sender);
    error NothingToClaim();

    struct FeeConfig {
        address treasury;
        uint32 protocolRewardFeeBps;
        uint32 maxOperatorCommissionBps;
        bool operatorClaimsPaused;
        bool treasuryClaimsPaused;
    }

    struct FeeAccount {
        uint256 accrued;
        uint256 claimed;
        uint256 lastAccruedEpoch;
        uint256 lastClaimedAt;
    }

    struct EpochFeeBreakdown {
        uint64 epochId;
        uint256 grossRewards;
        uint256 protocolFee;
        uint256 operatorCommission;
        uint256 delegatorRewards;
        uint256 operatorCount;
    }

    event RegistryConfigured(address indexed registry);
    event FeeConfigUpdated(FeeConfig previous, FeeConfig next);
    event ReporterUpdated(address indexed reporter, bool enabled);
    event EpochFeesRecorded(
        uint64 indexed epochId,
        uint256 grossRewards,
        uint256 protocolFee,
        uint256 operatorCommission,
        uint256 delegatorRewards
    );
    event OperatorCommissionAccrued(
        uint64 indexed epochId, address indexed operator, uint256 amount, uint256 bps
    );
    event TreasuryFeeAccrued(uint64 indexed epochId, uint256 amount);
    event OperatorFeesClaimed(address indexed operator, address indexed receiver, uint256 amount);
    event TreasuryFeesClaimed(address indexed receiver, uint256 amount);

    IERC20 public immutable rewardToken;
    HeliosAccess public immutable accessManager;
    OperatorRegistry public registry;

    FeeConfig private _config;
    uint256 public totalProtocolFeesAccrued;
    uint256 public totalProtocolFeesClaimed;
    uint256 public totalOperatorFeesAccrued;
    uint256 public totalOperatorFeesClaimed;

    mapping(address => bool) public reporters;
    mapping(address => FeeAccount) private _operatorFees;
    mapping(uint64 => EpochFeeBreakdown) private _epochFees;
    uint64[] private _feeEpochs;
    mapping(uint64 => bool) private _seenEpoch;

    constructor(address rewardToken_, address accessManager_, address treasury_) {
        if (rewardToken_ == address(0) || accessManager_ == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }
        rewardToken = IERC20(rewardToken_);
        accessManager = HeliosAccess(accessManager_);
        _config = FeeConfig({
            treasury: treasury_,
            protocolRewardFeeBps: 500,
            maxOperatorCommissionBps: uint32(HeliosConstants.MAX_COMMISSION_BPS),
            operatorClaimsPaused: false,
            treasuryClaimsPaused: false
        });
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

    function setRegistry(address registry_) external onlyGovernor {
        if (registry_ == address(0)) revert ZeroAddress();
        registry = OperatorRegistry(registry_);
        emit RegistryConfigured(registry_);
    }

    function setReporter(address reporter, bool enabled) external onlyGovernor {
        if (reporter == address(0)) revert ZeroAddress();
        reporters[reporter] = enabled;
        emit ReporterUpdated(reporter, enabled);
    }

    function setFeeConfig(FeeConfig calldata next) external onlyGovernor {
        if (next.treasury == address(0)) revert ZeroAddress();
        if (
            next.protocolRewardFeeBps > HeliosConstants.BPS
                || next.maxOperatorCommissionBps > HeliosConstants.MAX_COMMISSION_BPS
        ) revert InvalidBps(next.protocolRewardFeeBps);

        FeeConfig memory previous = _config;
        _config = next;
        emit FeeConfigUpdated(previous, next);
    }

    function recordEpochFees(uint64 epochId, uint256 grossRewards, address[] calldata operators)
        external
        onlyReporter
        returns (EpochFeeBreakdown memory breakdown)
    {
        FeeConfig memory localConfig = _config;
        uint256 protocolFee = grossRewards * localConfig.protocolRewardFeeBps / HeliosConstants.BPS;
        uint256 remaining = grossRewards - protocolFee;
        uint256 totalOperatorCommission;

        _touchEpoch(epochId);
        for (uint256 i = 0; i < operators.length; ++i) {
            address operator = operators[i];
            uint256 bps = registry.commissionBpsOf(operator);
            if (bps > localConfig.maxOperatorCommissionBps) {
                bps = localConfig.maxOperatorCommissionBps;
            }
            uint256 commission =
                remaining * bps / HeliosConstants.BPS / _nonZeroLength(operators.length);
            if (commission == 0) continue;
            totalOperatorCommission += commission;
            FeeAccount storage account = _operatorFees[operator];
            account.accrued += commission;
            account.lastAccruedEpoch = epochId;
            emit OperatorCommissionAccrued(epochId, operator, commission, bps);
        }

        totalProtocolFeesAccrued += protocolFee;
        totalOperatorFeesAccrued += totalOperatorCommission;

        breakdown = EpochFeeBreakdown({
            epochId: epochId,
            grossRewards: grossRewards,
            protocolFee: protocolFee,
            operatorCommission: totalOperatorCommission,
            delegatorRewards: remaining - totalOperatorCommission,
            operatorCount: operators.length
        });
        _epochFees[epochId] = breakdown;

        emit TreasuryFeeAccrued(epochId, protocolFee);
        emit EpochFeesRecorded(
            epochId, grossRewards, protocolFee, totalOperatorCommission, breakdown.delegatorRewards
        );
    }

    function claimOperatorFees(address operator, address receiver)
        external
        returns (uint256 amount)
    {
        if (_config.operatorClaimsPaused) revert NothingToClaim();
        if (receiver == address(0)) revert InvalidRecipient();
        if (
            msg.sender != operator
                && !accessManager.hasRole(HeliosConstants.GOVERNOR_ROLE, msg.sender)
        ) revert UnauthorizedReporter(msg.sender);

        FeeAccount storage account = _operatorFees[operator];
        amount = account.accrued - account.claimed;
        if (amount == 0) revert NothingToClaim();
        account.claimed += amount;
        account.lastClaimedAt = block.timestamp;
        totalOperatorFeesClaimed += amount;
        rewardToken.safeTransfer(receiver, amount);

        emit OperatorFeesClaimed(operator, receiver, amount);
    }

    function claimTreasuryFees(address receiver) external onlyGovernor returns (uint256 amount) {
        if (_config.treasuryClaimsPaused) revert NothingToClaim();
        address recipient = receiver == address(0) ? _config.treasury : receiver;
        amount = totalProtocolFeesAccrued - totalProtocolFeesClaimed;
        if (amount == 0) revert NothingToClaim();
        totalProtocolFeesClaimed += amount;
        rewardToken.safeTransfer(recipient, amount);
        emit TreasuryFeesClaimed(recipient, amount);
    }

    function quoteFees(uint256 grossRewards, address[] calldata operators)
        external
        view
        returns (uint256 protocolFee, uint256 operatorCommission, uint256 delegatorRewards)
    {
        FeeConfig memory localConfig = _config;
        protocolFee = grossRewards * localConfig.protocolRewardFeeBps / HeliosConstants.BPS;
        uint256 remaining = grossRewards - protocolFee;
        for (uint256 i = 0; i < operators.length; ++i) {
            uint256 bps = registry.commissionBpsOf(operators[i]);
            if (bps > localConfig.maxOperatorCommissionBps) {
                bps = localConfig.maxOperatorCommissionBps;
            }
            operatorCommission += remaining * bps / HeliosConstants.BPS
                / _nonZeroLength(operators.length);
        }
        delegatorRewards = remaining - operatorCommission;
    }

    function config() external view returns (FeeConfig memory) {
        return _config;
    }

    function operatorFees(address operator) external view returns (FeeAccount memory) {
        return _operatorFees[operator];
    }

    function epochFees(uint64 epochId) external view returns (EpochFeeBreakdown memory) {
        return _epochFees[epochId];
    }

    function feeEpochCount() external view returns (uint256) {
        return _feeEpochs.length;
    }

    function feeEpochAt(uint256 index) external view returns (uint64) {
        return _feeEpochs[index];
    }

    function feeEpochPage(uint256 offset, uint256 limit)
        external
        view
        returns (EpochFeeBreakdown[] memory result)
    {
        uint256 length = _feeEpochs.length;
        if (offset >= length) return new EpochFeeBreakdown[](0);
        uint256 end = offset + limit;
        if (end > length) end = length;
        result = new EpochFeeBreakdown[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            result[i - offset] = _epochFees[_feeEpochs[i]];
        }
    }

    function _touchEpoch(uint64 epochId) internal {
        if (_seenEpoch[epochId]) return;
        _seenEpoch[epochId] = true;
        _feeEpochs.push(epochId);
    }

    function _nonZeroLength(uint256 length) internal pure returns (uint256) {
        return length == 0 ? 1 : length;
    }
}
