// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {StablecoinControls} from "./StablecoinControls.sol";

/// @notice Bridged USDC on non-home chains (potato, ADR 0003). Symbol USDC.lz so it is never confused
/// with potato's unbacked MockUSDC. Minted on receive, burned on send. Blacklisted accounts can neither
/// move nor bridge it (ADR 0005).
contract UsdcOFT is OFT, StablecoinControls {
    constructor(address _endpoint, address _owner) OFT("USD Coin (LayerZero)", "USDC.lz", _endpoint, _owner) Ownable(_owner) {}

    /// @dev 6 like the home token; OFT reads this in its constructor for the shared-decimals conversion.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        _beforeDebit(_from, _dstEid, amountSentLD);
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    /// @dev A blacklisted recipient's USDC.lz is minted to this contract (quarantined): still backed, not spendable.
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

    /// @dev Token-level blacklist: covers transfers, transferFrom, and the burn in _debit.
    function _update(address _from, address _to, uint256 _value) internal override {
        if (isBlacklisted[_from]) revert AccountBlacklisted(_from);
        if (isBlacklisted[_to]) revert AccountBlacklisted(_to);
        super._update(_from, _to, _value);
    }
}
