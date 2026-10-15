// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Topic 7 (lzCompose): a minimal ERC-4626 vault for USDC.lz on potato, the compose target.
/// The owner can close deposits to exercise the composer's refund path.
contract UsdcVault is ERC4626, Ownable {
    bool public depositsOpen = true;

    constructor(IERC20 _usdc, address _owner) ERC20("Potato USDC Vault", "pvUSDC") ERC4626(_usdc) Ownable(_owner) {}

    function setDepositsOpen(bool _open) external onlyOwner {
        depositsOpen = _open;
    }

    function maxDeposit(address) public view override returns (uint256) {
        return depositsOpen ? type(uint256).max : 0;
    }
}
