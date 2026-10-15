// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Stand-in for the issuer's canonical USDC on its home chain (anvil, ADR 0003): the issuer (owner)
/// mints against deposits and burns on redemption. The bridge never mints it; it only locks it in UsdcAdapter.
contract IssuerUSDC is ERC20, Ownable {
    constructor(address _issuer) ERC20("USD Coin", "USDC") Ownable(_issuer) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) external onlyOwner {
        _burn(msg.sender, _amount);
    }
}
