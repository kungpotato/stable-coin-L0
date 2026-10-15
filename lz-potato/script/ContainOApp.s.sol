// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {BlockedMessageLib} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/BlockedMessageLib.sol";

/// @notice Incident containment (topic 3/8): cut one OApp off from every path on the connected chain by pointing
/// its send AND receive library at BlockedMessageLib (every call reverts). Works for OApps without a pause switch;
/// only the OApp's delegate can do it, and only it can undo it. In-flight messages stay where they are.
/// env: KEY_<chain>, ASSET (deployments key of the OApp)
contract ContainOApp is LabBase {
    function run() external {
        string memory asset = vm.envString("ASSET");
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
            if (sendLib != blocked) endpoint.setSendLibrary(oapp, eid, blocked);
            (address receiveLib,) = endpoint.getReceiveLibrary(oapp, eid);
            if (receiveLib != blocked) endpoint.setReceiveLibrary(oapp, eid, blocked, 0); // no grace period
            console.log(string.concat("  contained ", asset, " <-> ", names[i], " (send + receive = BlockedMessageLib)"));
        }
        vm.stopBroadcast();
    }
}
