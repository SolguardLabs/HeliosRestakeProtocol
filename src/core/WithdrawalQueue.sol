// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    HeliosConstants,
    WithdrawalRequest,
    WithdrawalRound,
    WithdrawalStatus
} from "../types/HeliosTypes.sol";
import { HeliosAccess } from "../security/HeliosAccess.sol";

contract WithdrawalQueue {
    error ZeroAddress();
    error OnlyVault(address sender);
    error InvalidReceiver();
    error InvalidShares();
    error RequestNotFound(uint256 requestId);
    error RequestNotOwned(uint256 requestId, address expected, address actual);
    error RequestNotPending(uint256 requestId);
    error RequestNotReady(uint256 requestId, uint64 claimableAt);
    error RequestExpired(uint256 requestId, uint64 expiresAt);
    error MinimumAssetsNotMet(uint256 assets, uint256 minimum);
    error DelayOutOfRange(uint256 delay);

    event VaultConfigured(address indexed vault);
    event WithdrawalDelayUpdated(uint64 previous, uint64 next);
    event RequestOpened(
        uint256 indexed requestId,
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 assets,
        uint64 claimableAt
    );
    event RequestMarkedClaimable(uint256 indexed requestId);
    event RequestCancelled(uint256 indexed requestId, address indexed owner, uint256 shares);
    event RequestClaimed(
        uint256 indexed requestId,
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 assets
    );

    HeliosAccess public immutable accessManager;

    address public vault;
    uint256 public nextRequestId = 1;
    uint64 public withdrawalDelay = 1 days;
    uint64 public requestTtl = 10 days;
    uint256 public totalQueuedShares;
    uint256 public totalQueuedAssets;
    uint256 public cumulativeClaimedShares;
    uint256 public cumulativeClaimedAssets;

    mapping(uint256 => WithdrawalRequest) private _requests;
    mapping(address => uint256[]) private _ownerRequests;
    mapping(uint64 => WithdrawalRound) private _rounds;

    constructor(address accessManager_) {
        if (accessManager_ == address(0)) revert ZeroAddress();
        accessManager = HeliosAccess(accessManager_);
    }

    modifier onlyGovernor() {
        accessManager.checkRole(HeliosConstants.GOVERNOR_ROLE, msg.sender);
        _;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault(msg.sender);
        _;
    }

    function setVault(address vault_) external onlyGovernor {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
        emit VaultConfigured(vault_);
    }

    function setWithdrawalDelay(uint64 delay) external onlyGovernor {
        if (
            delay < HeliosConstants.MIN_WITHDRAWAL_DELAY
                || delay > HeliosConstants.MAX_WITHDRAWAL_DELAY
        ) revert DelayOutOfRange(delay);
        uint64 previous = withdrawalDelay;
        withdrawalDelay = delay;
        emit WithdrawalDelayUpdated(previous, delay);
    }

    function open(
        address owner,
        address receiver,
        address operatorAtRequest,
        uint256 shares,
        uint256 assetsAtRequest,
        uint256 minAssets,
        uint64 epoch
    ) external onlyVault returns (uint256 requestId) {
        if (owner == address(0) || receiver == address(0)) revert InvalidReceiver();
        if (shares == 0) revert InvalidShares();

        requestId = nextRequestId++;
        uint64 requestedAt = uint64(block.timestamp);
        uint64 claimableAt = requestedAt + withdrawalDelay;
        uint64 expiresAt = claimableAt + requestTtl;

        _requests[requestId] = WithdrawalRequest({
            id: requestId,
            owner: owner,
            receiver: receiver,
            operatorAtRequest: operatorAtRequest,
            shares: shares,
            assetsAtRequest: assetsAtRequest,
            minAssets: minAssets,
            requestedAt: requestedAt,
            claimableAt: claimableAt,
            expiresAt: expiresAt,
            epoch: epoch,
            status: WithdrawalStatus.Pending
        });
        _ownerRequests[owner].push(requestId);

        totalQueuedShares += shares;
        totalQueuedAssets += assetsAtRequest;

        WithdrawalRound storage round = _rounds[epoch];
        if (round.epoch == 0) round.epoch = epoch;
        round.sharesQueued += shares;
        round.assetsReserved += assetsAtRequest;
        round.requestCount += 1;

        emit RequestOpened(requestId, owner, receiver, shares, assetsAtRequest, claimableAt);
    }

    function markClaimable(uint256 requestId) external onlyVault {
        WithdrawalRequest storage req = _requestStorage(requestId);
        if (req.status != WithdrawalStatus.Pending) revert RequestNotPending(requestId);
        if (block.timestamp < req.claimableAt) revert RequestNotReady(requestId, req.claimableAt);
        req.status = WithdrawalStatus.Claimable;
        emit RequestMarkedClaimable(requestId);
    }

    function cancel(uint256 requestId, address caller)
        external
        onlyVault
        returns (WithdrawalRequest memory req)
    {
        req = _requestStorage(requestId);
        if (req.owner != caller) revert RequestNotOwned(requestId, req.owner, caller);
        if (req.status != WithdrawalStatus.Pending && req.status != WithdrawalStatus.Claimable) {
            revert RequestNotPending(requestId);
        }

        _requests[requestId].status = WithdrawalStatus.Cancelled;
        totalQueuedShares -= req.shares;
        totalQueuedAssets -= req.assetsAtRequest;
        emit RequestCancelled(requestId, req.owner, req.shares);
    }

    function claim(uint256 requestId) external onlyVault returns (WithdrawalRequest memory req) {
        req = _requestStorage(requestId);
        if (req.status == WithdrawalStatus.Pending) {
            if (block.timestamp < req.claimableAt) {
                revert RequestNotReady(requestId, req.claimableAt);
            }
            _requests[requestId].status = WithdrawalStatus.Claimable;
            emit RequestMarkedClaimable(requestId);
        } else if (req.status != WithdrawalStatus.Claimable) {
            revert RequestNotPending(requestId);
        }
        if (block.timestamp > req.expiresAt) revert RequestExpired(requestId, req.expiresAt);
        if (req.assetsAtRequest < req.minAssets) {
            revert MinimumAssetsNotMet(req.assetsAtRequest, req.minAssets);
        }

        _requests[requestId].status = WithdrawalStatus.Claimed;
        totalQueuedShares -= req.shares;
        totalQueuedAssets -= req.assetsAtRequest;
        cumulativeClaimedShares += req.shares;
        cumulativeClaimedAssets += req.assetsAtRequest;

        WithdrawalRound storage round = _rounds[req.epoch];
        round.sharesClaimed += req.shares;
        round.assetsClaimed += req.assetsAtRequest;

        emit RequestClaimed(requestId, req.owner, req.receiver, req.shares, req.assetsAtRequest);
    }

    function request(uint256 requestId) external view returns (WithdrawalRequest memory) {
        return _requestStorage(requestId);
    }

    function statusOf(uint256 requestId) external view returns (WithdrawalStatus) {
        return _requestStorage(requestId).status;
    }

    function ownerRequestCount(address owner) external view returns (uint256) {
        return _ownerRequests[owner].length;
    }

    function ownerRequestAt(address owner, uint256 index) external view returns (uint256) {
        return _ownerRequests[owner][index];
    }

    function ownerRequests(address owner, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory result)
    {
        uint256 length = _ownerRequests[owner].length;
        if (offset >= length) return new uint256[](0);
        uint256 end = offset + limit;
        if (end > length) end = length;
        result = new uint256[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            result[i - offset] = _ownerRequests[owner][i];
        }
    }

    function roundInfo(uint64 epoch) external view returns (WithdrawalRound memory) {
        return _rounds[epoch];
    }

    function _requestStorage(uint256 requestId)
        internal
        view
        returns (WithdrawalRequest storage req)
    {
        req = _requests[requestId];
        if (req.id == 0) revert RequestNotFound(requestId);
    }
}
