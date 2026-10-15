// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {OFTCore} from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import {DemoToken, DemoAdapter, DemoOFT} from "../src/demo/DemoToken.sol";

/// @notice Topic 3: a demo bridge asset (DemoToken + DemoAdapter on its home, DemoOFT elsewhere), recorded as
/// "<ASSET>" and "<ASSET>Token". Same two-pass wiring as the other bridges. Re-runnable.
/// env: KEY_<chain>, ASSET (a key of .assets in config/topology.json, e.g. DEMOWEAK or DEMOSAFE)
contract DeployDemo is LabBase {
    using OptionsBuilder for bytes;

    function run() external {
        string memory asset = vm.envString("ASSET");
        string memory local = localName();
        bool isHome = _eq(vm.parseJsonString(topology(), string.concat(".assets.", asset, ".home")), local);
        address endpoint = existing("EndpointV2");
        uint256 pk = deployerKey();
        address owner = vm.addr(pk);

        vm.startBroadcast(pk);
        OFTCore leg = OFTCore(existing(asset));
        if (address(leg) == address(0)) {
            if (isHome) {
                // a redeployed leg (incident recovery) keeps wrapping the same home token
                address token = existing(string.concat(asset, "Token"));
                if (token == address(0)) {
                    token = address(new DemoToken(asset, owner));
                    save(string.concat(asset, "Token"), token);
                }
                leg = OFTCore(address(new DemoAdapter(token, endpoint, owner)));
            } else {
                leg = OFTCore(address(new DemoOFT(asset, endpoint, owner)));
            }
            save(asset, address(leg));
            console.log("deployed", asset, isHome ? "adapter" : "OFT", address(leg));
        } else {
            console.log("reused  ", asset, address(leg));
        }

        bytes memory opts = OptionsBuilder.newOptions().addExecutorLzReceiveOption(100_000, 0);
        string[] memory names = chainNames();
        for (uint256 i = 0; i < names.length; i++) {
            if (_eq(names[i], local)) continue;
            uint32 eid = eidOf(names[i]);
            address remote = recorded(chainUint(names[i], "chainId"), asset);
            if (remote == address(0)) {
                console.log("  peer", names[i], "pending");
            } else if (leg.peers(eid) != bytes32(uint256(uint160(remote)))) {
                leg.setPeer(eid, bytes32(uint256(uint160(remote))));
                console.log("  set  peer", names[i]);
            }
            if (keccak256(leg.enforcedOptions(eid, 1)) != keccak256(opts)) {
                EnforcedOptionParam[] memory p = new EnforcedOptionParam[](2);
                p[0] = EnforcedOptionParam(eid, 1, opts);
                p[1] = EnforcedOptionParam(eid, 2, opts);
                leg.setEnforcedOptions(p);
                console.log("  set  enforced options", names[i]);
            }
        }
        vm.stopBroadcast();
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
