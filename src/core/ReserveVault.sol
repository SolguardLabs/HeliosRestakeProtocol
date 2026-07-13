// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "../interfaces/IERC20.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { HeliosAccess } from "../security/HeliosAccess.sol";
import { HeliosConstants } from "../types/HeliosTypes.sol";

contract ReserveVault {
    using SafeTransferLib for IERC20;

    error ZeroAddress();
    error OnlyVault(address sender);
    error UnsupportedToken(address token);
    error InvalidRecipient();

    event VaultConfigured(address indexed vault);
    event SlashCredited(address indexed operator, uint256 amount, bytes32 indexed evidenceHash);
    event FeesCredited(address indexed source, uint256 amount);
    event ReserveReleased(address indexed recipient, uint256 amount, string reason);
    event ForeignTokenRecovered(address indexed token, address indexed recipient, uint256 amount);

    IERC20 public immutable stakingToken;
    HeliosAccess public immutable accessManager;
    address public vault;
    uint256 public totalSlashed;
    uint256 public totalFees;
    uint256 public totalReleased;

    mapping(address => uint256) public slashedByOperator;

    constructor(address stakingToken_, address accessManager_) {
        if (stakingToken_ == address(0) || accessManager_ == address(0)) revert ZeroAddress();
        stakingToken = IERC20(stakingToken_);
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

    function creditSlash(address operator, uint256 amount, bytes32 evidenceHash)
        external
        onlyVault
    {
        totalSlashed += amount;
        slashedByOperator[operator] += amount;
        emit SlashCredited(operator, amount, evidenceHash);
    }

    function creditFees(address source, uint256 amount) external onlyVault {
        totalFees += amount;
        emit FeesCredited(source, amount);
    }

    function release(address recipient, uint256 amount, string calldata reason)
        external
        onlyGovernor
    {
        if (recipient == address(0)) revert InvalidRecipient();
        totalReleased += amount;
        stakingToken.safeTransfer(recipient, amount);
        emit ReserveReleased(recipient, amount, reason);
    }

    function accountedBalance() external view returns (uint256) {
        return totalSlashed + totalFees - totalReleased;
    }

    function recoverForeignToken(address token, address recipient, uint256 amount)
        external
        onlyGovernor
    {
        if (recipient == address(0)) revert InvalidRecipient();
        if (token == address(stakingToken)) revert UnsupportedToken(token);
        IERC20(token).safeTransfer(recipient, amount);
        emit ForeignTokenRecovered(token, recipient, amount);
    }
}
