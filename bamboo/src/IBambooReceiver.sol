// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IBambooReceiver
/// @notice Any app that receives cross-chain messages implements this. The gateway
///         calls it AFTER verifying the attester threshold, and passes the `msgId`
///         so the app can reference the message (e.g. to send an ACK back).
///         The app should check msg.sender == gateway and that `sender` is a trusted peer.
interface IBambooReceiver {
    function bambooReceive(uint64 srcChainId, address sender, bytes32 msgId, bytes calldata payload) external;
}
