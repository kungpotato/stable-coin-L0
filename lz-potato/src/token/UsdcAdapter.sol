// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OFTAdapter} from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import {StablecoinControls} from "./StablecoinControls.sol";

/// @notice USDC home leg (anvil, ADR 0003): locks IssuerUSDC on send, releases it on receive.
/// IssuerUSDC.balanceOf(this) - totalQuarantined backs UsdcOFT supply on every other chain.
contract UsdcAdapter is OFTAdapter, StablecoinControls {
    using SafeERC20 for IERC20;

    constructor(address _usdc, address _endpoint, address _owner) OFTAdapter(_usdc, _endpoint, _owner) Ownable(_owner) {}

    function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        _beforeDebit(_from, _dstEid, amountSentLD);
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    /// @dev A blacklisted recipient's USDC stays in the adapter (quarantined) instead of being released.
    function _credit(address _to, uint256 _amountLD, uint32 _srcEid) internal override returns (uint256) {
        if (_quarantines(_to, _srcEid, _amountLD)) return _amountLD;
        return super._credit(_to, _amountLD, _srcEid);
    }

    function _payOutQuarantined(address _payee, uint256 _amountLD) internal override {
        innerToken.safeTransfer(_payee, _amountLD);
    }
}
