// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {BridgeControls} from "../src/token/BridgeControls.sol";
import {InboundMintCap} from "../src/token/InboundMintCap.sol";
import {PotatoNativeAdapter} from "../src/token/PotatoNativeAdapter.sol";
import {PotatoOFT} from "../src/token/PotatoOFT.sol";

contract NativeLeg is PotatoNativeAdapter {
    constructor(address e, address o) PotatoNativeAdapter(e, o) {}
    function debit(address from, uint256 amt, uint32 dst) external returns (uint256, uint256) {
        return _debit(from, amt, 0, dst);
    }
    function credit(address to, uint256 amt, uint32 src) external returns (uint256) {
        return _credit(to, amt, src);
    }
}

contract OftLeg is PotatoOFT {
    constructor(address e, address o) PotatoOFT(e, o) {}
    function debit(address from, uint256 amt, uint32 dst) external returns (uint256, uint256) {
        return _debit(from, amt, 0, dst);
    }
    function credit(address to, uint256 amt, uint32 src) external returns (uint256) {
        return _credit(to, amt, src);
    }
}

/// ADR 0007: POTATO legs get the same pause and outbound rate limit as USDC (BridgeControls), without the blacklist.
contract PotatoControlsTest is Test {
    uint32 constant ANVIL = 40338;
    uint32 constant POTATO = 40707;
    uint256 constant LIMIT = 1_000 ether; // per window, matches the inbound cap so legit traffic is never held
    uint64 constant WINDOW = 3600;
    address alice = makeAddr("alice");
    address stranger = makeAddr("stranger");
    NativeLeg adapter; // potato
    OftLeg oft; // anvil

    function setUp() public {
        adapter = new NativeLeg(address(new EndpointV2(POTATO, address(this))), address(this));
        oft = new OftLeg(address(new EndpointV2(ANVIL, address(this))), address(this));
        _setLimit(adapter, ANVIL);
        _setLimit(oft, POTATO);
        vm.deal(address(adapter), 100_000 ether);
        oft.credit(alice, 5_000 ether, POTATO); // alice holds POTATO on anvil (no inbound cap set here)
    }

    function _setLimit(BridgeControls leg, uint32 eid) internal {
        RateLimiter.RateLimitConfig[] memory cfg = new RateLimiter.RateLimitConfig[](1);
        cfg[0] = RateLimiter.RateLimitConfig(eid, uint192(LIMIT), WINDOW);
        leg.setRateLimits(cfg);
    }

    function test_rateLimit_adapterBlocksAboveLimit() public {
        adapter.debit(alice, 600 ether, ANVIL);
        vm.expectRevert(RateLimiter.RateLimitExceeded.selector);
        adapter.debit(alice, 401 ether, ANVIL);
        adapter.debit(alice, 400 ether, ANVIL); // exactly up to the limit
    }

    function test_rateLimit_oftBlocksAboveLimitAndRefills() public {
        oft.debit(alice, LIMIT, POTATO);
        vm.expectRevert(RateLimiter.RateLimitExceeded.selector);
        oft.debit(alice, 1 ether, POTATO);
        vm.warp(block.timestamp + WINDOW / 2);
        oft.debit(alice, LIMIT / 2, POTATO); // half the window refilled half the limit
        assertEq(oft.balanceOf(alice), 5_000 ether - LIMIT - LIMIT / 2);
    }

    function test_rateLimit_unsetPathBlocksEverything() public {
        vm.expectRevert(RateLimiter.RateLimitExceeded.selector);
        oft.debit(alice, 1 ether, 40161); // no limit configured = limit 0: the deploy script must set every path
    }

    function test_rateLimit_inflowGivesQuotaBack() public {
        oft.debit(alice, LIMIT, POTATO);
        oft.credit(alice, 300 ether, POTATO);
        oft.debit(alice, 300 ether, POTATO);
    }

    function test_rateLimit_heldCreditGivesNoQuota() public {
        InboundMintCap.InboundCapConfig[] memory caps = new InboundMintCap.InboundCapConfig[](1);
        caps[0] = InboundMintCap.InboundCapConfig(POTATO, 100 ether, WINDOW);
        oft.setInboundCaps(caps);
        oft.debit(alice, LIMIT, POTATO);
        oft.credit(alice, 500 ether, POTATO); // above the cap: held
        vm.expectRevert(RateLimiter.RateLimitExceeded.selector);
        oft.debit(alice, 1 ether, POTATO);
    }

    /// Full send() on the native leg: the limit reverts the whole tx, so no msg.value stays locked.
    function test_rateLimit_nativeSendRevertsBeforeLocking() public {
        adapter.setPeer(ANVIL, bytes32(uint256(uint160(address(oft)))));
        SendParam memory p = SendParam(ANVIL, bytes32(uint256(uint160(alice))), LIMIT + 1 ether, 0, "", "", "");
        vm.deal(alice, 2_000 ether);
        uint256 locked = address(adapter).balance;
        vm.prank(alice);
        vm.expectRevert(RateLimiter.RateLimitExceeded.selector);
        adapter.send{value: LIMIT + 1 ether}(p, MessagingFee(0, 0), alice);
        assertEq(address(adapter).balance, locked);
        assertEq(alice.balance, 2_000 ether);
    }

    function test_pause_blocksSendAndReceiveOnBothLegs() public {
        adapter.pause();
        oft.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        adapter.debit(alice, 1 ether, ANVIL);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        adapter.credit(alice, 1 ether, ANVIL); // the message waits at the executor, nothing is lost
        vm.expectRevert(Pausable.EnforcedPause.selector);
        oft.debit(alice, 1 ether, POTATO);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        oft.credit(alice, 1 ether, POTATO);
        adapter.unpause();
        oft.unpause();
        adapter.credit(alice, 1 ether, ANVIL); // delivered after unpause
        assertEq(alice.balance, 1 ether);
    }

    function test_noBlacklistOnPotato() public {
        // POTATO is a native coin: no blacklister role, every recipient is paid (within cap and limits)
        oft.credit(stranger, 1 ether, POTATO);
        assertEq(oft.balanceOf(stranger), 1 ether);
    }

    function test_onlyOwner() public {
        RateLimiter.RateLimitConfig[] memory cfg = new RateLimiter.RateLimitConfig[](0);
        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        adapter.pause();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oft.setRateLimits(cfg);
        vm.stopPrank();
    }
}
