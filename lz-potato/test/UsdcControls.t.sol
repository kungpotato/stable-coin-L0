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
