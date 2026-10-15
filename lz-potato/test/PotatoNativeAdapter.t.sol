// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {NativeOFTAdapter} from "@layerzerolabs/oft-evm/contracts/NativeOFTAdapter.sol";
import {PotatoNativeAdapter} from "../src/token/PotatoNativeAdapter.sol";

contract PotatoNativeAdapterHarness is PotatoNativeAdapter {
    constructor(address e, address o) PotatoNativeAdapter(e, o) {}
    function credit(address to, uint256 amt, uint32 src) external returns (uint256) {
        return _credit(to, amt, src);
    }
}

/// A contract with no receive()/fallback: cannot accept native POTATO.
contract NoReceive {}

/// Topic 13.8: what happens when POTATO comes home to a recipient that can't take native coin (ADR 0002).
contract PotatoNativeAdapterTest is Test {
    PotatoNativeAdapterHarness adapter;

    function setUp() public {
        adapter = new PotatoNativeAdapterHarness(address(new EndpointV2(40707, address(this))), address(this));
        vm.deal(address(adapter), 10 ether); // POTATO locked by earlier sends
    }

    function test_credit_paysNativeToEOA() public {
        address alice = makeAddr("alice");
        adapter.credit(alice, 1 ether, 40338);
        assertEq(alice.balance, 1 ether);
        assertEq(address(adapter).balance, 9 ether);
    }

    function test_credit_revertsForContractWithoutReceive() public {
        address sink = address(new NoReceive());
        vm.expectRevert(abi.encodeWithSelector(NativeOFTAdapter.CreditFailed.selector, sink, 1 ether, bytes("")));
        adapter.credit(sink, 1 ether, 40338);
        // nothing moved: the lzReceive that carries this credit reverts, so the message stays undelivered
        assertEq(address(adapter).balance, 10 ether);
    }
}
