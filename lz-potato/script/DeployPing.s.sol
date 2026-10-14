// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {PingOApp} from "../src/lab/PingOApp.sol";

/// @notice Topic 11: one PingOApp per chain ("Ping"), peered to the Ping on every other chain.
/// Peers need the remote address, so run this on every chain, then once more on the first one
/// (lab-crosschain.sh does that). Re-runnable: reuses the deployment and skips peers already set.
/// env: KEY_<chain>
contract DeployPing is LabBase {
    function run() external {
        string memory local = localName();
        address endpoint = existing("EndpointV2");
        require(endpoint != address(0), "run DeployProtocol first");
        uint256 pk = deployerKey();

        vm.startBroadcast(pk);
        PingOApp ping = PingOApp(existing("Ping"));
        if (address(ping) == address(0)) {
            ping = new PingOApp(endpoint, vm.addr(pk));
            save("Ping", address(ping));
            console.log("deployed Ping", address(ping));
        } else {
            console.log("reused   Ping", address(ping));
        }

        string[] memory names = chainNames();
        for (uint256 i = 0; i < names.length; i++) {
            if (keccak256(bytes(names[i])) == keccak256(bytes(local))) continue;
            address remote = recorded(chainUint(names[i], "chainId"), "Ping");
            uint32 remoteEid = eidOf(names[i]);
            if (remote == address(0)) {
                console.log("  peer", names[i], "pending: no Ping recorded there yet");
                continue;
            }
            bytes32 want = bytes32(uint256(uint160(remote)));
            if (ping.peers(remoteEid) == want) {
                console.log("  ok   peer", names[i], remote);
            } else {
                ping.setPeer(remoteEid, want);
                console.log("  set  peer", names[i], remote);
            }
        }
        vm.stopBroadcast();
    }
}
