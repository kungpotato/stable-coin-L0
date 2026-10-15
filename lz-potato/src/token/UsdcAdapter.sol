// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFTAdapter} from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import {StablecoinControls} from "./StablecoinControls.sol";

/// @notice USDC home leg (anvil, ADR 0003): locks IssuerUSDC on send, releases it on receive.
/// IssuerUSDC.balanceOf(this) backs UsdcOFT supply on every other chain.
contract UsdcAdapter is OFTAdapter, StablecoinControls {
    constructor(address _usdc, address _endpoint, address _owner) OFTAdapter(_usdc, _endpoint, _owner) Ownable(_owner) {}

    function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        _beforeDebit(_dstEid, amountSentLD);
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    function _credit(address _to, uint256 _amountLD, uint32 _srcEid) internal override returns (uint256) {
        _beforeCredit(_srcEid, _amountLD);
        return super._credit(_to, _amountLD, _srcEid);
    }
}
