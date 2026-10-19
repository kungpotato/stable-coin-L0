// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {BridgeControls} from "./BridgeControls.sol";

/// @notice POTATO on non-home chains (ADR 0002): minted when POTATO is locked on potato, burned when it goes back.
/// BridgeControls (ADR 0006, ADR 0007): pause, outbound rate limit per destination, and the inbound mint cap: a mint
/// above what the source chain's cap still allows goes to this contract, quarantined for the intended recipient
/// (still backed on potato, not spendable) until the owner releases it.
contract PotatoOFT is OFT, BridgeControls {
    constructor(address _endpoint, address _owner) OFT("Potato", "POTATO", _endpoint, _owner) Ownable(_owner) {}

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
        if (_quarantines(_to, _srcEid, _amountLD)) {
            _mint(address(this), _amountLD);
            return _amountLD;
        }
        return super._credit(_to, _amountLD, _srcEid);
    }

    function _payOutQuarantined(address _payee, uint256 _amountLD) internal override {
        _transfer(address(this), _payee, _amountLD);
    }
}
