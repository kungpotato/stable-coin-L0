// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {NativeOFTAdapter} from "@layerzerolabs/oft-evm/contracts/NativeOFTAdapter.sol";
import {BridgeControls} from "./BridgeControls.sol";

/// @notice potato side of POTATO (home chain, ADR 0002): locks native POTATO sent as msg.value,
/// releases it with a native transfer when POTATO comes back. Its native balance minus totalQuarantined is the
/// backing for PotatoOFT on every other chain.
/// BridgeControls (ADR 0006, ADR 0007): pause, outbound rate limit per destination, and the inbound mint cap: a
/// release above what the source chain's cap still allows stays in the adapter, quarantined for the intended
/// recipient, until the owner releases it.
contract PotatoNativeAdapter is NativeOFTAdapter, BridgeControls {
    constructor(address _endpoint, address _owner) NativeOFTAdapter(18, _endpoint, _owner) Ownable(_owner) {}

    /// @dev Checked before the lock: while paused or above the limit, send() reverts and msg.value goes back.
    function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        _beforeDebit(_from, _dstEid, amountSentLD);
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    function _credit(address _to, uint256 _amountLD, uint32 _srcEid) internal override returns (uint256) {
        if (_quarantines(_to, _srcEid, _amountLD)) return _amountLD; // native stays locked here, held for _to
        return super._credit(_to, _amountLD, _srcEid);
    }

    function _payOutQuarantined(address _payee, uint256 _amountLD) internal override {
        (bool success, bytes memory data) = payable(_payee).call{value: _amountLD}("");
        if (!success) revert CreditFailed(_payee, _amountLD, data); // owner picks a payee that can take native
    }
}
