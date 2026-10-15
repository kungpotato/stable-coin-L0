// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {UsdcVault} from "../src/compose/UsdcVault.sol";
import {UsdcDepositComposer} from "../src/compose/UsdcDepositComposer.sol";

/// Stand-in for USDC.lz: the composer only needs it to be an ERC-20 it holds.
contract FakeUsdcLz is ERC20 {
    constructor() ERC20("USDC.lz", "USDC.lz") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amt) external { _mint(to, amt); }
}

contract DepositComposerTest is Test {
    FakeUsdcLz usdc;
    UsdcVault vault;
    UsdcDepositComposer composer;
    address endpoint = makeAddr("endpoint");
    address alice = makeAddr("alice");
    bytes32 guid = keccak256("guid");

    function setUp() public {
        usdc = new FakeUsdcLz();
        vault = new UsdcVault(usdc, address(this));
        composer = new UsdcDepositComposer(endpoint, address(usdc), vault, address(this));
    }

    /// What OFTCore hands the endpoint: nonce, srcEid, amount, composeFrom, abi.encode(beneficiary)
    function _msg(uint256 amount, address beneficiary) internal pure returns (bytes memory) {
        return OFTComposeMsgCodec.encode(1, 40338, amount, abi.encodePacked(bytes32(uint256(1)), abi.encode(beneficiary)));
    }

    /// lzReceive already credited `amount` to the composer; now the executor's lzCompose arrives
    function _compose(address from, uint256 amount, address beneficiary) internal {
        vm.prank(endpoint);
        composer.lzCompose(from, guid, _msg(amount, beneficiary), address(0), "");
    }

    function test_deposit_forBeneficiary() public {
        usdc.mint(address(composer), 100e6);
        _compose(address(usdc), 100e6, alice);
        assertEq(vault.balanceOf(alice), 100e6); // shares 1:1 on an empty vault
        assertEq(usdc.balanceOf(address(composer)), 0);
    }

    function test_rejects_callerOtherThanEndpoint() public {
        usdc.mint(address(composer), 100e6);
        vm.expectRevert(abi.encodeWithSelector(UsdcDepositComposer.OnlyEndpoint.selector, address(this)));
        composer.lzCompose(address(usdc), guid, _msg(100e6, alice), address(0), "");
    }

    /// Another OApp on the same endpoint queues a compose to us claiming 1,000,000: it must not
    /// spend the USDC.lz other users have in flight here.
    function test_rejects_composeFromAnotherOApp() public {
        usdc.mint(address(composer), 100e6); // someone else's in-flight deposit
        address evil = makeAddr("evilOApp");
        vm.prank(endpoint);
        vm.expectRevert(abi.encodeWithSelector(UsdcDepositComposer.UntrustedOApp.selector, evil));
        composer.lzCompose(evil, guid, _msg(1_000_000e6, alice), address(0), "");
        assertEq(usdc.balanceOf(address(composer)), 100e6);
    }

    function test_failedDeposit_refundsBeneficiary() public {
        vault.setDepositsOpen(false);
        usdc.mint(address(composer), 100e6);
        _compose(address(usdc), 100e6, alice); // must not revert: a revert keeps the tokens in the composer
        assertEq(usdc.balanceOf(alice), 100e6);
        assertEq(vault.balanceOf(alice), 0);
    }
}
