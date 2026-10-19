// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import {IssuerUSDC} from "../src/token/IssuerUSDC.sol";
import {StablecoinControls} from "../src/token/StablecoinControls.sol";
import {UsdcOFTHarness, UsdcAdapterHarness} from "./UsdcControls.t.sol";

/// ADR 0006: inbound mint cap. A forged inbound message (compromised verifier, as in the DEMOWEAK drill or the
/// Cysic incident) must not be able to mint more than the cap per window; the excess is held, never reverted.
contract InboundCapTest is Test {
    uint32 constant SRC = 40338;
    uint32 constant OTHER = 40161;
    uint256 constant CAP = 10_000e6;
    uint64 constant WINDOW = 3600;
    address user = makeAddr("user");
    address attacker = makeAddr("attacker");
    address stranger = makeAddr("stranger");
    UsdcOFTHarness oft;
    UsdcAdapterHarness adapter;
    IssuerUSDC usdc;

    function setUp() public {
        EndpointV2 endpoint = new EndpointV2(40707, address(this));
        oft = new UsdcOFTHarness(address(endpoint), address(this));
        usdc = new IssuerUSDC(address(this));
        adapter = new UsdcAdapterHarness(address(usdc), address(endpoint), address(this));
        _setCap(StablecoinControls(oft), SRC, CAP, WINDOW);
    }

    function _setCap(StablecoinControls leg, uint32 eid, uint256 limit, uint64 window) internal {
        StablecoinControls.InboundCapConfig[] memory cfg = new StablecoinControls.InboundCapConfig[](1);
        cfg[0] = StablecoinControls.InboundCapConfig(eid, limit, window);
        leg.setInboundCaps(cfg);
    }

    function test_uncappedPathIsUnchanged() public {
        assertEq(oft.inboundAvailable(OTHER), type(uint256).max);
        oft.credit(user, 1_000_000e6, OTHER);
        assertEq(oft.balanceOf(user), 1_000_000e6);
        assertEq(oft.totalQuarantined(), 0);
    }

    function test_creditUpToCapIsPaid() public {
        oft.credit(user, 6_000e6, SRC);
        oft.credit(user, 4_000e6, SRC); // exactly up to the cap
        assertEq(oft.balanceOf(user), CAP);
        assertEq(oft.inboundAvailable(SRC), 0);
        assertEq(oft.totalQuarantined(), 0);
    }

    function test_aboveCapHoldsWholeMessage() public {
        oft.credit(user, 6_000e6, SRC);
        vm.expectEmit(address(oft));
        emit StablecoinControls.InboundCapExceeded(user, SRC, 5_000e6, 4_000e6);
        oft.credit(user, 5_000e6, SRC); // must not revert: a reverting lzReceive would strand the message
        assertEq(oft.balanceOf(user), 6_000e6); // nothing of it paid, not even the 4,000 that would fit
        assertEq(oft.quarantined(user), 5_000e6);
        assertEq(oft.balanceOf(address(oft)), 5_000e6); // minted to the leg: backed on the home chain, not spendable
        assertEq(oft.inboundAvailable(SRC), 4_000e6); // a held message does not use the cap
    }

    function test_capRefillsLinearly() public {
        oft.credit(user, CAP, SRC);
        vm.warp(block.timestamp + WINDOW / 4);
        assertEq(oft.inboundAvailable(SRC), CAP / 4);
        vm.warp(block.timestamp + WINDOW);
        assertEq(oft.inboundAvailable(SRC), CAP);
        oft.credit(user, CAP, SRC);
        assertEq(oft.balanceOf(user), 2 * CAP);
    }

    /// The Cysic pattern: a forged 10M mint, and the same attacker retrying in smaller pieces.
    function test_forgedMintIsLimitedToCap() public {
        oft.credit(attacker, 10_000_000e6, SRC);
        assertEq(oft.balanceOf(attacker), 0);
        for (uint256 i = 0; i < 20; i++) oft.credit(attacker, 1_000e6, SRC); // 20,000 in pieces
        assertEq(oft.balanceOf(attacker), CAP); // at most one window's cap reaches the attacker
        assertEq(oft.quarantined(attacker), 10_000_000e6 + 10_000e6);
    }

    function test_ownerReleasesHeldAfterReview() public {
        oft.credit(user, 15_000e6, SRC);
        oft.releaseQuarantined(user, user); // legit large transfer: owner pays it out after review
        assertEq(oft.balanceOf(user), 15_000e6);
        assertEq(oft.totalQuarantined(), 0);
        assertEq(oft.inboundAvailable(SRC), CAP); // a release is outside the cap
    }

    function test_heldCreditGivesNoOutboundQuota() public {
        RateLimiter.RateLimitConfig[] memory rl = new RateLimiter.RateLimitConfig[](1);
        rl[0] = RateLimiter.RateLimitConfig(SRC, uint192(CAP), WINDOW);
        oft.setRateLimits(rl);
        oft.credit(user, 20_000e6, OTHER); // uncapped path: user has funds
        oft.debit(user, CAP, SRC); // outbound quota to SRC used up
        oft.credit(user, 50_000e6, SRC); // held
        vm.expectRevert(RateLimiter.RateLimitExceeded.selector);
        oft.debit(user, 1e6, SRC); // a forged, held message must not refill outbound quota
    }

    function test_adapterHoldsTokensAboveCap() public {
        _setCap(StablecoinControls(adapter), SRC, CAP, WINDOW);
        RateLimiter.RateLimitConfig[] memory rl = new RateLimiter.RateLimitConfig[](1);
        rl[0] = RateLimiter.RateLimitConfig(SRC, uint192(100_000e6), WINDOW); // outbound: unset means 0
        adapter.setRateLimits(rl);
        usdc.mint(user, 50_000e6);
        vm.prank(user);
        usdc.approve(address(adapter), type(uint256).max);
        adapter.debit(user, 30_000e6, SRC); // lock first, so there is something to release
        adapter.credit(attacker, 25_000e6, SRC);
        assertEq(usdc.balanceOf(attacker), 0);
        assertEq(usdc.balanceOf(address(adapter)), 30_000e6); // stays locked
        assertEq(adapter.totalQuarantined(), 25_000e6); // check-supply deducts it from locked
    }

    function test_zeroLimitHoldsEverything_zeroWindowRemovesCap() public {
        _setCap(StablecoinControls(oft), SRC, 0, WINDOW);
        oft.credit(user, 1, SRC);
        assertEq(oft.quarantined(user), 1);
        _setCap(StablecoinControls(oft), SRC, 0, 0);
        assertEq(oft.inboundAvailable(SRC), type(uint256).max);
        oft.credit(user, 1, SRC);
        assertEq(oft.balanceOf(user), 1);
    }

    function test_changingCapKeepsUsage() public {
        oft.credit(user, 8_000e6, SRC);
        _setCap(StablecoinControls(oft), SRC, 20_000e6, WINDOW); // raise the cap mid-window
        assertEq(oft.inboundAvailable(SRC), 12_000e6);
    }

    function test_blacklistStillWinsOverCap() public {
        address blacklister = makeAddr("blacklister");
        oft.setBlacklister(blacklister);
        vm.prank(blacklister);
        oft.blacklist(attacker);
        oft.credit(attacker, 1_000e6, SRC);
        assertEq(oft.quarantined(attacker), 1_000e6);
        assertEq(oft.inboundAvailable(SRC), CAP); // held: no cap used
    }

    function test_onlyOwnerSetsCaps() public {
        StablecoinControls.InboundCapConfig[] memory cfg = new StablecoinControls.InboundCapConfig[](0);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oft.setInboundCaps(cfg);
    }
}
