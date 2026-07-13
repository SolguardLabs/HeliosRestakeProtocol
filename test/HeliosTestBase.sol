// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { HeliosAccess } from "../src/security/HeliosAccess.sol";
import { HeliosReceiptToken } from "../src/token/HeliosReceiptToken.sol";
import { HeliosRestakeVault } from "../src/core/HeliosRestakeVault.sol";
import { OperatorRegistry } from "../src/core/OperatorRegistry.sol";
import { DelegationManager } from "../src/core/DelegationManager.sol";
import { WithdrawalQueue } from "../src/core/WithdrawalQueue.sol";
import { EpochRewarder } from "../src/core/EpochRewarder.sol";
import { ReserveVault } from "../src/core/ReserveVault.sol";
import { SlashingController } from "../src/core/SlashingController.sol";
import { HeliosLens } from "../src/views/HeliosLens.sol";
import { HeliosMonitor } from "../src/monitoring/HeliosMonitor.sol";
import {
    HeliosConstants,
    OperatorAccounting,
    SlashRequest,
    VaultSnapshot,
    WithdrawalRequest
} from "../src/types/HeliosTypes.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract HeliosTestBase is Test {
    uint256 internal constant UNIT = 1 ether;
    uint16 internal constant DEFAULT_SLASH_BPS = 2500;
    uint96 internal constant LARGE_OPERATOR_LIMIT = 20_000 ether;
    uint96 internal constant SMALL_OPERATOR_LIMIT = 5000 ether;
    bytes32 internal constant DEFAULT_EVIDENCE = keccak256("helios:evidence:operator-a");

    address internal constant GOVERNOR = address(0xA11CE);
    address internal constant GUARDIAN = address(0xB0B0);
    address internal constant ALICE = address(0xA1);
    address internal constant BOB = address(0xB2);
    address internal constant CAROL = address(0xC3);
    address internal constant DAN = address(0xD4);
    address internal constant OPERATOR_A = address(0x0A);
    address internal constant OPERATOR_B = address(0x0B);
    address internal constant OPERATOR_C = address(0x0C);
    address internal constant SLASHER = address(0x51A5);
    address internal constant KEEPER = address(0x4EE9);
    address internal constant REWARDER = address(0x9EAD);
    address internal constant TREASURY = address(0x7EA5);

    MockERC20 internal stakeToken;
    MockERC20 internal rewardToken;
    HeliosAccess internal access;
    HeliosRestakeVault internal vault;
    HeliosReceiptToken internal receipt;
    OperatorRegistry internal registry;
    DelegationManager internal delegation;
    WithdrawalQueue internal queue;
    EpochRewarder internal rewarder;
    ReserveVault internal reserve;
    SlashingController internal slashing;
    HeliosLens internal lens;
    HeliosMonitor internal monitor;

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        stakeToken = new MockERC20("Helios Staking Token", "hSTK", 18);
        rewardToken = new MockERC20("Helios Reward Token", "hRWD", 18);

        vm.startPrank(GOVERNOR);
        access = new HeliosAccess(GOVERNOR, GUARDIAN);
        access.grantRole(HeliosConstants.SLASHER_ROLE, SLASHER);
        access.grantRole(HeliosConstants.KEEPER_ROLE, KEEPER);
        access.grantRole(HeliosConstants.REWARDER_ROLE, REWARDER);

        vault = new HeliosRestakeVault(address(stakeToken), address(rewardToken), address(access));
        receipt = new HeliosReceiptToken("Helios Restaked Share", "hrsSTK", 18, address(vault));
        registry = new OperatorRegistry(address(access));
        delegation = new DelegationManager(address(access), address(receipt), address(registry));
        queue = new WithdrawalQueue(address(access));
        rewarder = new EpochRewarder(address(rewardToken), address(access));
        reserve = new ReserveVault(address(stakeToken), address(access));
        slashing = new SlashingController(address(access), address(registry));

        delegation.setVault(address(vault));
        queue.setVault(address(vault));
        rewarder.setVault(address(vault));
        rewarder.setDelegationManager(address(delegation));
        reserve.setVault(address(vault));
        slashing.setVault(address(vault));
        registry.setAccountingModule(address(delegation), address(vault));

        vault.initializeModules(
            address(receipt),
            address(registry),
            address(delegation),
            address(queue),
            address(rewarder),
            address(reserve),
            address(slashing)
        );

        registry.registerOperator(
            OPERATOR_A, OPERATOR_A, TREASURY, 500, LARGE_OPERATOR_LIMIT, keccak256("operator-a")
        );
        registry.registerOperator(
            OPERATOR_B, OPERATOR_B, TREASURY, 750, LARGE_OPERATOR_LIMIT, keccak256("operator-b")
        );
        registry.registerOperator(
            OPERATOR_C, OPERATOR_C, TREASURY, 1000, SMALL_OPERATOR_LIMIT, keccak256("operator-c")
        );
        vm.stopPrank();

        _mintStake(ALICE, 100_000 * UNIT);
        _mintStake(BOB, 100_000 * UNIT);
        _mintStake(CAROL, 100_000 * UNIT);
        _mintStake(DAN, 100_000 * UNIT);
        rewardToken.mint(REWARDER, 100_000 * UNIT);
    }

    function _mintStake(address user, uint256 amount) internal {
        stakeToken.mint(user, amount);
    }

    function _stake(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        stakeToken.approve(address(vault), amount);
        shares = vault.stake(amount, user);
        vm.stopPrank();
    }

    function _delegate(address user, address operator, uint256 shares) internal {
        vm.prank(user);
        vault.delegate(operator, shares);
    }

    function _undelegate(address user, uint256 shares) internal {
        vm.prank(user);
        vault.undelegate(shares);
    }

    function _requestWithdrawal(address user, uint256 shares, address receiver, uint256 minAssets)
        internal
        returns (uint256 requestId)
    {
        vm.prank(user);
        requestId = vault.requestWithdrawal(shares, receiver, minAssets);
    }

    function _executeWithdrawal(uint256 requestId) internal returns (uint256 assets) {
        WithdrawalRequest memory req = queue.request(requestId);
        vm.warp(req.claimableAt);
        vm.prank(KEEPER);
        assets = vault.executeWithdrawal(requestId);
    }

    function _fundAndFinalizeEpoch(uint64 epochId, uint256 amount) internal {
        vm.startPrank(REWARDER);
        rewardToken.approve(address(rewarder), amount);
        rewarder.fundEpoch(
            epochId, amount, uint64(block.timestamp), uint64(block.timestamp + 1 days)
        );
        rewarder.finalizeEpoch(epochId);
        vm.stopPrank();
    }

    function _queueSlash(address operator, uint16 slashBps, bytes32 evidence)
        internal
        returns (uint256 requestId)
    {
        vm.prank(SLASHER);
        requestId = slashing.queueSlash(operator, slashBps, evidence);
    }

    function _executeSlash(uint256 requestId) internal returns (uint256 assetsSlashed) {
        SlashRequest memory req = slashing.request(requestId);
        vm.warp(req.executableAt);
        vm.prank(KEEPER);
        assetsSlashed = slashing.executeSlash(requestId);
    }

    function _snapshot() internal view returns (VaultSnapshot memory) {
        return vault.protocolSnapshot();
    }

    function _operatorAccounting(address operator)
        internal
        view
        returns (OperatorAccounting memory)
    {
        return registry.accountingOf(operator);
    }
}
