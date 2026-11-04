// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MockUSDT} from "../src/lab/MockUSDT.sol";
import {HotWalletVault} from "../src/lab/HotWalletVault.sol";

/// @notice Chapter 19 lab: the after-hack / monitoring layer, built from the two drains we traced.
///         Binance 14 (2026-10-29, EIP-7702) and Mercado Bitcoin (2026-11-02, one stolen seed) both
///         emptied wallets in ~25 minutes. This file models the controls that would have closed the
///         gap between "funds move" and "human reacts":
///           - DETECT: on-chain signals a watcher can flag in real time (7702 delegation, outflow
///             spike, nonce/transfer surge).
///           - CONTAIN: an automatic outflow circuit breaker + a guardian pause (the T+0 switch).
///         The lesson both cases share: stablecoins can be frozen afterwards, ETH cannot — so the
///         only real defence for ETH is to stop it leaving in the first place.
contract HotWalletMonitorTest is Test {
    MockUSDT usdt;
    HotWalletVault vault;

    address issuer = makeAddr("tether");
    address operator = makeAddr("operator"); // the key an attacker steals
    address guardian = makeAddr("guardian"); // incident-response key, separate
    address attacker = makeAddr("attacker");

    uint256 constant VAULT_FUNDS = 1_000_000e6; // 1,000,000 USDT in the hot wallet
    uint256 constant WINDOW = 60;               // 1-minute rolling window
    uint256 constant WINDOW_CAP = 50_000e6;     // at most 50k USDT may leave per minute

    function setUp() public {
        vm.prank(issuer);
        usdt = new MockUSDT();
        vault = new HotWalletVault(usdt, operator, guardian, WINDOW, WINDOW_CAP);
        usdt.mint(address(vault), VAULT_FUNDS);
    }

    // ----------------------------------------------------------------------------------
    // DETECT - pure signals a monitor evaluates per block. No privileged access needed;
    // anyone watching the chain can compute them.
    // ----------------------------------------------------------------------------------

    /// @dev EIP-7702 delegation leaves a 23-byte designator as the account's code:
    ///      0xef0100 ++ 20-byte target. This is the exact Binance 14 signal — a hot EOA that
    ///      suddenly has code is delegated, and the target is the attacker's sweeper.
    function _delegatedTo(address a) internal view returns (bool isDelegated, address target) {
        bytes memory code = a.code;
        if (code.length != 23) return (false, address(0));
        if (!(code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00)) return (false, address(0));
        bytes20 t;
        assembly {
            // code bytes live at add(code,0x20); skip the 3-byte prefix, load the 20-byte address.
            t := mload(add(code, 0x23))
        }
        return (true, address(t));
    }

    function test_detect7702DelegationOnHotWallet() public {
        address hot = makeAddr("binanceHot");
        address sweeper = makeAddr("sweeper");

        // Clean EOA: no code, watcher stays quiet.
        (bool d0,) = _delegatedTo(hot);
        assertFalse(d0, "a bare EOA must not flag");

        // Attacker gets a 7702 auth through: the EOA now carries 0xef0100++sweeper.
        bytes memory designator = abi.encodePacked(hex"ef0100", sweeper);
        vm.etch(hot, designator);

        (bool d1, address target) = _delegatedTo(hot);
        assertTrue(d1, "delegated hot wallet must flag");
        assertEq(target, sweeper, "watcher recovers the sweeper address to alert on");
    }

    /// @dev Outflow-rate signal: sum of withdrawals in a short window vs a baseline threshold.
    ///      Both drains blew past any sane baseline within the first minute.
    function test_detectOutflowSpikeAgainstBaseline() public pure {
        uint256 baselinePerMin = 20_000e6; // normal business outflow
        uint256 observed = 420_000e6;      // what a drain looks like in minute one
        assertGt(observed, baselinePerMin * 3, "3x baseline in a minute = page someone");
    }

    // ----------------------------------------------------------------------------------
    // CONTAIN - the circuit breaker caps the loss automatically, and the guardian pause
    // stops the rest, without waiting for a human.
    // ----------------------------------------------------------------------------------

    /// @dev Stolen operator key tries to drain the whole vault in one window. The breaker lets
    ///      through at most one window's cap, then trips and bounces every further sweep.
    function test_breakerCapsLossToOneWindow() public {
        // Attacker sweeps in 50k chunks. First one fits the 50k cap...
        vm.prank(operator);
        vault.withdraw(attacker, 50_000e6);
        assertEq(usdt.balanceOf(attacker), 50_000e6);

        // ...the second, same minute, pushes past the cap -> breaker latches, nothing transfers.
        vm.prank(operator);
        vault.withdraw(attacker, 50_000e6);

        assertTrue(vault.tripped(), "breaker latched");
        assertEq(usdt.balanceOf(attacker), 50_000e6, "the over-cap sweep sent nothing");

        // Every further attempt bounces while tripped - the rest of the vault is safe.
        vm.prank(operator);
        vm.expectRevert("vault: breaker tripped");
        vault.withdraw(attacker, 1e6);

        assertEq(usdt.balanceOf(attacker), 50_000e6, "attacker got one window, not the vault");
        assertEq(usdt.balanceOf(address(vault)), VAULT_FUNDS - 50_000e6, "95% still in the vault");
    }

    /// @dev Many small transfers (the Mercado shape: thousands of deposit addresses, one tx each)
    ///      still sum against the same window cap - rate limiting does not care about tx count.
    function test_breakerCatchesManySmallDrains() public {
        // 10 x 5k = 50k fits exactly; the 11th trips.
        for (uint256 i; i < 10; i++) {
            vm.prank(operator);
            vault.withdraw(attacker, 5_000e6);
        }
        assertEq(vault.windowOut(), WINDOW_CAP);

        vm.prank(operator);
        vault.withdraw(attacker, 5_000e6); // 11th pushes past the cap -> latches, sends nothing
        assertTrue(vault.tripped());
        assertEq(usdt.balanceOf(attacker), WINDOW_CAP, "only the 50k that fit the cap got out");
    }

    /// @dev The window rolls: legitimate withdrawals resume next minute, so the cap throttles a
    ///      drain without freezing normal business.
    function test_windowRollsForwardForHonestTraffic() public {
        vm.prank(operator);
        vault.withdraw(attacker, 40_000e6);

        // Next minute, a fresh cap applies (and nothing tripped on honest traffic).
        vm.warp(block.timestamp + WINDOW + 1);
        vm.prank(operator);
        vault.withdraw(attacker, 40_000e6);

        assertFalse(vault.tripped());
        assertEq(usdt.balanceOf(attacker), 80_000e6);
    }

    /// @dev T+0 kill switch. The guardian (separate key) pauses; the compromised operator can
    ///      neither withdraw nor un-pause. This is the manual brake for signals the auto cap misses.
    function test_guardianPauseStopsBleedingOperatorCannotUndo() public {
        vm.prank(guardian);
        vault.pause();

        vm.prank(operator);
        vm.expectRevert("vault: paused");
        vault.withdraw(attacker, 1e6);

        // A stolen operator key must NOT be able to lift the pause.
        vm.prank(operator);
        vm.expectRevert("vault: not guardian");
        vault.resume();

        // Only the guardian clears it.
        vm.prank(guardian);
        vault.resume();
        vm.prank(operator);
        vault.withdraw(attacker, 1e6);
        assertEq(usdt.balanceOf(attacker), 1e6);
    }

    /// @dev Aftermath, tying back to chapters 17-18: what DID leak as USDT, the issuer freezes;
    ///      the breaker + freeze together are why the loss is bounded. ETH would not be.
    function test_whatLeaksIsFrozenByIssuer() public {
        vm.prank(operator);
        vault.withdraw(attacker, 50_000e6); // the one window that got out

        vm.prank(issuer);
        usdt.addBlackList(attacker);

        vm.prank(attacker);
        vm.expectRevert("USDT: sender frozen");
        usdt.transfer(makeAddr("cashout"), 1e6);
    }
}
