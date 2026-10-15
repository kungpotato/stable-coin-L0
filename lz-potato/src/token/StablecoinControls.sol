// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";

/// @notice Owner controls shared by every USDC bridge leg (ADR 0003, ADR 0005): a per-path outbound rate limit,
/// a pause switch, and a blacklist run by a separate blacklister role.
/// Bridged funds addressed to a blacklisted account are QUARANTINED, not reverted: a reverting lzReceive would
/// strand the message forever. The leg holds them and the owner can release them after review.
/// Legs call _beforeDebit / _quarantines from their _debit / _credit and implement _payOutQuarantined.
abstract contract StablecoinControls is RateLimiter, Pausable, Ownable {
    address public blacklister;
    mapping(address => bool) public isBlacklisted;
    mapping(address => uint256) public quarantined; // per intended recipient, local decimals
    uint256 public totalQuarantined;

    event BlacklisterChanged(address indexed blacklister);
    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);
    event Quarantined(address indexed to, uint32 srcEid, uint256 amount);
    event QuarantineReleased(address indexed to, address indexed payee, uint256 amount);

    error AccountBlacklisted(address account);
    error NotBlacklister(address caller);
    error NothingQuarantined(address to);

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

    /// @notice Pay out what arrived for `_to` while it was blacklisted, to `_payee`: `_to` itself once cleared,
    /// or e.g. the issuer under a legal order. Owner decision, never automatic.
    function releaseQuarantined(address _to, address _payee) external onlyOwner {
        uint256 amount = quarantined[_to];
        if (amount == 0) revert NothingQuarantined(_to);
        if (isBlacklisted[_payee]) revert AccountBlacklisted(_payee);
        quarantined[_to] = 0;
        totalQuarantined -= amount;
        _payOutQuarantined(_payee, amount);
        emit QuarantineReleased(_to, _payee, amount);
    }

    /// @dev Outbound: blocked while paused or for a blacklisted sender; counts against the destination's limit.
    function _beforeDebit(address _from, uint32 _dstEid, uint256 _amountSentLD) internal whenNotPaused {
        if (isBlacklisted[_from]) revert AccountBlacklisted(_from);
        _outflow(_dstEid, _amountSentLD);
    }

    /// @dev Inbound: blocked while paused (the message waits at the executor); gives quota back to that path.
    /// Returns true when the credit must be quarantined instead of paid to `_to`.
    function _quarantines(address _to, uint32 _srcEid, uint256 _amountLD) internal whenNotPaused returns (bool) {
        _inflow(_srcEid, _amountLD);
        if (!isBlacklisted[_to]) return false;
        quarantined[_to] += _amountLD;
        totalQuarantined += _amountLD;
        emit Quarantined(_to, _srcEid, _amountLD);
        return true;
    }

    /// @dev Move quarantined funds held by the leg to `_payee`.
    function _payOutQuarantined(address _payee, uint256 _amountLD) internal virtual;
}
