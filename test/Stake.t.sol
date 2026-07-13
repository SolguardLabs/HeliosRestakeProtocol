// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosTestBase } from "./HeliosTestBase.sol";
import { HeliosRestakeVault } from "../src/core/HeliosRestakeVault.sol";
import { VaultSnapshot } from "../src/types/HeliosTypes.sol";

contract StakeTest is HeliosTestBase {
    function testStakeMintsReceiptSharesAndUpdatesPool() public {
        uint256 shares = _stake(ALICE, 1000 * UNIT);

        assertEq(shares, 1000 * UNIT, "initial shares");
        assertEq(receipt.balanceOf(ALICE), 1000 * UNIT, "receipt balance");
        assertEq(receipt.activeBalanceOf(ALICE), 1000 * UNIT, "active balance");
        assertEq(vault.totalPooledAssets(), 1000 * UNIT, "pool assets");
        assertEq(stakeToken.balanceOf(address(vault)), 1000 * UNIT, "vault token balance");
        assertEq(vault.cumulativeDeposits(), 1000 * UNIT, "deposit aggregate");

        VaultSnapshot memory snapshot = _snapshot();
        assertEq(snapshot.totalPooledAssets, 1000 * UNIT);
        assertEq(snapshot.totalReceiptSupply, 1000 * UNIT);
        assertEq(snapshot.totalActiveShares, 1000 * UNIT);
        assertEq(snapshot.exchangeRateRay, 1e27);
    }

    function testStakeUsesCurrentExchangeRateAfterPoolLoss() public {
        _stake(ALICE, 1000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 1000 * UNIT);

        uint256 requestId = _queueSlash(OPERATOR_A, 2000, keccak256("rate-adjustment"));
        _executeSlash(requestId);

        assertEq(vault.totalPooledAssets(), 800 * UNIT, "assets after loss");
        assertEq(vault.previewDeposit(800 * UNIT), 1000 * UNIT, "shares at adjusted rate");

        uint256 carolShares = _stake(CAROL, 800 * UNIT);
        assertEq(carolShares, 1000 * UNIT, "new depositor shares");
        assertEq(receipt.balanceOf(CAROL), 1000 * UNIT, "carol shares");
        assertEq(receipt.totalSupply(), 2000 * UNIT, "total shares");
        assertEq(vault.totalPooledAssets(), 1600 * UNIT, "new pooled assets");
    }

    function testStakeRejectsZeroAmountAndZeroReceiver() public {
        vm.startPrank(ALICE);
        stakeToken.approve(address(vault), 1000 * UNIT);

        vm.expectRevert(HeliosRestakeVault.InvalidAmount.selector);
        vault.stake(0, ALICE);

        vm.expectRevert(HeliosRestakeVault.InvalidReceiver.selector);
        vault.stake(1 * UNIT, address(0));

        vm.stopPrank();
    }

    function testGuardianCanPauseDeposits() public {
        vm.prank(GUARDIAN);
        vault.setPauseState(true, false, false, false);

        vm.startPrank(ALICE);
        stakeToken.approve(address(vault), 1000 * UNIT);
        vm.expectRevert(HeliosRestakeVault.DepositsPaused.selector);
        vault.stake(1000 * UNIT, ALICE);
        vm.stopPrank();
    }
}
