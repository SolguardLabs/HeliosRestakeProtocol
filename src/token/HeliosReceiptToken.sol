// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20, IERC20Metadata } from "../interfaces/IERC20.sol";

contract HeliosReceiptToken is IERC20Metadata {
    error ZeroAddress();
    error InsufficientBalance(uint256 available, uint256 required);
    error InsufficientAllowance(uint256 available, uint256 required);
    error InsufficientActiveBalance(uint256 available, uint256 required);
    error OnlyVault(address sender);

    string public name;
    string public symbol;
    uint8 public immutable decimals;
    address public vault;

    uint256 public override totalSupply;
    uint256 public totalLocked;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    mapping(address => uint256) public lockedBalanceOf;

    event VaultConfigured(address indexed vault);
    event SharesLocked(address indexed owner, uint256 amount);
    event SharesUnlocked(address indexed owner, uint256 amount);

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault(msg.sender);
        _;
    }

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address vault_) {
        if (vault_ == address(0)) revert ZeroAddress();
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        vault = vault_;
        emit VaultConfigured(vault_);
    }

    function activeBalanceOf(address owner) public view returns (uint256) {
        return balanceOf[owner] - lockedBalanceOf[owner];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        override
        returns (bool)
    {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance(allowed, amount);
            allowance[from][msg.sender] = allowed - amount;
            emit Approval(from, msg.sender, allowed - amount);
        }
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external onlyVault {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyVault {
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance(balance, amount);
        uint256 locked = lockedBalanceOf[from];
        if (balance - locked < amount) revert InsufficientActiveBalance(balance - locked, amount);
        unchecked {
            balanceOf[from] = balance - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    function lock(address owner, uint256 amount) external onlyVault {
        uint256 active = activeBalanceOf(owner);
        if (active < amount) revert InsufficientActiveBalance(active, amount);
        lockedBalanceOf[owner] += amount;
        totalLocked += amount;
        emit SharesLocked(owner, amount);
    }

    function unlock(address owner, uint256 amount) external onlyVault {
        uint256 locked = lockedBalanceOf[owner];
        if (locked < amount) revert InsufficientBalance(locked, amount);
        unchecked {
            lockedBalanceOf[owner] = locked - amount;
            totalLocked -= amount;
        }
        emit SharesUnlocked(owner, amount);
    }

    function burnLocked(address owner, uint256 amount) external onlyVault {
        uint256 locked = lockedBalanceOf[owner];
        uint256 balance = balanceOf[owner];
        if (locked < amount) revert InsufficientBalance(locked, amount);
        if (balance < amount) revert InsufficientBalance(balance, amount);
        unchecked {
            lockedBalanceOf[owner] = locked - amount;
            balanceOf[owner] = balance - amount;
            totalLocked -= amount;
            totalSupply -= amount;
        }
        emit SharesUnlocked(owner, amount);
        emit Transfer(owner, address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        uint256 active = activeBalanceOf(from);
        if (active < amount) revert InsufficientActiveBalance(active, amount);
        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}
