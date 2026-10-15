// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";

/// @notice Owner controls shared by every USDC bridge leg (ADR 0003): a per-path outbound rate limit
/// and a pause switch. Legs call _beforeDebit/_beforeCredit from their _debit/_credit.
abstract contract StablecoinControls is RateLimiter, Pausable, Ownable {
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

    /// @dev Outbound: blocked while paused; counts against the destination's limit (reverts RateLimitExceeded).
    function _beforeDebit(uint32 _dstEid, uint256 _amountSentLD) internal whenNotPaused {
        _outflow(_dstEid, _amountSentLD);
    }

    /// @dev Inbound: blocked while paused (the message waits at the executor); gives quota back to that path.
    function _beforeCredit(uint32 _srcEid, uint256 _amountLD) internal whenNotPaused {
        _inflow(_srcEid, _amountLD);
    }
}
