// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import {IssuerUSDC} from "../src/token/IssuerUSDC.sol";
import {UsdcAdapter} from "../src/token/UsdcAdapter.sol";
import {UsdcOFT} from "../src/token/UsdcOFT.sol";

/// @notice Topic 14: USDC bridge leg on the connected chain (ADR 0003). On the home chain
/// (.assets.USDC.home) IssuerUSDC + UsdcAdapter, elsewhere UsdcOFT, recorded as "USDC" (and "IssuerUSDC").
/// Peers, enforced lzReceive gas and the lab rate limit for every other chain. Run on every chain, then once
/// more on the first (peers need the remote address). Re-runnable.
/// env: KEY_<chain>
contract DeployUsdcBridge is LabBase {
    using OptionsBuilder for bytes;

    uint128 constant LZ_RECEIVE_GAS = 100_000;
    uint192 constant RATE_LIMIT = 10_000e6; // per window, per destination (ADR 0003)
    uint64 constant RATE_WINDOW = 60;

    function run() external {
        string memory local = localName();
        bool isHome = _eq(vm.parseJsonString(topology(), ".assets.USDC.home"), local);
        address endpoint = existing("EndpointV2");
        require(endpoint != address(0), "run DeployProtocol first");
        uint256 pk = deployerKey();
        address owner = vm.addr(pk);

        vm.startBroadcast(pk);
        UsdcOFT leg = UsdcOFT(existing("USDC")); // same owner/peer/limit API on both leg types
        if (address(leg) == address(0)) {
            if (isHome) {
                address token = existing("IssuerUSDC");
                if (token == address(0)) {
                    token = address(new IssuerUSDC(owner));
                    save("IssuerUSDC", token);
                    console.log("deployed IssuerUSDC", token);
                }
                leg = UsdcOFT(address(new UsdcAdapter(token, endpoint, owner)));
                console.log("deployed UsdcAdapter", address(leg));
            } else {
                leg = new UsdcOFT(endpoint, owner);
                console.log("deployed UsdcOFT", address(leg));
            }
            save("USDC", address(leg));
        } else {
            console.log("reused   USDC leg", address(leg));
        }

        bytes memory opts = OptionsBuilder.newOptions().addExecutorLzReceiveOption(LZ_RECEIVE_GAS, 0);
        string[] memory names = chainNames();
        for (uint256 i = 0; i < names.length; i++) {
            if (_eq(names[i], local)) continue;
            uint32 remoteEid = eidOf(names[i]);
            _peer(leg, names[i], remoteEid);

            if (keccak256(leg.enforcedOptions(remoteEid, 1)) == keccak256(opts)
                && keccak256(leg.enforcedOptions(remoteEid, 2)) == keccak256(opts)) {
                console.log("  ok   enforced options", names[i]);
            } else {
                EnforcedOptionParam[] memory p = new EnforcedOptionParam[](2);
                p[0] = EnforcedOptionParam(remoteEid, 1, opts);
                p[1] = EnforcedOptionParam(remoteEid, 2, opts);
                leg.setEnforcedOptions(p);
                console.log("  set  enforced options", names[i]);
            }

            (,, uint192 limit, uint64 window) = leg.rateLimits(remoteEid);
            if (limit == RATE_LIMIT && window == RATE_WINDOW) {
                console.log("  ok   rate limit", names[i]);
            } else {
                RateLimiter.RateLimitConfig[] memory cfg = new RateLimiter.RateLimitConfig[](1);
                cfg[0] = RateLimiter.RateLimitConfig(remoteEid, RATE_LIMIT, RATE_WINDOW);
                leg.setRateLimits(cfg);
                console.log("  set  rate limit", names[i]);
            }
        }
        vm.stopBroadcast();
    }

    function _peer(UsdcOFT leg, string memory remoteName, uint32 remoteEid) internal {
        address remote = recorded(chainUint(remoteName, "chainId"), "USDC");
        if (remote == address(0)) {
            console.log("  peer", remoteName, "pending: no USDC leg recorded there yet");
        } else if (leg.peers(remoteEid) == bytes32(uint256(uint160(remote)))) {
            console.log("  ok   peer", remoteName, remote);
        } else {
            leg.setPeer(remoteEid, bytes32(uint256(uint160(remote))));
            console.log("  set  peer", remoteName, remote);
        }
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
