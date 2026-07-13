// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosAccess } from "../security/HeliosAccess.sol";
import { HeliosConstants, SlashRequest, SlashRequestStatus } from "../types/HeliosTypes.sol";
import { OperatorRegistry } from "./OperatorRegistry.sol";

interface IHeliosSlashTarget {
    function applyOperatorSlash(address operator, uint16 slashBps, bytes32 evidenceHash)
        external
        returns (uint256 assetsSlashed);
}

contract SlashingController {
    error ZeroAddress();
    error UnauthorizedSlasher(address sender);
    error InvalidSlashBps(uint16 slashBps);
    error EvidenceHashRequired();
    error SlashDelayOutOfRange(uint64 delay);
    error SlashRequestNotFound(uint256 requestId);
    error SlashRequestNotQueued(uint256 requestId);
    error SlashRequestNotReady(uint256 requestId, uint64 executableAt);
    error SlashingPaused();

    event VaultConfigured(address indexed vault);
    event SlashDelayUpdated(uint64 previous, uint64 next);
    event SlashingPauseUpdated(bool paused);
    event SlashQueued(
        uint256 indexed requestId,
        address indexed operator,
        uint16 slashBps,
        uint64 executableAt,
        bytes32 indexed evidenceHash
    );
    event SlashCancelled(uint256 indexed requestId, address indexed canceller);
    event SlashExecuted(
        uint256 indexed requestId, address indexed operator, uint16 slashBps, uint256 assetsSlashed
    );

    HeliosAccess public immutable accessManager;
    OperatorRegistry public immutable operatorRegistry;

    address public vault;
    uint256 public nextRequestId = 1;
    uint64 public slashDelay = 1 days;
    bool public slashingPaused;

    mapping(uint256 => SlashRequest) private _requests;
    mapping(address => uint256[]) private _operatorRequests;

    constructor(address accessManager_, address operatorRegistry_) {
        if (accessManager_ == address(0) || operatorRegistry_ == address(0)) revert ZeroAddress();
        accessManager = HeliosAccess(accessManager_);
        operatorRegistry = OperatorRegistry(operatorRegistry_);
    }

    modifier onlyGovernor() {
        accessManager.checkRole(HeliosConstants.GOVERNOR_ROLE, msg.sender);
        _;
    }

    modifier onlyGuardianOrGovernor() {
        if (
            !accessManager.hasRole(HeliosConstants.GUARDIAN_ROLE, msg.sender)
                && !accessManager.hasRole(HeliosConstants.GOVERNOR_ROLE, msg.sender)
        ) {
            accessManager.checkRole(HeliosConstants.GUARDIAN_ROLE, msg.sender);
        }
        _;
    }

    function setVault(address vault_) external onlyGovernor {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
        emit VaultConfigured(vault_);
    }

    function setSlashDelay(uint64 delay) external onlyGovernor {
        if (delay < HeliosConstants.MIN_SLASH_DELAY || delay > HeliosConstants.MAX_SLASH_DELAY) {
            revert SlashDelayOutOfRange(delay);
        }
        uint64 previous = slashDelay;
        slashDelay = delay;
        emit SlashDelayUpdated(previous, delay);
    }

    function setSlashingPaused(bool paused) external onlyGuardianOrGovernor {
        slashingPaused = paused;
        emit SlashingPauseUpdated(paused);
    }

    function queueSlash(address operator, uint16 slashBps, bytes32 evidenceHash)
        external
        returns (uint256 requestId)
    {
        if (slashingPaused) revert SlashingPaused();
        if (
            !accessManager.hasRole(HeliosConstants.SLASHER_ROLE, msg.sender)
                && !accessManager.hasRole(HeliosConstants.GOVERNOR_ROLE, msg.sender)
        ) revert UnauthorizedSlasher(msg.sender);
        if (slashBps == 0 || slashBps > HeliosConstants.MAX_SLASH_BPS) {
            revert InvalidSlashBps(slashBps);
        }
        if (evidenceHash == bytes32(0)) revert EvidenceHashRequired();
        operatorRegistry.requireActiveOperator(operator);

        requestId = nextRequestId++;
        uint64 queuedAt = uint64(block.timestamp);
        uint64 executableAt = queuedAt + slashDelay;

        _requests[requestId] = SlashRequest({
            id: requestId,
            operator: operator,
            proposer: msg.sender,
            slashBps: slashBps,
            queuedAt: queuedAt,
            executableAt: executableAt,
            executedAt: 0,
            evidenceHash: evidenceHash,
            status: SlashRequestStatus.Queued,
            assetsSlashed: 0
        });
        _operatorRequests[operator].push(requestId);

        emit SlashQueued(requestId, operator, slashBps, executableAt, evidenceHash);
    }

    function cancelSlash(uint256 requestId) external onlyGuardianOrGovernor {
        SlashRequest storage req = _requestStorage(requestId);
        if (req.status != SlashRequestStatus.Queued) revert SlashRequestNotQueued(requestId);
        req.status = SlashRequestStatus.Cancelled;
        emit SlashCancelled(requestId, msg.sender);
    }

    function executeSlash(uint256 requestId) external returns (uint256 assetsSlashed) {
        SlashRequest storage req = _requestStorage(requestId);
        if (req.status != SlashRequestStatus.Queued) revert SlashRequestNotQueued(requestId);
        if (block.timestamp < req.executableAt) {
            revert SlashRequestNotReady(requestId, req.executableAt);
        }

        assetsSlashed = IHeliosSlashTarget(vault)
            .applyOperatorSlash(req.operator, req.slashBps, req.evidenceHash);
        req.status = SlashRequestStatus.Executed;
        req.executedAt = uint64(block.timestamp);
        req.assetsSlashed = assetsSlashed;

        emit SlashExecuted(requestId, req.operator, req.slashBps, assetsSlashed);
    }

    function request(uint256 requestId) external view returns (SlashRequest memory) {
        return _requestStorage(requestId);
    }

    function operatorRequestCount(address operator) external view returns (uint256) {
        return _operatorRequests[operator].length;
    }

    function operatorRequestAt(address operator, uint256 index) external view returns (uint256) {
        return _operatorRequests[operator][index];
    }

    function _requestStorage(uint256 requestId) internal view returns (SlashRequest storage req) {
        req = _requests[requestId];
        if (req.id == 0) revert SlashRequestNotFound(requestId);
    }
}
