// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { SlashingController } from "../src/core/SlashingController.sol";
import {
    OperatorAccounting,
    SlashRequest,
    SlashRequestStatus,
    VaultSnapshot
} from "../src/types/HeliosTypes.sol";
import { HeliosTestBase } from "./HeliosTestBase.sol";

contract SlashingTest is HeliosTestBase {
    function testQueueSlashPersistsEvidenceDelayAndProposer() public {
        _stake(ALICE, 1000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 1000 * UNIT);

        uint64 queuedAt = uint64(block.timestamp);
        uint256 requestId = _queueSlash(OPERATOR_A, DEFAULT_SLASH_BPS, DEFAULT_EVIDENCE);
        SlashRequest memory req = slashing.request(requestId);

        assertEq(req.id, requestId, "id");
        assertEq(req.operator, OPERATOR_A, "operator");
        assertEq(req.proposer, SLASHER, "proposer");
        assertEq(req.slashBps, DEFAULT_SLASH_BPS, "bps");
        assertEq(req.queuedAt, queuedAt, "queued");
        assertEq(req.executableAt, queuedAt + slashing.slashDelay(), "delay");
        assertEq(req.evidenceHash, DEFAULT_EVIDENCE, "evidence");
        assertEq(uint256(req.status), uint256(SlashRequestStatus.Queued), "status");
        assertEq(slashing.operatorRequestCount(OPERATOR_A), 1, "operator request count");
    }

    function testSlashExecutionHonorsDelayAndRecordsReserve() public {
        _stake(ALICE, 2000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 2000 * UNIT);

        uint256 requestId = _queueSlash(OPERATOR_A, 1500, DEFAULT_EVIDENCE);
        SlashRequest memory req = slashing.request(requestId);

        vm.expectRevert(
            abi.encodeWithSelector(
                SlashingController.SlashRequestNotReady.selector, requestId, req.executableAt
            )
        );
        slashing.executeSlash(requestId);

        uint256 slashed = _executeSlash(requestId);
        SlashRequest memory afterReq = slashing.request(requestId);
        OperatorAccounting memory accounting = _operatorAccounting(OPERATOR_A);

        assertEq(slashed, 300 * UNIT, "slashed amount");
        assertEq(vault.totalPooledAssets(), 1700 * UNIT, "pool assets");
        assertEq(stakeToken.balanceOf(address(reserve)), 300 * UNIT, "reserve token balance");
        assertEq(reserve.totalSlashed(), 300 * UNIT, "reserve accounted");
        assertEq(reserve.slashedByOperator(OPERATOR_A), 300 * UNIT, "operator reserve");
        assertEq(accounting.cumulativeSlashed, 300 * UNIT, "operator slashed");
        assertEq(accounting.slashCount, 1, "slash count");
        assertEq(accounting.activeAssets, 1700 * UNIT, "operator active assets");
        assertEq(uint256(afterReq.status), uint256(SlashRequestStatus.Executed), "status");
        assertEq(afterReq.assetsSlashed, 300 * UNIT, "request assets");
    }

    function testPartialSlashAdjustsExchangeRateForAllReceipts() public {
        _stake(ALICE, 1000 * UNIT);
        _stake(BOB, 1000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 1000 * UNIT);
        _delegate(BOB, OPERATOR_A, 1000 * UNIT);

        uint256 requestId = _queueSlash(OPERATOR_A, 2500, DEFAULT_EVIDENCE);
        uint256 slashed = _executeSlash(requestId);
        VaultSnapshot memory snapshot = _snapshot();

        assertEq(slashed, 500 * UNIT, "slashed amount");
        assertEq(snapshot.totalPooledAssets, 1500 * UNIT, "pooled assets");
        assertEq(snapshot.totalReceiptSupply, 2000 * UNIT, "supply unchanged");
        assertEq(vault.previewRedeem(1000 * UNIT), 750 * UNIT, "redeem value");
        assertEq(snapshot.cumulativeSlashed, 500 * UNIT, "aggregate");
    }

    function testGuardianCanCancelQueuedSlash() public {
        _stake(ALICE, 1000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 1000 * UNIT);

        uint256 requestId = _queueSlash(OPERATOR_A, DEFAULT_SLASH_BPS, DEFAULT_EVIDENCE);
        vm.prank(GUARDIAN);
        slashing.cancelSlash(requestId);

        SlashRequest memory req = slashing.request(requestId);
        assertEq(uint256(req.status), uint256(SlashRequestStatus.Cancelled), "cancelled");

        vm.warp(req.executableAt);
        vm.expectRevert(
            abi.encodeWithSelector(SlashingController.SlashRequestNotQueued.selector, requestId)
        );
        slashing.executeSlash(requestId);
    }

    function testSlashRequiresRoleAndEvidence() public {
        _stake(ALICE, 1000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 1000 * UNIT);

        vm.prank(ALICE);
        vm.expectRevert();
        slashing.queueSlash(OPERATOR_A, DEFAULT_SLASH_BPS, DEFAULT_EVIDENCE);

        vm.prank(SLASHER);
        vm.expectRevert(SlashingController.EvidenceHashRequired.selector);
        slashing.queueSlash(OPERATOR_A, DEFAULT_SLASH_BPS, bytes32(0));
    }
}
