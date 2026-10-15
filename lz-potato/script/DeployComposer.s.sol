// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {console} from "forge-std/Script.sol";
import {LabBase} from "./LabBase.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UsdcVault} from "../src/compose/UsdcVault.sol";
import {UsdcDepositComposer} from "../src/compose/UsdcDepositComposer.sol";

/// @notice Topic 7: UsdcVault + UsdcDepositComposer next to the USDC OFT leg on the connected chain
/// (potato). Recorded as "UsdcVault" / "UsdcComposer". Re-runnable.
/// env: KEY_<chain>
contract DeployComposer is LabBase {
    function run() external {
        address oft = existing("USDC");
        address endpoint = existing("EndpointV2");
        require(oft != address(0), "deploy the USDC leg first");
        uint256 pk = deployerKey();

        vm.startBroadcast(pk);
        address vault = existing("UsdcVault");
        if (vault == address(0)) {
            vault = address(new UsdcVault(IERC20(oft), vm.addr(pk)));
            save("UsdcVault", vault);
            console.log("deployed UsdcVault", vault);
        }
        address composer = existing("UsdcComposer");
        if (composer == address(0)) {
            composer = address(new UsdcDepositComposer(endpoint, oft, UsdcVault(vault), vm.addr(pk)));
            save("UsdcComposer", composer);
            console.log("deployed UsdcComposer", composer);
        } else {
            console.log("reused   UsdcComposer", composer);
        }
        vm.stopBroadcast();
    }
}
