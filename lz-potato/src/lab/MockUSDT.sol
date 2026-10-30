// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Lab stand-in for USDT (6 decimals, anyone can mint).
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock Tether", "USDT") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
