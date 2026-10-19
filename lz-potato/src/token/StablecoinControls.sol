// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import {InboundMintCap} from "./InboundMintCap.sol";

/// @notice Owner controls shared by every USDC bridge leg (ADR 0003, ADR 0005, ADR 0006): a per-path outbound rate
/// limit, the inbound mint cap (InboundMintCap), a pause switch, and a blacklist run by a separate blacklister role.
/// Bridged funds addressed to a blacklisted account, or above the inbound cap, are QUARANTINED, not reverted: a
/// reverting lzReceive would strand the message forever. The leg holds them and the owner can release them after review.
/// Legs call _beforeDebit / _quarantines from their _debit / _credit and implement _payOutQuarantined.
abstract contract StablecoinControls is RateLimiter, Pausable, InboundMintCap {
    address public blacklister;
    mapping(address => bool) public isBlacklisted;

    event BlacklisterChanged(address indexed blacklister);
    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);

    error AccountBlacklisted(address account);
    error NotBlacklister(address caller);

    modifier onlyBlacklister() {
        if (msg.sender != blacklister) revert NotBlacklister(msg.sender);
        _;
    }

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

    function setBlacklister(address _blacklister) external onlyOwner {
        blacklister = _blacklister;
        emit BlacklisterChanged(_blacklister);
    }

    function blacklist(address _account) external onlyBlacklister {
        isBlacklisted[_account] = true;
        emit Blacklisted(_account);
    }

    function unBlacklist(address _account) external onlyBlacklister {
        isBlacklisted[_account] = false;
        emit UnBlacklisted(_account);
    }

    /// @dev Released funds never go to a still-blacklisted account.
    function _checkPayee(address _payee) internal view override {
        if (isBlacklisted[_payee]) revert AccountBlacklisted(_payee);
    }

    /// @dev Outbound: blocked while paused or for a blacklisted sender; counts against the destination's limit.
    function _beforeDebit(address _from, uint32 _dstEid, uint256 _amountSentLD) internal whenNotPaused {
        if (isBlacklisted[_from]) revert AccountBlacklisted(_from);
        _outflow(_dstEid, _amountSentLD);
    }

    /// @dev Inbound: blocked while paused (the message waits at the executor). Returns true when the credit must be
    /// quarantined instead of paid to `_to`: the recipient is blacklisted, or the message is above what the source
    /// chain's inbound cap still allows (the WHOLE message is held, never split). Only paid credits consume the cap
    /// and give outbound quota back to the path; held funds do neither until the owner releases them.
    function _quarantines(address _to, uint32 _srcEid, uint256 _amountLD) internal whenNotPaused returns (bool) {
        if (isBlacklisted[_to]) {
            _hold(_to, _srcEid, _amountLD);
            return true;
        }
        if (_capHolds(_to, _srcEid, _amountLD)) return true;
        _inflow(_srcEid, _amountLD);
        return false;
    }
}
