// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { ExitLiquidityStress } from "../src/risk/ExitLiquidityStress.sol";

contract ExitLiquidityStressTest is Test {
    ExitLiquidityStress internal model;

    function setUp() public {
        model = new ExitLiquidityStress();
    }

    function _base() internal pure returns (ExitLiquidityStress.Input memory input) {
        input = ExitLiquidityStress.Input({
            pooledAssets: 2000 ether,
            receiptSupply: 2000 ether,
            activeShares: 1500 ether,
            queuedAssets: 500 ether,
            slashShockBps: 1000,
            liquidityHaircutBps: 500,
            reserveAssets: 400 ether,
            reserveRecoveryBps: 5000,
            minimumCoverageBps: 10_000,
            guardedBufferBps: 500
        });
    }

    function testProjectionExposesLossWaterfall() public view {
        ExitLiquidityStress.Projection memory result = model.project(_base());
        assertEq(result.activeLiability, 1500 ether);
        assertEq(result.totalLiability, 2000 ether);
        assertEq(result.slashLoss, 200 ether);
        assertEq(result.liquidityLoss, 90 ether);
        assertEq(result.postShockAssets, 1710 ether);
        assertEq(result.recoverableReserve, 200 ether);
        assertEq(result.effectiveAssets, 1910 ether);
        assertEq(result.capitalShortfall, 90 ether);
        assertEq(uint256(result.severity), uint256(ExitLiquidityStress.Severity.Critical));
    }

    function testNoShockWithReserveProducesBuffer() public view {
        ExitLiquidityStress.Input memory input = _base();
        input.slashShockBps = 0;
        input.liquidityHaircutBps = 0;
        ExitLiquidityStress.Projection memory result = model.project(input);
        assertEq(result.residualBuffer, 200 ether);
        assertEq(result.residualBufferBps, 909);
        assertEq(uint256(result.severity), uint256(ExitLiquidityStress.Severity.Normal));
    }

    function testQueuedClaimsAreCoveredBeforeActiveBacking() public view {
        ExitLiquidityStress.Input memory input = _base();
        input.reserveAssets = 0;
        input.slashShockBps = 9000;
        input.liquidityHaircutBps = 0;
        ExitLiquidityStress.Projection memory result = model.project(input);
        assertEq(result.effectiveAssets, 200 ether);
        assertEq(result.queueCoverageBps, 4000);
        assertEq(result.activeBacking, 0);
        assertEq(result.activeRateRay, 0);
    }

    function testZeroQueuedAssetsHasFullQueueCoverage() public view {
        ExitLiquidityStress.Input memory input = _base();
        input.queuedAssets = 0;
        assertEq(model.project(input).queueCoverageBps, 10_000);
    }

    function testRejectsSharesAboveSupply() public {
        ExitLiquidityStress.Input memory input = _base();
        input.activeShares = input.receiptSupply + 1;
        vm.expectRevert(ExitLiquidityStress.InvalidSupply.selector);
        model.project(input);
    }

    function testRejectsPolicyAboveBps() public {
        ExitLiquidityStress.Input memory input = _base();
        input.reserveRecoveryBps = 10_001;
        vm.expectRevert(ExitLiquidityStress.InvalidPolicy.selector);
        model.project(input);
    }

    function testZeroStateIsWellDefined() public view {
        ExitLiquidityStress.Input memory input;
        input.minimumCoverageBps = 10_000;
        input.guardedBufferBps = 500;
        ExitLiquidityStress.Projection memory result = model.project(input);
        assertEq(result.queueCoverageBps, 10_000);
        assertEq(result.systemCoverageBps, 10_000);
        assertEq(uint256(result.severity), uint256(ExitLiquidityStress.Severity.Guarded));
    }

    function testFuzzProjectionNeverAllocatesNegativeBacking(
        uint128 pooled,
        uint128 reserve,
        uint16 slashBps,
        uint16 haircutBps
    ) public view {
        uint256 assets = bound(uint256(pooled), 1, type(uint128).max);
        ExitLiquidityStress.Input memory input = ExitLiquidityStress.Input({
            pooledAssets: assets,
            receiptSupply: assets,
            activeShares: assets,
            queuedAssets: 0,
            slashShockBps: bound(uint256(slashBps), 0, 10_000),
            liquidityHaircutBps: bound(uint256(haircutBps), 0, 10_000),
            reserveAssets: uint256(reserve),
            reserveRecoveryBps: 5000,
            minimumCoverageBps: 10_000,
            guardedBufferBps: 500
        });
        ExitLiquidityStress.Projection memory result = model.project(input);
        assertLe(result.activeBacking, result.effectiveAssets);
    }
}
