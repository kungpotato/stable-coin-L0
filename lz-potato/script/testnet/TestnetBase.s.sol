// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {LabBase} from "../LabBase.s.sol";

/// @notice Topics 4/7/8 on public testnets with LayerZero's OFFICIAL endpoints, DVNs and executors
/// (../testnet/config.json). Reuses LabBase's deployments/<chainId>.json bookkeeping.
abstract contract TestnetBase is LabBase {
    string internal constant TESTNET = "../testnet/config.json";

    function tn() internal view returns (string memory) {
        return vm.readFile(TESTNET);
    }

    /// @dev Key of the connected chain in testnet/config.json ("sepolia" | "arbitrum-sepolia").
    function tnLocal() internal view returns (string memory) {
        string[] memory keys = vm.parseJsonKeys(tn(), ".chains");
        for (uint256 i = 0; i < keys.length; i++) {
            if (vm.parseJsonUint(tn(), string.concat(".chains.", tnPath(keys[i]), ".chainId")) == block.chainid) return keys[i];
        }
        revert(string.concat("chainId ", vm.toString(block.chainid), " is not in ", TESTNET));
    }

    function tnChains() internal view returns (string[] memory) {
        return vm.parseJsonKeys(tn(), ".chains");
    }

    /// @dev JSON path segment for a chain key (keys contain '-').
    function tnPath(string memory key) internal pure returns (string memory) {
        return string.concat("[\"", key, "\"]");
    }

    function tnAddr(string memory chain, string memory field) internal view returns (address) {
        return vm.parseJsonAddress(tn(), string.concat(".chains.", tnPath(chain), ".", field));
    }

    function tnEid(string memory chain) internal view returns (uint32) {
        return uint32(vm.parseJsonUint(tn(), string.concat(".chains.", tnPath(chain), ".eid")));
    }

    function tnChainId(string memory chain) internal view returns (uint256) {
        return vm.parseJsonUint(tn(), string.concat(".chains.", tnPath(chain), ".chainId"));
    }

    function tnKey() internal view returns (uint256) {
        return vm.envUint("TESTNET_PRIVATE_KEY");
    }

    function eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
