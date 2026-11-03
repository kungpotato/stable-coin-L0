// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MockUSDT} from "../src/lab/MockUSDT.sol";

/// @notice Models the Mercado Bitcoin drain (2026-11-02), the OPPOSITE shape to the Binance 14
///         EIP-7702 hack. There is no delegation and no attacker contract: whoever holds the
///         exchange's ONE signing secret can sign plain transfers out of every hot wallet AND
///         every customer deposit address. On-chain it looked like ~36,042 ordinary transfers.
/// @dev The teaching point is the blast radius of a single compromised signing authority when all
///      deposit addresses are derived from one seed (HD wallet) or served by one signing service:
///      one secret = signing power over all of them. The stolen stablecoins can be frozen by the
///      issuer afterwards; the ETH, once parked, cannot.
contract MercadoDepositSweepTest is Test {
    /// @dev ONE seed derives every deposit address's key. Steal it once, sign for all. This is the
    ///      shared-master-key custody model the on-chain pattern points at (unconfirmed publicly).
    bytes32 constant MASTER_SEED = keccak256("mercado-bitcoin-master-seed");
    uint256 constant N = 100; // stands in for the 36,042 deposit addresses, at lab scale

    MockUSDT usdt;
    address issuer = makeAddr("tether");
    address attackerCollector = makeAddr("attackerCollector"); // like 0xe485… (USDT lands here)
    address attackerEthPark = makeAddr("attackerEthPark"); // like 0x59a9… (fresh wallet, ETH parked)

    function _depositKey(uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(MASTER_SEED, i)));
    }

    function _depositAddr(uint256 i) internal returns (address) {
        return vm.addr(_depositKey(i));
    }

    function setUp() public {
        vm.prank(issuer);
        usdt = new MockUSDT();
        for (uint256 i; i < N; i++) {
            address d = _depositAddr(i);
            vm.deal(d, 1 ether);
            usdt.mint(d, 10_000e6);
        }
    }

    /// @dev One stolen seed drains every deposit address with plain transfers — no contract, no
    ///      EIP-7702 code on any victim. Contrast Binance, where the sweep needed delegated code.
    function _drain() internal returns (uint256 totalUsdt, uint256 totalEth) {
        for (uint256 i; i < N; i++) {
            address d = _depositAddr(i);
            assertEq(d.code.length, 0, "victim stays a plain EOA: no delegation needed");
            uint256 u = usdt.balanceOf(d);
            vm.prank(d);
            usdt.transfer(attackerCollector, u);
            totalUsdt += u;
            uint256 e = d.balance;
            vm.prank(d);
            (bool ok,) = attackerEthPark.call{value: e}("");
            require(ok, "eth");
            totalEth += e;
        }
    }

    function test_oneStolenSeedDrainsEveryDepositAddress() public {
        (uint256 u, uint256 e) = _drain();
        assertEq(u, N * 10_000e6, "all USDT swept");
        assertEq(e, N * 1 ether, "all ETH swept");
        assertEq(usdt.balanceOf(attackerCollector), u);
        assertEq(attackerEthPark.balance, e);
        // Every deposit address was and stays a plain EOA — the drain used signatures, not code.
        for (uint256 i; i < N; i++) {
            assertEq(_depositAddr(i).code.length, 0);
        }
    }

    /// @dev Aftermath matching the live chain: the issuer froze the attacker's USDT collector
    ///      (on mainnet 0xe485… holds ~3.05M USDT, isBlackListed=true), but the ETH parked in a
    ///      fresh wallet (0x59a9… held 2,979 ETH, nonce 0) is unfreezable and moves freely.
    function test_issuerFreezesUsdtButNotParkedEth() public {
        _drain();
        address cashout = makeAddr("cashout");

        vm.prank(issuer);
        usdt.addBlackList(attackerCollector);

        vm.prank(attackerCollector);
        vm.expectRevert("USDT: sender frozen");
        usdt.transfer(cashout, 1e6);

        // ETH has no issuer and no blacklist — the parked ETH leaves whenever the attacker wants.
        vm.prank(attackerEthPark);
        (bool ok,) = cashout.call{value: 10 ether}("");
        assertTrue(ok, "parked ETH cannot be frozen");
        assertEq(cashout.balance, 10 ether);
    }
}
