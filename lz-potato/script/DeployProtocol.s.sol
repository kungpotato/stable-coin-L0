// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {SendUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/SendUln302.sol";
import {ReceiveUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/ReceiveUln302.sol";
import {LabDVN} from "../src/lab/LabDVN.sol";
import {LabExecutor} from "../src/lab/LabExecutor.sol";

/// @notice Topic 11: LayerZero V2 protocol on the connected chain (EID from config/topology.json).
/// Re-runnable: anything already deployed (code at the recorded address) is reused, not redeployed.
/// env: KEY_<chain> (config/dev-keys.env)
contract DeployProtocol is LabBase {
    function run() external {
        string memory name = localName();
        uint32 eid = eidOf(name);
        uint256 pk = deployerKey();
        address admin = vm.addr(pk);
        console.log("chain", name, "eid", eid);

        vm.startBroadcast(pk);

        address endpoint = existing("EndpointV2");
        if (endpoint == address(0)) {
            endpoint = address(new EndpointV2(eid, admin));
            save("EndpointV2", endpoint);
            console.log("deployed EndpointV2", endpoint);
        } else {
            require(EndpointV2(endpoint).eid() == eid, "recorded EndpointV2 has a different eid");
            console.log("reused   EndpointV2", endpoint);
        }

        address sendLib = existing("SendUln302");
        if (sendLib == address(0)) {
            sendLib = address(new SendUln302(endpoint, 0, 0));
            EndpointV2(endpoint).registerLibrary(sendLib);
            save("SendUln302", sendLib);
            console.log("deployed SendUln302", sendLib);
        } else {
            console.log("reused   SendUln302", sendLib);
        }

        address receiveLib = existing("ReceiveUln302");
        if (receiveLib == address(0)) {
            receiveLib = address(new ReceiveUln302(endpoint));
            EndpointV2(endpoint).registerLibrary(receiveLib);
            save("ReceiveUln302", receiveLib);
            console.log("deployed ReceiveUln302", receiveLib);
        } else {
            console.log("reused   ReceiveUln302", receiveLib);
        }

        address dvn = existing("LabDVN");
        if (dvn == address(0)) {
            dvn = address(new LabDVN(admin));
            save("LabDVN", dvn);
            console.log("deployed LabDVN", dvn);
        } else {
            console.log("reused   LabDVN", dvn);
        }

        address executor = existing("LabExecutor");
        if (executor == address(0)) {
            executor = address(new LabExecutor());
            save("LabExecutor", executor);
            console.log("deployed LabExecutor", executor);
        } else {
            console.log("reused   LabExecutor", executor);
        }

        vm.stopBroadcast();
        save("EndpointV2", endpoint); // also records chainId on a fresh file
    }
}
