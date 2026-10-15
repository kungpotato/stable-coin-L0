// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {LabDVN} from "../src/lab/LabDVN.sol";

/// @notice Topic 3: two more LabDVNs per chain ("LabDVN_B", "LabDVN_C"), each owned by its own operator key,
/// so a path can require several independent attestations. Funds the operators' gas. Re-runnable.
/// env: KEY_<chain>, DVN_B_KEY, DVN_C_KEY
contract DeployExtraDvns is LabBase {
    function run() external {
        vm.startBroadcast(deployerKey());
        _dvn("LabDVN_B", vm.addr(vm.envUint("DVN_B_KEY")));
        _dvn("LabDVN_C", vm.addr(vm.envUint("DVN_C_KEY")));
        vm.stopBroadcast();
    }

    function _dvn(string memory key, address operator) internal {
        address dvn = existing(key);
        if (dvn == address(0)) {
            dvn = address(new LabDVN(operator));
            save(key, dvn);
            console.log("deployed", key, dvn);
        } else {
            console.log("reused  ", key, dvn);
        }
        if (operator.balance < 5 ether) {
            payable(operator).transfer(10 ether);
            console.log("  funded operator", operator);
        }
    }
}
