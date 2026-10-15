// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {BlockedMessageLib} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/BlockedMessageLib.sol";

/// @notice Incident containment (topic 3/8): cut one OApp off from every path on the connected chain by pointing
/// its send AND receive library at BlockedMessageLib (every call reverts). Works for OApps without a pause switch;
/// only the OApp's delegate can do it, and only it can undo it. In-flight messages stay where they are.
/// SIDES=send|receive|both (default both): one side only retires a leg while keeping an exit open, e.g. block new
/// deposits (home send, remote receive) but let holders bridge back (remote send, home receive).
/// env: KEY_<chain>, ASSET (deployments key of the OApp), SIDES (optional)
contract ContainOApp is LabBase {
    function run() external {
        string memory asset = vm.envString("ASSET");
        string memory sides = vm.envOr("SIDES", string("both"));
        bool doSend = keccak256(bytes(sides)) != keccak256("receive");
        bool doReceive = keccak256(bytes(sides)) != keccak256("send");
        EndpointV2 endpoint = EndpointV2(existing("EndpointV2"));
        address oapp = existing(asset);
        require(oapp != address(0), "unknown OApp");

        vm.startBroadcast(deployerKey());
        address blocked = existing("BlockedMessageLib");
        if (blocked == address(0)) { // one per endpoint, registered by the endpoint owner
            blocked = address(new BlockedMessageLib());
            endpoint.registerLibrary(blocked);
            save("BlockedMessageLib", blocked);
            console.log("deployed + registered BlockedMessageLib", blocked);
        }
        string[] memory names = chainNames();
        string memory local = localName();
        for (uint256 i = 0; i < names.length; i++) {
            if (keccak256(bytes(names[i])) == keccak256(bytes(local))) continue;
            uint32 eid = eidOf(names[i]);
            address sendLib = endpoint.getSendLibrary(oapp, eid);
            if (doSend && sendLib != blocked) endpoint.setSendLibrary(oapp, eid, blocked);
            (address receiveLib,) = endpoint.getReceiveLibrary(oapp, eid);
            if (doReceive && receiveLib != blocked) endpoint.setReceiveLibrary(oapp, eid, blocked, 0); // no grace period
            console.log(string.concat("  contained ", asset, " <-> ", names[i], ": ", sides, " = BlockedMessageLib"));
        }
        vm.stopBroadcast();
    }
}
