// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosConstants } from "../types/HeliosTypes.sol";

contract HeliosAccess {
    error ZeroAddress();
    error Unauthorized(bytes32 role, address account);
    error CannotRemoveLastGovernor();

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    mapping(bytes32 => mapping(address => bool)) private _roles;
    uint256 public governorCount;

    constructor(address initialGovernor, address initialGuardian) {
        if (initialGovernor == address(0) || initialGuardian == address(0)) revert ZeroAddress();
        _grant(HeliosConstants.GOVERNOR_ROLE, initialGovernor);
        _grant(HeliosConstants.GUARDIAN_ROLE, initialGuardian);
        governorCount = 1;
    }

    modifier onlyGovernor() {
        checkRole(HeliosConstants.GOVERNOR_ROLE, msg.sender);
        _;
    }

    modifier onlyGuardianOrGovernor() {
        if (
            !hasRole(HeliosConstants.GUARDIAN_ROLE, msg.sender)
                && !hasRole(HeliosConstants.GOVERNOR_ROLE, msg.sender)
        ) revert Unauthorized(HeliosConstants.GUARDIAN_ROLE, msg.sender);
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function checkRole(bytes32 role, address account) public view {
        if (!_roles[role][account]) revert Unauthorized(role, account);
    }

    function grantRole(bytes32 role, address account) external onlyGovernor {
        if (account == address(0)) revert ZeroAddress();
        if (!_roles[role][account]) {
            if (role == HeliosConstants.GOVERNOR_ROLE) governorCount += 1;
            _grant(role, account);
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function revokeRole(bytes32 role, address account) external onlyGovernor {
        if (!_roles[role][account]) return;
        if (role == HeliosConstants.GOVERNOR_ROLE) {
            if (governorCount == 1) revert CannotRemoveLastGovernor();
            governorCount -= 1;
        }
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function requireRole(bytes32 role, address account) external view {
        checkRole(role, account);
    }

    function _grant(bytes32 role, address account) internal {
        _roles[role][account] = true;
    }
}
