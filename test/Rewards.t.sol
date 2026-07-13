// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { EpochData } from "../src/types/HeliosTypes.sol";
import { HeliosTestBase } from "./HeliosTestBase.sol";

contract RewardsTest is HeliosTestBase {
    function testEpochRewardsAreDistributedByDelegatedShares() public {
        _stake(ALICE, 1000 * UNIT);
        _stake(BOB, 3000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 1000 * UNIT);
        _delegate(BOB, OPERATOR_B, 3000 * UNIT);

        _fundAndFinalizeEpoch(1, 400 * UNIT);

        assertEq(rewarder.previewAccrued(ALICE), 100 * UNIT, "alice accrued");
        assertEq(rewarder.previewAccrued(BOB), 300 * UNIT, "bob accrued");

        vm.prank(ALICE);
        uint256 aliceClaim = vault.claim(ALICE);
        vm.prank(BOB);
        uint256 bobClaim = vault.claim(BOB);

        assertEq(aliceClaim, 100 * UNIT, "alice claim");
        assertEq(bobClaim, 300 * UNIT, "bob claim");
        assertEq(rewardToken.balanceOf(ALICE), 100 * UNIT, "alice reward token");
        assertEq(rewardToken.balanceOf(BOB), 300 * UNIT, "bob reward token");
        assertEq(rewarder.totalClaimedRewards(), 400 * UNIT, "claimed aggregate");
        assertEq(vault.cumulativeRewardClaims(), 400 * UNIT, "vault aggregate");
    }

    function testCheckpointKeepsAccruedRewardsAcrossUndelegation() public {
        _stake(ALICE, 1000 * UNIT);
        _stake(BOB, 1000 * UNIT);
        _delegate(ALICE, OPERATOR_A, 1000 * UNIT);
        _delegate(BOB, OPERATOR_A, 1000 * UNIT);

        _fundAndFinalizeEpoch(1, 200 * UNIT);
        _undelegate(ALICE, 500 * UNIT);

        assertEq(rewarder.claimableRewards(ALICE), 100 * UNIT, "checkpointed before change");
        assertEq(delegation.delegatedSharesOf(ALICE), 500 * UNIT, "remaining shares");

        _fundAndFinalizeEpoch(2, 300 * UNIT);
        assertEq(rewarder.previewAccrued(ALICE), 200 * UNIT, "alice total");
        assertEq(rewarder.previewAccrued(BOB), 300 * UNIT, "bob total");
    }

    function testEpochWithoutEligibleSharesIsTrackedAsUnallocated() public {
        _fundAndFinalizeEpoch(1, 250 * UNIT);

        EpochData memory epoch = rewarder.epoch(1);
        assertTrue(epoch.finalized, "finalized");
        assertEq(epoch.eligibleShares, 0, "eligible");
        assertEq(rewarder.unallocatedRewards(), 250 * UNIT, "unallocated");
        assertEq(rewarder.globalRewardIndex(), 0, "index unchanged");
    }

    function testOnlyRewarderRoleCanFundEpochs() public {
        rewardToken.mint(ALICE, 10 * UNIT);
        vm.startPrank(ALICE);
        rewardToken.approve(address(rewarder), 10 * UNIT);
        vm.expectRevert();
        rewarder.fundEpoch(1, 10 * UNIT, uint64(block.timestamp), uint64(block.timestamp + 1 days));
        vm.stopPrank();
    }
}
