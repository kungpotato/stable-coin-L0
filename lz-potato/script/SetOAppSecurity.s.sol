// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

/// @notice Topic 3: per-OApp DVN config for one bridge leg on the connected chain (overrides the defaults).
///   MODE=one       send + receive require LabDVN only                    (one key compromised = forged mints)
///   MODE=two       send + receive require LabDVN and LabDVN_B            (two independent operators)
///   MODE=mismatch  send requires LabDVN only, receive requires both      (B is never assigned: messages stall)
/// The OApp's delegate (owner) calls EndpointV2.setConfig. Re-runnable: unchanged configs are skipped.
/// env: KEY_<chain>, ASSET, MODE
contract SetOAppSecurity is LabBase {
    uint32 constant CONFIG_TYPE_ULN = 2;

    EndpointV2 endpoint;
    address oapp;
    address sendLib;
    address receiveLib;
    address[] sendDvns;
    address[] receiveDvns;

    function run() external {
        string memory asset = vm.envString("ASSET");
        string memory mode = vm.envString("MODE");
        require(_eq(mode, "one") || _eq(mode, "two") || _eq(mode, "mismatch"), "MODE must be one|two|mismatch");
        endpoint = EndpointV2(existing("EndpointV2"));
        oapp = existing(asset);
        sendLib = existing("SendUln302");
        receiveLib = existing("ReceiveUln302");
        require(oapp != address(0), "deploy the asset first");

        address[] memory one = new address[](1);
        one[0] = existing("LabDVN");
        address[] memory two = _sorted(existing("LabDVN"), existing("LabDVN_B"));
        sendDvns = _eq(mode, "two") ? two : one;
        receiveDvns = _eq(mode, "one") ? one : two;

        string memory local = localName();
        string[] memory names = chainNames();
        vm.startBroadcast(deployerKey());
        for (uint256 i = 0; i < names.length; i++) {
            if (!_eq(names[i], local)) _path(local, names[i]);
        }
        vm.stopBroadcast();
    }

    function _path(string memory local, string memory remote) internal {
        uint32 eid = eidOf(remote);
        // sending waits for this chain's confirmations; receiving for the remote chain's
        _set(sendLib, eid, _uln(uint64(chainUint(local, "confirmations")), sendDvns), "send   ", remote);
        _set(receiveLib, eid, _uln(uint64(chainUint(remote, "confirmations")), receiveDvns), "receive", remote);
    }

    function _set(address lib, uint32 eid, bytes memory cfg, string memory side, string memory remote) internal {
        if (keccak256(endpoint.getConfig(oapp, lib, eid, CONFIG_TYPE_ULN)) == keccak256(cfg)) {
            console.log("  ok  ", side, remote);
            return;
        }
        SetConfigParam[] memory p = new SetConfigParam[](1);
        p[0] = SetConfigParam(eid, CONFIG_TYPE_ULN, cfg);
        endpoint.setConfig(oapp, lib, p);
        UlnConfig memory u = abi.decode(cfg, (UlnConfig));
        console.log("  set ", side, remote);
        console.log("       required DVNs:", u.requiredDVNCount);
    }

    function _uln(uint64 confirmations, address[] memory required) internal pure returns (bytes memory) {
        return abi.encode(UlnConfig(confirmations, uint8(required.length), 0, 0, required, new address[](0)));
    }

    /// @dev ULN rejects unsorted or duplicate DVN lists
    function _sorted(address a, address b) internal pure returns (address[] memory s) {
        s = new address[](2);
        (s[0], s[1]) = a < b ? (a, b) : (b, a);
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
