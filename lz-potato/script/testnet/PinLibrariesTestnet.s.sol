// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {TestnetBase} from "./TestnetBase.s.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";

/// @notice Topic 8: pin an OApp's send/receive libraries (ULN302) on every path, so a change of the endpoint
/// owner's DEFAULT library (LayerZero Labs in production) can no longer reroute our messages (topic 1 finding).
/// Run before handing ownership to the Safe: afterwards only the Safe (delegate) can do this. Re-runnable.
/// env: TESTNET_PRIVATE_KEY, OAPP (deployments key, default Ping)
contract PinLibrariesTestnet is TestnetBase {
    function run() external {
        string memory local = tnLocal();
        EndpointV2 endpoint = EndpointV2(tnAddr(local, "endpointV2"));
        address oapp = existing(vm.envOr("OAPP", string("Ping")));
        address sendLib = tnAddr(local, "sendUln302");
        address receiveLib = tnAddr(local, "receiveUln302");
        string[] memory chains = tnChains();

        vm.startBroadcast(tnKey());
        for (uint256 i = 0; i < chains.length; i++) {
            if (eq(chains[i], local)) continue;
            uint32 eid = tnEid(chains[i]);
            if (endpoint.isDefaultSendLibrary(oapp, eid)) {
                endpoint.setSendLibrary(oapp, eid, sendLib);
                console.log("  pinned send library   ->", chains[i]);
            } else {
                console.log("  ok     send library   ->", chains[i]);
            }
            (, bool isDefault) = endpoint.getReceiveLibrary(oapp, eid);
            if (isDefault) {
                endpoint.setReceiveLibrary(oapp, eid, receiveLib, 0);
                console.log("  pinned receive library <-", chains[i]);
            } else {
                console.log("  ok     receive library <-", chains[i]);
            }
        }
        vm.stopBroadcast();
    }
}
