// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {TestnetBase} from "./TestnetBase.s.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {ReadLibConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/readlib/ReadLibBase.sol";
import {CrossChainReader} from "../../src/read/CrossChainReader.sol";

/// @notice Topic 7: CrossChainReader on the connected testnet, read channel on, and a read config requiring two
/// read DVNs (LayerZero Labs + Horizen) instead of the network default of one. Re-runnable.
/// Broadcast with --skip-simulation (Glamsterdam gas, see DeployPingTestnet).
/// env: TESTNET_PRIVATE_KEY
contract DeployReaderTestnet is TestnetBase {
    uint32 constant CONFIG_TYPE_READ = 1; // ReadLib1002 CONFIG_TYPE_READ_LID_CONFIG

    function run() external {
        string memory local = tnLocal();
        address endpoint = tnAddr(local, "endpointV2");
        uint256 pk = tnKey();
        vm.startBroadcast(pk);

        CrossChainReader reader = CrossChainReader(existing("Reader"));
        if (address(reader) == address(0)) {
            reader = new CrossChainReader(endpoint, vm.addr(pk));
            save("Reader", address(reader));
            console.log("deployed Reader", address(reader));
        } else {
            console.log("reused   Reader", address(reader));
        }

        uint32 channel = reader.READ_CHANNEL();
        if (reader.peers(channel) != bytes32(uint256(uint160(address(reader))))) {
            reader.setReadChannel(channel, true); // the read channel's "peer" is the reader itself
            console.log("  set  read channel", channel);
        }

        address a = tnAddr(local, "readDvns.layerzero-labs");
        address b = tnAddr(local, "readDvns.horizen");
        address[] memory dvns = new address[](2);
        (dvns[0], dvns[1]) = a < b ? (a, b) : (b, a);
        bytes memory cfg = abi.encode(ReadLibConfig(tnAddr(local, "executor"), 2, 0, 0, dvns, new address[](0)));
        address readLib = tnAddr(local, "readLib1002");
        if (keccak256(EndpointV2(endpoint).getConfig(address(reader), readLib, channel, CONFIG_TYPE_READ)) == keccak256(cfg)) {
            console.log("  ok   read DVNs: LayerZero Labs + Horizen");
        } else {
            SetConfigParam[] memory p = new SetConfigParam[](1);
            p[0] = SetConfigParam(channel, CONFIG_TYPE_READ, cfg);
            EndpointV2(endpoint).setConfig(address(reader), readLib, p);
            console.log("  set  read DVNs: LayerZero Labs + Horizen");
        }
        vm.stopBroadcast();
    }
}
