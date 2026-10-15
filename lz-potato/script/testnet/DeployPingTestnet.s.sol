// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {TestnetBase} from "./TestnetBase.s.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {PingOApp} from "../../src/lab/PingOApp.sol";

/// @notice Topic 4: our PingOApp on a public testnet, on LayerZero's official endpoint. Peers the other testnet
/// and, unlike the network default (1 DVN), requires LayerZero Labs + Nethermind on both directions, with the
/// default confirmations of the sending chain. Run on both chains, then once more on the first. Re-runnable.
/// Broadcast with --skip-simulation: Sepolia runs Glamsterdam (EIP-8037 state-creation repricing) and forge simulates
/// with this project's evm_version (Prague, for potato), so its own gas estimate is ~7x too low (deploy: 1.47M
/// simulated vs 11.39M real) and the deploy runs out of gas. --skip-simulation uses the node's eth_estimateGas.
/// env: TESTNET_PRIVATE_KEY
contract DeployPingTestnet is TestnetBase {
    uint32 constant CONFIG_TYPE_ULN = 2;

    function run() external {
        string memory local = tnLocal();
        address endpoint = tnAddr(local, "endpointV2");
        uint256 pk = tnKey();

        vm.startBroadcast(pk);
        PingOApp ping = PingOApp(existing("Ping"));
        if (address(ping) == address(0)) {
            ping = new PingOApp(endpoint, vm.addr(pk));
            save("Ping", address(ping));
            console.log("deployed Ping", address(ping));
        } else {
            console.log("reused   Ping", address(ping));
        }

        string[] memory chains = tnChains();
        for (uint256 i = 0; i < chains.length; i++) {
            if (eq(chains[i], local)) continue;
            uint32 remoteEid = tnEid(chains[i]);
            address remote = recorded(tnChainId(chains[i]), "Ping");
            if (remote == address(0)) {
                console.log("  peer", chains[i], "pending");
            } else if (ping.peers(remoteEid) != bytes32(uint256(uint160(remote)))) {
                ping.setPeer(remoteEid, bytes32(uint256(uint160(remote))));
                console.log("  set  peer", chains[i], remote);
            }
            // lzReceive gas the remote chain really needs (measured in topic 4, +40%); paid by the sender
            uint128 gas = uint128(vm.parseJsonUint(tn(), string.concat(".chains.", tnPath(chains[i]), ".pingReceiveGas")));
            if (ping.receiveGas(remoteEid) != gas) {
                ping.setReceiveGas(remoteEid, gas);
                console.log("  set  lzReceive gas for", chains[i], gas);
            }
            // send waits for OUR chain's confirmations, receive for the remote chain's (keep LayerZero's defaults)
            _uln(EndpointV2(endpoint), address(ping), tnAddr(local, "sendUln302"), remoteEid, _confirmations(local), local, "send   ");
            _uln(EndpointV2(endpoint), address(ping), tnAddr(local, "receiveUln302"), remoteEid, _confirmations(chains[i]), local, "receive");
        }
        vm.stopBroadcast();
    }

    function _confirmations(string memory chain) internal view returns (uint64) {
        string memory field = eq(chain, "sepolia") ? "defaultToArbSepolia" : "defaultToSepolia";
        return uint64(vm.parseJsonUint(tn(), string.concat(".chains.", tnPath(chain), ".", field, ".confirmations")));
    }

    function _uln(EndpointV2 endpoint, address oapp, address lib, uint32 eid, uint64 conf, string memory local, string memory side) internal {
        address a = tnAddr(local, "dvns.layerzero-labs");
        address b = tnAddr(local, "dvns.nethermind");
        address[] memory dvns = new address[](2);
        (dvns[0], dvns[1]) = a < b ? (a, b) : (b, a); // ULN wants them sorted
        bytes memory cfg = abi.encode(UlnConfig(conf, 2, 0, 0, dvns, new address[](0)));
        if (keccak256(endpoint.getConfig(oapp, lib, eid, CONFIG_TYPE_ULN)) == keccak256(cfg)) {
            console.log("  ok  ", side, "DVNs: LayerZero Labs + Nethermind");
            return;
        }
        SetConfigParam[] memory p = new SetConfigParam[](1);
        p[0] = SetConfigParam(eid, CONFIG_TYPE_ULN, cfg);
        endpoint.setConfig(oapp, lib, p);
        console.log("  set ", side, "DVNs: LayerZero Labs + Nethermind");
    }
}
