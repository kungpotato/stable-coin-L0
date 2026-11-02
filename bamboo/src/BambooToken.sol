// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IBridgeToken} from "./IBridgeToken.sol";

/// @title BambooToken
/// @notice LAB MOCK of an issuer's stablecoin. It exists only so the lab has a
///         token to move; it is NOT part of the protocol. A real issuer keeps
///         their own (proxy-upgradable) token and just implements IBridgeToken
///         + grants the gateway a minter role.
///
///         This mock mirrors how a real token integrates:
///           - a `minter` ROLE (not single-owner, not "owned by the gateway")
///           - allowance-based burnFrom
///         so wiring bamboo never costs the issuer control of their token.
contract BambooToken is IBridgeToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;
    mapping(address => bool) public isMinter; // issuer grants this to bridge gateways

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MinterSet(address indexed minter, bool allowed);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyMinter() {
        require(isMinter[msg.sender], "not minter");
        _;
    }

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
    }

    /// @notice Issuer authorizes a bridge gateway as minter/burner. Revocable.
    ///         The issuer keeps ownership and every other control of the token.
    function setMinter(address m, bool allowed) external onlyOwner {
        isMinter[m] = allowed;
        emit MinterSet(m, allowed);
    }

    /// @notice Seed supply for the demo (owner only).
    function ownerMint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // --- IBridgeToken (bridge hooks) ---
    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    /// @notice Allowance-based burn: the user approves the gateway, the gateway burns.
    ///         The gateway cannot burn balances it was not approved for.
    function burnFrom(address from, uint256 amount) external onlyMinter {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    // --- standard ERC20 ---
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // --- internals ---
    function _spendAllowance(address from, address spender, uint256 amount) internal {
        uint256 a = allowance[from][spender];
        if (a != type(uint256).max) {
            require(a >= amount, "allowance");
            allowance[from][spender] = a - amount;
        }
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "to zero");
        uint256 b = balanceOf[from];
        require(b >= amount, "balance");
        unchecked {
            balanceOf[from] = b - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "to zero");
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        uint256 b = balanceOf[from];
        require(b >= amount, "balance");
        unchecked {
            balanceOf[from] = b - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}
