// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {SendUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/SendUln302.sol";
import {ReceiveUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/ReceiveUln302.sol";
import {UlnConfig, SetDefaultUlnConfigParam} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig, SetDefaultExecutorConfigParam} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";

/// @notice Topic 11: default pathway config from this chain to every other chain in config/topology.json.
/// Each chain only configures its OWN side, with its OWN DVN:
///   send    (local -> remote): local LabDVN gets the job, confirmations = local chain's
///   receive (remote -> local): local LabDVN must verify,   confirmations = remote chain's
/// Re-runnable: skips anything already set to the same value (the endpoint reverts on same-value updates).
/// env: KEY_<chain>
contract WireProtocol is LabBase {
    uint32 constant MAX_MESSAGE_SIZE = 10_000;

    function run() external {
        string memory local = localName();
        EndpointV2 endpoint = EndpointV2(existing("EndpointV2"));
        SendUln302 sendLib = SendUln302(payable(existing("SendUln302")));
        ReceiveUln302 receiveLib = ReceiveUln302(existing("ReceiveUln302"));
        address dvn = existing("LabDVN");
        address executor = existing("LabExecutor");
        require(address(endpoint) != address(0) && dvn != address(0), "run DeployProtocol first");

        string[] memory names = chainNames();
        vm.startBroadcast(deployerKey());
        for (uint256 i = 0; i < names.length; i++) {
            if (keccak256(bytes(names[i])) == keccak256(bytes(local))) continue;
            uint32 remoteEid = eidOf(names[i]);
            console.log("path", local, "<->", names[i]);

            _ensureUln(address(sendLib), remoteEid, uint64(chainUint(local, "confirmations")), dvn, "send");
            _ensureUln(address(receiveLib), remoteEid, uint64(chainUint(names[i], "confirmations")), dvn, "receive");

            ExecutorConfig memory ex = sendLib.getExecutorConfig(address(0), remoteEid);
            if (ex.executor != executor || ex.maxMessageSize != MAX_MESSAGE_SIZE) {
                SetDefaultExecutorConfigParam[] memory p = new SetDefaultExecutorConfigParam[](1);
                p[0] = SetDefaultExecutorConfigParam(remoteEid, ExecutorConfig(MAX_MESSAGE_SIZE, executor));
                sendLib.setDefaultExecutorConfigs(p);
                console.log("  set  executor config");
            } else {
                console.log("  ok   executor config");
            }

            if (endpoint.defaultSendLibrary(remoteEid) != address(sendLib)) {
                endpoint.setDefaultSendLibrary(remoteEid, address(sendLib));
                console.log("  set  default send library");
            } else {
                console.log("  ok   default send library");
            }
            if (endpoint.defaultReceiveLibrary(remoteEid) != address(receiveLib)) {
                endpoint.setDefaultReceiveLibrary(remoteEid, address(receiveLib), 0);
                console.log("  set  default receive library");
            } else {
                console.log("  ok   default receive library");
            }
        }
        vm.stopBroadcast();
    }

    function _ensureUln(address lib, uint32 remoteEid, uint64 confirmations, address dvn, string memory side) internal {
        // same view on both libs; reverts (LZ_ULN_AtLeastOneDVN) while the path has no config yet
        try SendUln302(payable(lib)).getUlnConfig(address(0), remoteEid) returns (UlnConfig memory cur) {
            if (
                cur.confirmations == confirmations && cur.requiredDVNCount == 1 && cur.requiredDVNs.length == 1
                    && cur.requiredDVNs[0] == dvn && cur.optionalDVNCount == 0
            ) {
                console.log("  ok  ", side, "ULN config");
                return;
            }
        } catch {}
        address[] memory required = new address[](1);
        required[0] = dvn;
        SetDefaultUlnConfigParam[] memory p = new SetDefaultUlnConfigParam[](1);
        p[0] = SetDefaultUlnConfigParam(remoteEid, UlnConfig(confirmations, 1, 0, 0, required, new address[](0)));
        SendUln302(payable(lib)).setDefaultUlnConfigs(p);
        console.log("  set ", side, "ULN config");
    }
}
