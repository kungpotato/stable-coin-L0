// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";

/// @notice Shared helpers: find this chain in config/topology.json and read/update deployments/<chainId>.json.
/// Deploy scripts reuse any address that already has code, so they are safe to re-run.
abstract contract LabBase is Script {
    string internal constant TOPOLOGY = "config/topology.json";

    function topology() internal view returns (string memory) {
        return vm.readFile(TOPOLOGY);
    }

    function chainNames() internal view returns (string[] memory) {
        return vm.parseJsonKeys(topology(), ".chains");
    }

    /// @dev Name of the chain we're connected to; reverts if the RPC is not a chain from the topology.
    function localName() internal view returns (string memory) {
        string[] memory names = chainNames();
        for (uint256 i = 0; i < names.length; i++) {
            if (chainUint(names[i], "chainId") == block.chainid) return names[i];
        }
        revert(string.concat("chainId ", vm.toString(block.chainid), " is not in ", TOPOLOGY));
    }

    function chainUint(string memory name, string memory field) internal view returns (uint256) {
        return vm.parseJsonUint(topology(), string.concat(".chains.", name, ".", field));
    }

    function eidOf(string memory name) internal view returns (uint32) {
        return uint32(chainUint(name, "eid"));
    }

    function deploymentsPath(uint256 chainId) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", vm.toString(chainId), ".json");
    }

    /// @dev Address recorded for `key` on `chainId`, or 0 if missing. Does not check code (may be another chain).
    function recorded(uint256 chainId, string memory key) internal view returns (address) {
        string memory path = deploymentsPath(chainId);
        if (!vm.exists(path)) return address(0);
        string memory json = vm.readFile(path);
        string memory k = string.concat(".", key);
        return vm.keyExistsJson(json, k) ? vm.parseJsonAddress(json, k) : address(0);
    }

    /// @dev Recorded address on this chain that still has code (0 if never deployed or the chain was reset).
    function existing(string memory key) internal view returns (address a) {
        a = recorded(block.chainid, key);
        if (a != address(0) && a.code.length == 0) a = address(0);
    }

    /// @dev Upsert `key` in deployments/<chainid>.json, keeping the other keys.
    function save(string memory key, address value) internal {
        string memory path = deploymentsPath(block.chainid);
        string memory obj = "deployments";
        if (vm.exists(path)) vm.serializeJson(obj, vm.readFile(path));
        vm.serializeUint(obj, "chainId", block.chainid);
        string memory json = vm.serializeAddress(obj, key, value);
        vm.writeJson(json, path);
    }

    function deployerKey() internal view returns (uint256) {
        return vm.envUint(string.concat("KEY_", localName()));
    }
}
