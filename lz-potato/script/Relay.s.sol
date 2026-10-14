// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {EndpointV2, Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {ReceiveUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/ReceiveUln302.sol";
import {LabDVN} from "../src/lab/LabDVN.sol";

/// @notice Does by hand what the DVN + Executor workers do (topic 12 automates it):
///   1. DVN attests  -> ReceiveUln302.verify   (via LabDVN, emits PayloadVerified)
///   2. anyone       -> ReceiveUln302.commitVerification -> EndpointV2.verify (emits PacketVerified)
///   3. executor     -> EndpointV2.lzReceive -> OApp._lzReceive (emits PacketDelivered)
/// env: PRIVATE_KEY, PAYLOAD (encodedPayload from EndpointV2.PacketSent), CONFIRMATIONS (default 1)
contract Relay is Script {
    // PacketV1 layout: version(1) nonce(8) srcEid(4) sender(32) dstEid(4) receiver(32) | guid(32) message(...)
    uint256 constant HEADER_LEN = 81;

    function run() external {
        bytes memory payload = vm.envBytes("PAYLOAD");
        string memory dep = vm.readFile(string.concat("deployments/", vm.toString(block.chainid), ".json"));
        EndpointV2 endpoint = EndpointV2(vm.parseJsonAddress(dep, ".EndpointV2"));
        ReceiveUln302 receiveLib = ReceiveUln302(vm.parseJsonAddress(dep, ".ReceiveUln302"));
        LabDVN dvn = LabDVN(vm.parseJsonAddress(dep, ".LabDVN"));

        bytes memory header = _slice(payload, 0, HEADER_LEN);
        bytes memory body = _slice(payload, HEADER_LEN, payload.length - HEADER_LEN); // guid ++ message
        bytes32 payloadHash = keccak256(body);
        bytes32 guid = bytes32(_slice(body, 0, 32));
        bytes memory message = _slice(body, 32, body.length - 32);

        Origin memory origin = Origin({
            srcEid: uint32(bytes4(_slice(header, 9, 4))),
            sender: bytes32(_slice(header, 13, 32)),
            nonce: uint64(bytes8(_slice(header, 1, 8)))
        });
        address receiver = address(uint160(uint256(bytes32(_slice(header, 49, 32)))));
        console.log("nonce", origin.nonce, "srcEid", origin.srcEid);
        console.log("receiver", receiver);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        dvn.verify(address(receiveLib), header, payloadHash, uint64(vm.envOr("CONFIRMATIONS", uint256(1))));
        receiveLib.commitVerification(header, payloadHash);
        endpoint.lzReceive(origin, receiver, guid, message, "");
        vm.stopBroadcast();
    }

    function _slice(bytes memory b, uint256 start, uint256 len) internal pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i = 0; i < len; i++) out[i] = b[start + i];
    }
}
