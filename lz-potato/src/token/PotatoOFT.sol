// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/// @notice POTATO on non-home chains (ADR 0002): minted when POTATO is locked on potato, burned when it goes back.
contract PotatoOFT is OFT {
    constructor(address _endpoint, address _owner) OFT("Potato", "POTATO", _endpoint, _owner) Ownable(_owner) {}
}
