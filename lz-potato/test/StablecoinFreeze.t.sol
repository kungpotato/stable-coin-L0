// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MockUSDT} from "../src/lab/MockUSDT.sol";
import {MockUSDC, MockUSDCLogic} from "../src/lab/MockUSDC.sol";

/// @notice The "stop-the-bleeding" layer the Binance 14 drain (2026-10-29) actually relied on.
/// @dev The 7702 sweep itself is unstoppable — it lands in one tx. What limited the net loss was
///      the stablecoin ISSUERS freezing the thief's address afterwards. These tests show how that
///      works, why USDT can go one step further (seize/burn), why USDC cannot, why the thief must
///      win a RACE against the freeze, and why ETH can never be frozen at all.
contract StablecoinFreezeTest is Test {
    // Issuers (the only keys that can freeze).
    address tether = makeAddr("tether");
    address circle = makeAddr("circle");
    // The address the drain swept funds into.
    address thief = makeAddr("thief");
    address cashOut = makeAddr("cashOut"); // where the thief tries to move/launder funds

    MockUSDT usdt;
    MockUSDCLogic usdc; // the proxy, cast to its logic ABI

    uint256 constant STOLEN = 1_175_000_000e6; // ~$1.175B, mirrors the real drain size

    function setUp() public {
        vm.prank(tether);
        usdt = new MockUSDT();

        vm.prank(circle);
        usdc = MockUSDCLogic(address(new MockUSDC(circle)));

        // The sweep already happened: stolen stablecoins now sit in the thief's address.
        usdt.mint(thief, STOLEN);
        usdc.mint(thief, STOLEN);
    }

    // --- USDC really is a proxy; USDT really is not -------------------------------------------

    /// @dev ERC1967 implementation slot is non-zero for USDC (logic sits behind a proxy),
    ///      and USDT's own code is not a proxy — its logic is the deployed contract itself.
    function test_usdcSitsBehindAProxy_usdtDoesNot() public view {
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address usdcImpl = address(uint160(uint256(vm.load(address(usdc), implSlot))));
        assertTrue(usdcImpl != address(0), "USDC must have an implementation behind the proxy");
        assertEq(address(uint160(uint256(vm.load(address(usdt), implSlot)))), address(0), "USDT is not a proxy");
        // Both still behave as full ERC20s regardless of the storage layout difference.
        assertEq(usdc.balanceOf(thief), STOLEN);
        assertEq(usdt.balanceOf(thief), STOLEN);
    }

    // --- The freeze: identical victim outcome for USDT and USDC ------------------------------

    function test_usdtFreezeStopsTheThiefMovingFunds() public {
        vm.prank(tether);
        usdt.addBlackList(thief);

        vm.prank(thief);
        vm.expectRevert("USDT: sender frozen");
        usdt.transfer(cashOut, STOLEN);

        // Even receiving is blocked, so the thief cannot park it on a fresh address either.
        usdt.mint(address(this), 1e6);
        vm.expectRevert("USDT: recipient frozen");
        usdt.transfer(thief, 1e6);
    }

    function test_usdcFreezeStopsTheThiefMovingFunds() public {
        vm.prank(circle);
        usdc.blacklist(thief);

        vm.prank(thief);
        vm.expectRevert("USDC: sender frozen");
        usdc.transfer(cashOut, STOLEN);
    }

    function test_onlyIssuerCanFreeze() public {
        vm.prank(thief);
        vm.expectRevert("USDT: not issuer");
        usdt.addBlackList(cashOut);

        vm.prank(thief);
        vm.expectRevert("USDC: not issuer");
        usdc.blacklist(cashOut);
    }

    // --- The one real difference: USDT can seize, USDC can only freeze -----------------------

    function test_usdtCanSeizeAndBurnStolenFunds() public {
        uint256 supplyBefore = usdt.totalSupply();

        vm.startPrank(tether);
        usdt.addBlackList(thief);
        usdt.destroyBlackFunds(thief);
        vm.stopPrank();

        assertEq(usdt.balanceOf(thief), 0, "stolen USDT burned");
        assertEq(usdt.totalSupply(), supplyBefore - STOLEN, "supply reduced by the seized amount");
    }

    /// @dev USDC has no seize function at all — the stolen balance stays put, just frozen.
    function test_usdcCannotSeize_fundsStayFrozenNotDestroyed() public {
        vm.prank(circle);
        usdc.blacklist(thief);

        // There is no destroyBlackFunds on USDC; the balance is still there, immovable.
        assertEq(usdc.balanceOf(thief), STOLEN, "USDC can freeze but not burn");
    }

    // --- Why the thief races, and why they prefer ETH ----------------------------------------

    /// @dev If the thief moves funds out BEFORE the issuer freezes, the freeze is too late.
    ///      This is the race the Binance thief was running.
    function test_thiefWinsIfTheyMoveBeforeTheFreeze() public {
        vm.prank(thief);
        usdt.transfer(cashOut, STOLEN); // succeeds — not frozen yet

        // Issuer reacts a block later, but the funds already left the watched address.
        vm.prank(tether);
        usdt.addBlackList(thief);

        assertEq(usdt.balanceOf(thief), 0);
        assertEq(usdt.balanceOf(cashOut), STOLEN, "already gone before the freeze landed");
    }

    /// @dev The full Tether recovery: freeze -> seize (burn) -> issue replacement -> hand to victim.
    ///      Supply ends unchanged and the victim is made whole — impossible for burned ETH.
    function test_usdtBurnAndRemintReturnsFundsToVictim() public {
        address victim = makeAddr("victim");
        uint256 supplyBefore = usdt.totalSupply();

        vm.startPrank(tether);
        usdt.addBlackList(thief);
        usdt.destroyBlackFunds(thief);          // stolen tokens burned, supply drops
        assertEq(usdt.totalSupply(), supplyBefore - STOLEN);

        usdt.issue(STOLEN);                      // mint replacement to the issuer treasury
        usdt.transfer(victim, STOLEN);           // ...then send it to the verified victim
        vm.stopPrank();

        assertEq(usdt.balanceOf(victim), STOLEN, "victim made whole");
        assertEq(usdt.totalSupply(), supplyBefore, "net supply unchanged after burn+remint");
    }

    function test_onlyIssuerCanIssue() public {
        vm.prank(thief);
        vm.expectRevert("USDT: not issuer");
        usdt.issue(STOLEN);
    }

    /// @dev ETH has no issuer and no blacklist. Once the thief holds ETH, nobody can freeze it —
    ///      which is exactly why a drain swaps stablecoins to ETH as fast as possible.
    function test_ethCannotBeFrozenByAnyone() public {
        vm.deal(thief, 100 ether);
        vm.prank(thief);
        (bool ok,) = cashOut.call{value: 100 ether}("");
        assertTrue(ok, "no one can stop a plain ETH transfer");
        assertEq(cashOut.balance, 100 ether);
    }
}
