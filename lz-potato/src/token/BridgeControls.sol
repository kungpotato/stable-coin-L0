// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import {InboundMintCap} from "./InboundMintCap.sol";

/// @notice Owner controls every bridge leg has (ADR 0003, ADR 0006, ADR 0007): a pause switch, a per-path outbound
/// rate limit, and the inbound mint cap. USDC adds a blacklist on top (StablecoinControls); POTATO uses this directly.
/// Legs call _beforeDebit / _quarantines from their _debit / _credit and implement _payOutQuarantined.
/// NOTE: RateLimiter treats a path with no limit set as limit 0, so a leg cannot send anywhere until the owner
/// calls setRateLimits for that destination (the deploy scripts do).
abstract contract BridgeControls is RateLimiter, Pausable, InboundMintCap {
    function setRateLimits(RateLimitConfig[] calldata _configs) external onlyOwner {
        _setRateLimits(_configs);
    }

    function resetRateLimits(uint32[] calldata _eids) external onlyOwner {
        _resetRateLimits(_eids);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev Outbound: blocked while paused (reverts at send, nothing leaves); counts against the destination's limit.
    function _beforeDebit(address _from, uint32 _dstEid, uint256 _amountSentLD) internal whenNotPaused {
        _checkSender(_from);
        _outflow(_dstEid, _amountSentLD);
    }

    /// @dev Inbound: blocked while paused (the message waits at the executor and is delivered after unpause).
    /// Returns true when the credit must be quarantined instead of paid to `_to`: the leg's own rule says so
    /// (_mustHold, e.g. a blacklisted recipient) or it is above what the source chain's inbound cap still allows
    /// (the WHOLE message is held, never split). Only paid credits consume the cap and give outbound quota back to
    /// the path; held funds do neither until the owner releases them.
    function _quarantines(address _to, uint32 _srcEid, uint256 _amountLD) internal whenNotPaused returns (bool) {
        if (_mustHold(_to)) {
            _hold(_to, _srcEid, _amountLD);
            return true;
        }
        if (_capHolds(_to, _srcEid, _amountLD)) return true;
        _inflow(_srcEid, _amountLD);
        return false;
    }

    /// @dev Reject a sender (e.g. blacklisted). Default: any.
    function _checkSender(address _from) internal view virtual {}

    /// @dev Hold every credit to this recipient regardless of the cap (e.g. blacklisted). Default: none.
    function _mustHold(address _to) internal view virtual returns (bool) {}
}
