// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosConstants } from "../types/HeliosTypes.sol";
import { HeliosMath } from "../libraries/HeliosMath.sol";

/// @title ExitLiquidityStress
/// @notice Deterministic solvency projection for active and queued restaking claims.
contract ExitLiquidityStress {
    error InvalidSupply();
    error InvalidPolicy();

    enum Severity {
        Normal,
        Guarded,
        High,
        Critical
    }

    struct Input {
        uint256 pooledAssets;
        uint256 receiptSupply;
        uint256 activeShares;
        uint256 queuedAssets;
        uint256 slashShockBps;
        uint256 liquidityHaircutBps;
        uint256 reserveAssets;
        uint256 reserveRecoveryBps;
        uint256 minimumCoverageBps;
        uint256 guardedBufferBps;
    }

    struct Projection {
        uint256 activeLiability;
        uint256 totalLiability;
        uint256 slashLoss;
        uint256 liquidityLoss;
        uint256 postShockAssets;
        uint256 recoverableReserve;
        uint256 effectiveAssets;
        uint256 queueCoverageBps;
        uint256 systemCoverageBps;
        uint256 activeBacking;
        uint256 activeRateRay;
        uint256 capitalShortfall;
        uint256 residualBuffer;
        uint256 residualBufferBps;
        Severity severity;
    }

    function project(Input calldata input) external pure returns (Projection memory result) {
        _validate(input);

        if (input.receiptSupply != 0) {
            result.activeLiability =
                HeliosMath.mulDivDown(input.activeShares, input.pooledAssets, input.receiptSupply);
        }
        result.totalLiability = input.queuedAssets + result.activeLiability;
        result.slashLoss = HeliosMath.applyBps(input.pooledAssets, input.slashShockBps);
        uint256 assetsAfterSlash = input.pooledAssets - result.slashLoss;
        result.liquidityLoss = HeliosMath.applyBps(assetsAfterSlash, input.liquidityHaircutBps);
        result.postShockAssets = assetsAfterSlash - result.liquidityLoss;
        result.recoverableReserve =
            HeliosMath.applyBps(input.reserveAssets, input.reserveRecoveryBps);
        result.effectiveAssets = result.postShockAssets + result.recoverableReserve;

        if (input.queuedAssets == 0) {
            result.queueCoverageBps = HeliosConstants.BPS;
        } else {
            result.queueCoverageBps = HeliosMath.mulDivDown(
                HeliosMath.min(result.effectiveAssets, input.queuedAssets),
                HeliosConstants.BPS,
                input.queuedAssets
            );
        }
        if (result.totalLiability == 0) {
            result.systemCoverageBps = HeliosConstants.BPS;
        } else {
            result.systemCoverageBps = HeliosMath.mulDivDown(
                HeliosMath.min(result.effectiveAssets, result.totalLiability),
                HeliosConstants.BPS,
                result.totalLiability
            );
        }

        if (result.effectiveAssets > input.queuedAssets) {
            result.activeBacking = result.effectiveAssets - input.queuedAssets;
        }
        if (input.activeShares != 0) {
            result.activeRateRay = HeliosMath.mulDivDown(
                result.activeBacking, HeliosConstants.RAY, input.activeShares
            );
        }
        if (result.totalLiability > result.effectiveAssets) {
            result.capitalShortfall = result.totalLiability - result.effectiveAssets;
        } else {
            result.residualBuffer = result.effectiveAssets - result.totalLiability;
        }
        if (result.effectiveAssets != 0) {
            result.residualBufferBps = HeliosMath.mulDivDown(
                result.residualBuffer, HeliosConstants.BPS, result.effectiveAssets
            );
        }

        if (result.capitalShortfall != 0 || result.queueCoverageBps < input.minimumCoverageBps) {
            result.severity = Severity.Critical;
        } else if (result.systemCoverageBps < HeliosConstants.BPS) {
            result.severity = Severity.High;
        } else if (result.residualBufferBps < input.guardedBufferBps) {
            result.severity = Severity.Guarded;
        } else {
            result.severity = Severity.Normal;
        }
    }

    function _validate(Input calldata input) internal pure {
        if (input.receiptSupply == 0 && (input.activeShares != 0 || input.pooledAssets != 0)) {
            revert InvalidSupply();
        }
        if (input.activeShares > input.receiptSupply) revert InvalidSupply();
        if (
            input.slashShockBps > HeliosConstants.BPS
                || input.liquidityHaircutBps > HeliosConstants.BPS
                || input.reserveRecoveryBps > HeliosConstants.BPS
                || input.minimumCoverageBps > HeliosConstants.BPS
                || input.guardedBufferBps > HeliosConstants.BPS
        ) revert InvalidPolicy();
    }
}
