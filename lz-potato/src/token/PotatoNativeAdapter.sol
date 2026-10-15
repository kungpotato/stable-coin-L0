// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {NativeOFTAdapter} from "@layerzerolabs/oft-evm/contracts/NativeOFTAdapter.sol";

/// @notice potato side of POTATO (home chain, ADR 0002): locks native POTATO sent as msg.value,
/// releases it with a native transfer when POTATO comes back. Its native balance is the backing
/// for PotatoOFT on every other chain.
contract PotatoNativeAdapter is NativeOFTAdapter {
    constructor(address _endpoint, address _owner) NativeOFTAdapter(18, _endpoint, _owner) Ownable(_owner) {}
}
