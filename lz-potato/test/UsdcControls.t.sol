// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import {IssuerUSDC} from "../src/token/IssuerUSDC.sol";
import {UsdcAdapter} from "../src/token/UsdcAdapter.sol";
import {UsdcOFT} from "../src/token/UsdcOFT.sol";
import {StablecoinControls} from "../src/token/StablecoinControls.sol";

/// Exposes the internal debit/credit hooks so the controls can be tested without a full pathway.
contract UsdcOFTHarness is UsdcOFT {
    constructor(address e, address o) UsdcOFT(e, o) {}
    function debit(address from, uint256 amt, uint32 dst) external returns (uint256, uint256) {
        return _debit(from, amt, 0, dst);
    }
    function credit(address to, uint256 amt, uint32 src) external returns (uint256) {
        return _credit(to, amt, src);
    }
}

contract UsdcAdapterHarness is UsdcAdapter {
    constructor(address t, address e, address o) UsdcAdapter(t, e, o) {}
    function debit(address from, uint256 amt, uint32 dst) external returns (uint256, uint256) {
        return _debit(from, amt, 0, dst);
    }
    function credit(address to, uint256 amt, uint32 src) external returns (uint256) {
        return _credit(to, amt, src);
    }
}

contract UsdcControlsTest is Test {
    uint32 constant DST = 40338;
    uint256 constant LIMIT = 10_000e6; // ADR 0003 lab limit
    uint64 constant WINDOW = 60;
    address user = makeAddr("user");
    address stranger = makeAddr("stranger");
    UsdcOFTHarness oft;
    UsdcAdapterHarness adapter;
    IssuerUSDC usdc;

    function setUp() public {
        EndpointV2 endpoint = new EndpointV2(40707, address(this));
        oft = new UsdcOFTHarness(address(endpoint), address(this));
        usdc = new IssuerUSDC(address(this));
        adapter = new UsdcAdapterHarness(address(usdc), address(endpoint), address(this));
        RateLimiter.RateLimitConfig[] memory cfg = new RateLimiter.RateLimitConfig[](1);
        cfg[0] = RateLimiter.RateLimitConfig(DST, uint192(LIMIT), WINDOW);
        oft.setRateLimits(cfg);
        adapter.setRateLimits(cfg);
        oft.credit(user, 50_000e6, DST); // user holds bridged USDC
        usdc.mint(user, 50_000e6);
        vm.prank(user);
        usdc.approve(address(adapter), type(uint256).max);
        oft.setBlacklister(blacklister);
        adapter.setBlacklister(blacklister);
    }

    address blacklister = makeAddr("blacklister");
    address bad = makeAddr("sanctioned");

    function _blacklist(StablecoinControls leg, address who) internal {
        vm.prank(blacklister);
        leg.blacklist(who);
    }

    function test_blacklist_onlyBlacklister() public {
        vm.expectRevert(abi.encodeWithSelector(StablecoinControls.NotBlacklister.selector, address(this)));
        oft.blacklist(bad); // not even the owner
        _blacklist(oft, bad);
        assertTrue(oft.isBlacklisted(bad));
    }

    function test_blacklist_blocksTransfersBothWays() public {
        oft.credit(bad, 1_000e6, DST);
        _blacklist(oft, bad);
        vm.prank(bad);
        vm.expectRevert(abi.encodeWithSelector(StablecoinControls.AccountBlacklisted.selector, bad));
        oft.transfer(user, 1e6);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(StablecoinControls.AccountBlacklisted.selector, bad));
        oft.transfer(bad, 1e6);
    }

    function test_blacklist_blocksBridgingOut() public {
        oft.credit(bad, 1_000e6, DST);
        _blacklist(oft, bad);
        vm.expectRevert(abi.encodeWithSelector(StablecoinControls.AccountBlacklisted.selector, bad));
        oft.debit(bad, 1e6, DST);
        usdc.mint(bad, 1_000e6);
        vm.prank(bad);
        usdc.approve(address(adapter), type(uint256).max);
        _blacklist(adapter, bad);
        vm.expectRevert(abi.encodeWithSelector(StablecoinControls.AccountBlacklisted.selector, bad));
        adapter.debit(bad, 1e6, DST);
    }

    function test_quarantine_oftMintsToItselfAndReleases() public {
        _blacklist(oft, bad);
        uint256 supply = oft.totalSupply();
        oft.credit(bad, 700e6, DST); // must not revert: a reverting lzReceive would strand the message
        assertEq(oft.balanceOf(bad), 0);
        assertEq(oft.balanceOf(address(oft)), 700e6);
        assertEq(oft.quarantined(bad), 700e6);
        assertEq(oft.totalSupply(), supply + 700e6); // still minted: it is backed on the home chain
        vm.expectRevert(abi.encodeWithSelector(StablecoinControls.AccountBlacklisted.selector, bad));
        oft.releaseQuarantined(bad, bad); // can't pay a still-blacklisted account
        address issuer = makeAddr("issuer");
        oft.releaseQuarantined(bad, issuer); // e.g. legal order: hand to the issuer
        assertEq(oft.balanceOf(issuer), 700e6);
        assertEq(oft.totalQuarantined(), 0);
    }

    function test_quarantine_adapterKeepsTokens() public {
        adapter.debit(user, 5_000e6, DST); // lock some USDC first
        _blacklist(adapter, bad);
        adapter.credit(bad, 2_000e6, DST);
        assertEq(usdc.balanceOf(bad), 0);
        assertEq(usdc.balanceOf(address(adapter)), 5_000e6); // nothing released
        assertEq(adapter.totalQuarantined(), 2_000e6);
        vm.prank(blacklister);
        adapter.unBlacklist(bad);
        adapter.releaseQuarantined(bad, bad);
        assertEq(usdc.balanceOf(bad), 2_000e6);
    }

    function test_releaseQuarantined_onlyOwner() public {
        _blacklist(oft, bad);
        oft.credit(bad, 1e6, DST);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oft.releaseQuarantined(bad, stranger);
    }

    function test_metadata() public view {
        assertEq(oft.decimals(), 6);
        assertEq(oft.symbol(), "USDC.lz");
        assertEq(oft.decimalConversionRate(), 1); // 6 local = 6 shared: no dust
    }

    function test_rateLimit_blocksAboveLimitInWindow() public {
        oft.debit(user, 6_000e6, DST);
        vm.expectRevert(RateLimiter.RateLimitExceeded.selector);
        oft.debit(user, 4_001e6, DST);
        oft.debit(user, 4_000e6, DST); // exactly up to the limit is fine
    }

    function test_rateLimit_refillsOverTime() public {
        oft.debit(user, LIMIT, DST);
        vm.warp(block.timestamp + WINDOW / 2);
        (, uint256 canSend) = oft.getAmountCanBeSent(DST);
        assertEq(canSend, LIMIT / 2);
        vm.warp(block.timestamp + WINDOW / 2);
        oft.debit(user, LIMIT, DST);
    }

    function test_rateLimit_inflowGivesQuotaBack() public {
        oft.debit(user, LIMIT, DST);
        oft.credit(user, 3_000e6, DST);
        oft.debit(user, 3_000e6, DST);
    }

    function test_rateLimit_appliesToAdapterAndLocks() public {
        adapter.debit(user, LIMIT, DST);
        assertEq(usdc.balanceOf(address(adapter)), LIMIT);
        vm.expectRevert(RateLimiter.RateLimitExceeded.selector);
        adapter.debit(user, 1, DST);
    }

    function test_pause_blocksSendAndReceive() public {
        oft.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        oft.debit(user, 1e6, DST);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        oft.credit(user, 1e6, DST);
        oft.unpause();
        oft.debit(user, 1e6, DST);
    }

    function test_onlyOwner() public {
        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oft.pause();
        RateLimiter.RateLimitConfig[] memory cfg = new RateLimiter.RateLimitConfig[](0);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        adapter.setRateLimits(cfg);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        usdc.mint(stranger, 1);
        vm.stopPrank();
    }
}
