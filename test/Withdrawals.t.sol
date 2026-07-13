// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosRestakeVault } from "../src/core/HeliosRestakeVault.sol";
import { WithdrawalQueue } from "../src/core/WithdrawalQueue.sol";
import { WithdrawalRequest, WithdrawalStatus } from "../src/types/HeliosTypes.sol";
import { HeliosTestBase } from "./HeliosTestBase.sol";

contract WithdrawalsTest is HeliosTestBase {
    function testRequestWithdrawalLocksSharesAndStoresRequest() public {
        _stake(ALICE, 1000 * UNIT);

        uint256 requestId = _requestWithdrawal(ALICE, 400 * UNIT, CAROL, 395 * UNIT);
        WithdrawalRequest memory req = queue.request(requestId);

        assertEq(req.owner, ALICE, "owner");
        assertEq(req.receiver, CAROL, "receiver");
        assertEq(req.shares, 400 * UNIT, "shares");
        assertEq(req.assetsAtRequest, 400 * UNIT, "assets");
        assertEq(req.minAssets, 395 * UNIT, "minimum");
        assertEq(uint256(req.status), uint256(WithdrawalStatus.Pending), "status");
        assertEq(receipt.lockedBalanceOf(ALICE), 400 * UNIT, "locked");
        assertEq(receipt.activeBalanceOf(ALICE), 600 * UNIT, "active");
        assertEq(queue.totalQueuedShares(), 400 * UNIT, "queued shares");
        assertEq(queue.totalQueuedAssets(), 400 * UNIT, "queued assets");
    }

    function testCancelWithdrawalUnlocksShares() public {
        _stake(ALICE, 1000 * UNIT);
        uint256 requestId = _requestWithdrawal(ALICE, 300 * UNIT, ALICE, 0);

        vm.prank(ALICE);
        uint256 shares = vault.cancelWithdrawal(requestId);

        assertEq(shares, 300 * UNIT, "cancelled shares");
        assertEq(receipt.lockedBalanceOf(ALICE), 0, "locked cleared");
        assertEq(receipt.activeBalanceOf(ALICE), 1000 * UNIT, "active restored");
        assertEq(queue.totalQueuedShares(), 0, "queue shares cleared");
        assertEq(queue.totalQueuedAssets(), 0, "queue assets cleared");
        assertEq(uint256(queue.statusOf(requestId)), uint256(WithdrawalStatus.Cancelled), "status");
    }

    function testExecuteWithdrawalAfterDelayPaysReceiverAndBurnsShares() public {
        _stake(ALICE, 1000 * UNIT);
        _stake(BOB, 1000 * UNIT);
        uint256 requestId = _requestWithdrawal(ALICE, 250 * UNIT, CAROL, 240 * UNIT);
        uint256 carolBefore = stakeToken.balanceOf(CAROL);

        uint256 assets = _executeWithdrawal(requestId);

        assertEq(assets, 250 * UNIT, "assets");
        assertEq(stakeToken.balanceOf(CAROL) - carolBefore, 250 * UNIT, "receiver paid");
        assertEq(receipt.balanceOf(ALICE), 750 * UNIT, "alice shares");
        assertEq(receipt.totalSupply(), 1750 * UNIT, "total supply");
        assertEq(receipt.totalLocked(), 0, "locked cleared");
        assertEq(vault.totalPooledAssets(), 1750 * UNIT, "pool assets");
        assertEq(vault.cumulativeWithdrawals(), 250 * UNIT, "withdrawals");
        assertEq(uint256(queue.statusOf(requestId)), uint256(WithdrawalStatus.Claimed), "status");
    }

    function testExecuteWithdrawalBeforeDelayReverts() public {
        _stake(ALICE, 1000 * UNIT);
        uint256 requestId = _requestWithdrawal(ALICE, 100 * UNIT, ALICE, 0);
        WithdrawalRequest memory req = queue.request(requestId);

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalQueue.RequestNotReady.selector, requestId, req.claimableAt
            )
        );
        vault.executeWithdrawal(requestId);
    }

    function testMinimumAssetsIsCheckedAtExecution() public {
        _stake(ALICE, 1000 * UNIT);
        uint256 requestId = _requestWithdrawal(ALICE, 100 * UNIT, ALICE, 101 * UNIT);
        WithdrawalRequest memory req = queue.request(requestId);
        vm.warp(req.claimableAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalQueue.MinimumAssetsNotMet.selector, 100 * UNIT, 101 * UNIT
            )
        );
        vault.executeWithdrawal(requestId);
        assertEq(receipt.lockedBalanceOf(ALICE), 100 * UNIT, "request remains locked");
    }

    function testWithdrawalsCanBePausedByGuardian() public {
        _stake(ALICE, 1000 * UNIT);

        vm.prank(GUARDIAN);
        vault.setPauseState(false, true, false, false);

        vm.prank(ALICE);
        vm.expectRevert(HeliosRestakeVault.WithdrawalsPaused.selector);
        vault.requestWithdrawal(100 * UNIT, ALICE, 0);
    }
}
