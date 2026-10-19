// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {NativeOFTAdapter} from "@layerzerolabs/oft-evm/contracts/NativeOFTAdapter.sol";
import {InboundMintCap} from "../src/token/InboundMintCap.sol";
import {PotatoOFT} from "../src/token/PotatoOFT.sol";
import {PotatoNativeAdapterHarness, NoReceive} from "./PotatoNativeAdapter.t.sol";

contract PotatoOFTHarness is PotatoOFT {
    constructor(address e, address o) PotatoOFT(e, o) {}
    function credit(address to, uint256 amt, uint32 src) external returns (uint256) {
        return _credit(to, amt, src);
    }
}

/// ADR 0006 on the POTATO legs: a forged inbound message can release (potato) or mint (anvil) at most the cap
/// per window; the excess is held, never reverted, and only the owner pays it out.
contract PotatoInboundCapTest is Test {
    uint32 constant FROM_ANVIL = 40338;
    uint32 constant FROM_POTATO = 40707;
    uint256 constant CAP = 1_000 ether;
    uint64 constant WINDOW = 3600;
    address alice = makeAddr("alice");
    address attacker = makeAddr("attacker");
    PotatoNativeAdapterHarness adapter; // potato: native lockbox
    PotatoOFTHarness oft; // anvil: minted POTATO

    function setUp() public {
        adapter = new PotatoNativeAdapterHarness(address(new EndpointV2(40707, address(this))), address(this));
        oft = new PotatoOFTHarness(address(new EndpointV2(40338, address(this))), address(this));
        vm.deal(address(adapter), 100_000 ether); // POTATO locked by earlier sends
        _setCap(adapter, FROM_ANVIL);
        _setCap(oft, FROM_POTATO);
    }

    function _setCap(InboundMintCap leg, uint32 eid) internal {
        InboundMintCap.InboundCapConfig[] memory cfg = new InboundMintCap.InboundCapConfig[](1);
        cfg[0] = InboundMintCap.InboundCapConfig(eid, CAP, WINDOW);
        leg.setInboundCaps(cfg);
    }

    function test_adapter_releasesUpToCap() public {
        adapter.credit(alice, 600 ether, FROM_ANVIL);
        adapter.credit(alice, 400 ether, FROM_ANVIL); // exactly up to the cap
        assertEq(alice.balance, CAP);
        assertEq(adapter.inboundAvailable(FROM_ANVIL), 0);
    }

    function test_adapter_aboveCapStaysLocked() public {
        uint256 locked = address(adapter).balance;
        adapter.credit(alice, 1_500 ether, FROM_ANVIL); // must not revert: the message would be stranded
        assertEq(alice.balance, 0);
        assertEq(address(adapter).balance, locked); // native never left the lockbox
        assertEq(adapter.quarantined(alice), 1_500 ether);
        assertEq(adapter.totalQuarantined(), 1_500 ether); // check-supply deducts it from locked
        assertEq(adapter.inboundAvailable(FROM_ANVIL), CAP); // held: no cap used
    }

    /// The lockbox drain from the DEMOWEAK drill / Cysic pattern: a forged release, then smaller retries.
    function test_adapter_forgedDrainLimitedToCap() public {
        adapter.credit(attacker, 100_000 ether, FROM_ANVIL); // the whole lockbox
        for (uint256 i = 0; i < 20; i++) adapter.credit(attacker, 100 ether, FROM_ANVIL);
        assertEq(attacker.balance, CAP); // at most one window's cap leaves the lockbox
        assertEq(address(adapter).balance, 100_000 ether - CAP);
    }

    function test_adapter_ownerReleasesNative() public {
        adapter.credit(alice, 1_500 ether, FROM_ANVIL);
        adapter.releaseQuarantined(alice, alice);
        assertEq(alice.balance, 1_500 ether);
        assertEq(adapter.totalQuarantined(), 0);
    }

    function test_adapter_releaseToContractWithoutReceiveReverts() public {
        adapter.credit(alice, 1_500 ether, FROM_ANVIL);
        address sink = address(new NoReceive());
        vm.expectRevert(abi.encodeWithSelector(NativeOFTAdapter.CreditFailed.selector, sink, 1_500 ether, bytes("")));
        adapter.releaseQuarantined(alice, sink);
        assertEq(adapter.quarantined(alice), 1_500 ether); // still held: the owner can pick another payee
        adapter.releaseQuarantined(alice, alice);
        assertEq(alice.balance, 1_500 ether);
    }

    function test_adapter_uncappedPathUnchanged() public {
        adapter.credit(alice, 50_000 ether, 40161); // no cap set for this source
        assertEq(alice.balance, 50_000 ether);
    }

    function test_oft_aboveCapMintsToItself() public {
        oft.credit(alice, 1_000 ether, FROM_POTATO);
        oft.credit(attacker, 10_000_000 ether, FROM_POTATO);
        assertEq(oft.balanceOf(alice), CAP);
        assertEq(oft.balanceOf(attacker), 0);
        assertEq(oft.balanceOf(address(oft)), 10_000_000 ether); // minted but not spendable
        assertEq(oft.quarantined(attacker), 10_000_000 ether);
    }

    function test_oft_ownerReleases() public {
        oft.credit(alice, 2_000 ether, FROM_POTATO);
        oft.releaseQuarantined(alice, alice);
        assertEq(oft.balanceOf(alice), 2_000 ether);
        assertEq(oft.balanceOf(address(oft)), 0);
    }

    function test_onlyOwner() public {
        InboundMintCap.InboundCapConfig[] memory cfg = new InboundMintCap.InboundCapConfig[](0);
        vm.startPrank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        adapter.setInboundCaps(cfg);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        oft.releaseQuarantined(alice, attacker);
        vm.stopPrank();
    }
}
