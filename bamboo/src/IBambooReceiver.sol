// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IBambooReceiver
/// @notice Any app that wants to receive cross-chain messages implements this.
///         The gateway calls it AFTER verifying the attester threshold, so the
///         app only needs to (a) check msg.sender == gateway and (b) check the
///         source `sender` is a peer it trusts.
interface IBambooReceiver {
    function bambooReceive(uint64 srcChainId, address sender, bytes calldata payload) external;
}
