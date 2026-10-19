// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {OFTCore} from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import {PotatoNativeAdapter} from "../src/token/PotatoNativeAdapter.sol";
import {PotatoOFT} from "../src/token/PotatoOFT.sol";
import {InboundMintCap} from "../src/token/InboundMintCap.sol";
import {BridgeControls} from "../src/token/BridgeControls.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";

/// @notice Topic 13: POTATO bridge leg on the connected chain (ADR 0002). On the asset's home chain
/// (config/topology.json .assets.POTATO.home) a PotatoNativeAdapter, elsewhere a PotatoOFT, recorded as
/// "POTATO". Peers every other recorded leg and enforces lzReceive gas for SEND / SEND_AND_CALL.
/// With INBOUND_CAP=true (legs from v2 on, ADR 0006) also the inbound mint cap per source chain; with
/// CONTROLS=true (legs from v3 on, ADR 0007) also the outbound rate limit, without which the leg cannot send.
/// Run on every chain, then once more on the first (peers need the remote address). Re-runnable.
/// env: KEY_<chain>, INBOUND_CAP (optional bool; v1 has no cap), CONTROLS (optional bool; v1/v2 have no rate limit)
contract DeployPotatoBridge is LabBase {
    using OptionsBuilder for bytes;

    string constant KEY = "POTATO";
    uint128 constant LZ_RECEIVE_GAS = 100_000;
    uint256 constant INBOUND_LIMIT = 1_000 ether; // POTATO per window, per source chain (ADR 0006)
    uint64 constant INBOUND_WINDOW = 3600;
    // outbound = the remote's inbound cap: legit traffic within the limit is never held on the other side (ADR 0007)
    uint192 constant RATE_LIMIT = 1_000 ether;
    uint64 constant RATE_WINDOW = 3600;

    function run() external {
        string memory local = localName();
        bool isHome = _eq(vm.parseJsonString(topology(), ".assets.POTATO.home"), local);
        address endpoint = existing("EndpointV2");
        require(endpoint != address(0), "run DeployProtocol first");
        uint256 pk = deployerKey();

        vm.startBroadcast(pk);
        OFTCore leg = OFTCore(existing(KEY));
        if (address(leg) == address(0)) {
            leg = isHome
                ? OFTCore(address(new PotatoNativeAdapter(endpoint, vm.addr(pk))))
                : OFTCore(address(new PotatoOFT(endpoint, vm.addr(pk))));
            save(KEY, address(leg));
            console.log(isHome ? "deployed PotatoNativeAdapter" : "deployed PotatoOFT", address(leg));
        } else {
            console.log("reused  ", KEY, address(leg));
        }

        bytes memory opts = OptionsBuilder.newOptions().addExecutorLzReceiveOption(LZ_RECEIVE_GAS, 0);
        string[] memory names = chainNames();
        for (uint256 i = 0; i < names.length; i++) {
            if (_eq(names[i], local)) continue;
            uint32 remoteEid = eidOf(names[i]);
            address remote = recorded(chainUint(names[i], "chainId"), KEY);
            if (remote == address(0)) {
                console.log("  peer", names[i], "pending: no POTATO leg recorded there yet");
            } else if (leg.peers(remoteEid) == bytes32(uint256(uint160(remote)))) {
                console.log("  ok   peer", names[i], remote);
            } else {
                leg.setPeer(remoteEid, bytes32(uint256(uint160(remote))));
                console.log("  set  peer", names[i], remote);
            }

            if (keccak256(leg.enforcedOptions(remoteEid, 1)) == keccak256(opts)
                && keccak256(leg.enforcedOptions(remoteEid, 2)) == keccak256(opts)) {
                console.log("  ok   enforced options", names[i]);
            } else {
                EnforcedOptionParam[] memory p = new EnforcedOptionParam[](2);
                p[0] = EnforcedOptionParam(remoteEid, 1, opts); // SEND
                p[1] = EnforcedOptionParam(remoteEid, 2, opts); // SEND_AND_CALL
                leg.setEnforcedOptions(p);
                console.log("  set  enforced options", names[i]);
            }

            if (vm.envOr("CONTROLS", false)) {
                BridgeControls controlled = BridgeControls(address(leg));
                (,, uint192 limit, uint64 window) = controlled.rateLimits(remoteEid);
                if (limit == RATE_LIMIT && window == RATE_WINDOW) {
                    console.log("  ok   rate limit", names[i]);
                } else {
                    RateLimiter.RateLimitConfig[] memory rl = new RateLimiter.RateLimitConfig[](1);
                    rl[0] = RateLimiter.RateLimitConfig(remoteEid, RATE_LIMIT, RATE_WINDOW);
                    controlled.setRateLimits(rl);
                    console.log("  set  rate limit", names[i]);
                }
            }

            if (vm.envOr("INBOUND_CAP", false)) {
                InboundMintCap capped = InboundMintCap(address(leg));
                (uint256 capLimit, uint64 capWindow,,) = capped.inboundCaps(remoteEid);
                if (capLimit == INBOUND_LIMIT && capWindow == INBOUND_WINDOW) {
                    console.log("  ok   inbound cap", names[i]);
                } else {
                    InboundMintCap.InboundCapConfig[] memory caps = new InboundMintCap.InboundCapConfig[](1);
                    caps[0] = InboundMintCap.InboundCapConfig(remoteEid, INBOUND_LIMIT, INBOUND_WINDOW);
                    capped.setInboundCaps(caps);
                    console.log("  set  inbound cap", names[i]);
                }
            }
        }
        vm.stopBroadcast();
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
