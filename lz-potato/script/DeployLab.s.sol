// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {SendUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/SendUln302.sol";
import {ReceiveUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/ReceiveUln302.sol";
import {UlnConfig, SetDefaultUlnConfigParam} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig, SetDefaultExecutorConfigParam} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import {LabDVN} from "../src/lab/LabDVN.sol";
import {LabExecutor} from "../src/lab/LabExecutor.sol";
import {PingOApp} from "../src/lab/PingOApp.sol";

/// @notice Self-hosted LayerZero V2 stack on one chain + two PingOApps wired to each other (loopback path).
/// env: PRIVATE_KEY, LOCAL_EID, CONFIRMATIONS (default 1)
contract DeployLab is Script {
    EndpointV2 endpoint;
    SendUln302 sendLib;
    ReceiveUln302 receiveLib;
    LabDVN dvn;
    LabExecutor executor;
    PingOApp a;
    PingOApp b;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        uint32 eid = uint32(vm.envUint("LOCAL_EID"));
        address admin = vm.addr(pk);

        vm.startBroadcast(pk);
        _deployProtocol(eid, admin);
        _setDefaults(eid, uint64(vm.envOr("CONFIRMATIONS", uint256(1))));
        _deployPing(eid, admin);
        vm.stopBroadcast();

        _save(eid);
    }

    function _deployProtocol(uint32 eid, address admin) internal {
        endpoint = new EndpointV2(eid, admin);
        sendLib = new SendUln302(address(endpoint), 0, 0);
        receiveLib = new ReceiveUln302(address(endpoint));
        dvn = new LabDVN(admin);
        executor = new LabExecutor();
        endpoint.registerLibrary(address(sendLib));
        endpoint.registerLibrary(address(receiveLib));
    }

    /// @dev Loopback: the only remote path is this chain's own eid. Topic 10 adds a real second chain.
    function _setDefaults(uint32 eid, uint64 confirmations) internal {
        address[] memory required = new address[](1);
        required[0] = address(dvn);
        SetDefaultUlnConfigParam[] memory ulnParams = new SetDefaultUlnConfigParam[](1);
        ulnParams[0] = SetDefaultUlnConfigParam(eid, UlnConfig(confirmations, 1, 0, 0, required, new address[](0)));
        sendLib.setDefaultUlnConfigs(ulnParams);
        receiveLib.setDefaultUlnConfigs(ulnParams);

        SetDefaultExecutorConfigParam[] memory exParams = new SetDefaultExecutorConfigParam[](1);
        exParams[0] = SetDefaultExecutorConfigParam(eid, ExecutorConfig(10_000, address(executor)));
        sendLib.setDefaultExecutorConfigs(exParams);

        endpoint.setDefaultSendLibrary(eid, address(sendLib));
        endpoint.setDefaultReceiveLibrary(eid, address(receiveLib), 0);
    }

    function _deployPing(uint32 eid, address admin) internal {
        a = new PingOApp(address(endpoint), admin);
        b = new PingOApp(address(endpoint), admin);
        // Same eid on both sides, so each OApp has exactly one peer: A <-> B.
        a.setPeer(eid, bytes32(uint256(uint160(address(b)))));
        b.setPeer(eid, bytes32(uint256(uint160(address(a)))));
    }

    function _save(uint32 eid) internal {
        string memory k = "lz";
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeUint(k, "eid", eid);
        vm.serializeAddress(k, "EndpointV2", address(endpoint));
        vm.serializeAddress(k, "SendUln302", address(sendLib));
        vm.serializeAddress(k, "ReceiveUln302", address(receiveLib));
        vm.serializeAddress(k, "LabDVN", address(dvn));
        vm.serializeAddress(k, "LabExecutor", address(executor));
        vm.serializeAddress(k, "PingA", address(a));
        string memory json = vm.serializeAddress(k, "PingB", address(b));
        vm.writeJson(json, string.concat("deployments/", vm.toString(block.chainid), ".json"));
        console.log("EndpointV2", address(endpoint));
    }
}
