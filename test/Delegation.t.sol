// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosRestakeVault } from "../src/core/HeliosRestakeVault.sol";
import {
    DelegationAccount,
    DelegationStatus,
    OperatorAccounting
} from "../src/types/HeliosTypes.sol";
import { HeliosTestBase } from "./HeliosTestBase.sol";

contract DelegationTest is HeliosTestBase {
    function testDelegateUpdatesOwnerAndOperatorAccounting() public {
        _stake(ALICE, 2000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 1250 * UNIT);

        DelegationAccount memory account = delegation.delegationOf(ALICE);
        OperatorAccounting memory accounting = _operatorAccounting(OPERATOR_A);

        assertEq(account.operator, OPERATOR_A, "operator");
        assertEq(account.shares, 1250 * UNIT, "delegated shares");
        assertEq(uint256(account.status), uint256(DelegationStatus.Active), "status");
        assertEq(delegation.totalDelegatedShares(), 1250 * UNIT, "global delegated");
        assertEq(accounting.delegatedShares, 1250 * UNIT, "operator shares");
        assertEq(accounting.activeAssets, 1250 * UNIT, "operator assets");
        assertEq(delegation.freeSharesOf(ALICE), 750 * UNIT, "free shares");
    }

    function testUndelegateReleasesSharesAndClearsEmptyAccount() public {
        _stake(ALICE, 2000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 1000 * UNIT);

        _undelegate(ALICE, 400 * UNIT);
        assertEq(delegation.delegatedSharesOf(ALICE), 600 * UNIT, "partial remaining");
        assertEq(registry.delegatedSharesOf(OPERATOR_A), 600 * UNIT, "operator remaining");
        assertEq(delegation.freeSharesOf(ALICE), 1400 * UNIT, "free after partial");

        _undelegate(ALICE, 600 * UNIT);
        DelegationAccount memory account = delegation.delegationOf(ALICE);
        assertEq(account.operator, address(0), "operator cleared");
        assertEq(account.shares, 0, "shares cleared");
        assertEq(uint256(account.status), uint256(DelegationStatus.None), "status");
        assertEq(delegation.totalDelegatedShares(), 0, "global delegated");
    }

    function testCannotDelegateMoreThanFreeBalance() public {
        _stake(ALICE, 1000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 700 * UNIT);

        vm.prank(ALICE);
        vm.expectRevert();
        vault.delegate(OPERATOR_A, 400 * UNIT);
    }

    function testCannotWithdrawDelegatedSharesUntilReleased() public {
        _stake(ALICE, 1000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 800 * UNIT);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                HeliosRestakeVault.InsufficientShares.selector, 200 * UNIT, 300 * UNIT
            )
        );
        vault.requestWithdrawal(300 * UNIT, ALICE, 0);

        _undelegate(ALICE, 300 * UNIT);
        vm.prank(ALICE);
        uint256 requestId = vault.requestWithdrawal(300 * UNIT, ALICE, 0);
        assertEq(requestId, 1, "request id");
    }

    function testCannotSwitchOperatorsWhileSharesRemainDelegated() public {
        _stake(ALICE, 1000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 500 * UNIT);

        vm.prank(ALICE);
        vm.expectRevert();
        vault.delegate(OPERATOR_B, 100 * UNIT);
    }
}
