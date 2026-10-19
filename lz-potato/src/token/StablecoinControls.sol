// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {RateLimiter} from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";

/// @notice Owner controls shared by every USDC bridge leg (ADR 0003, ADR 0005, ADR 0006): a per-path outbound rate
/// limit, a per-path inbound mint cap, a pause switch, and a blacklist run by a separate blacklister role.
/// Bridged funds addressed to a blacklisted account, or above the inbound cap, are QUARANTINED, not reverted: a
/// reverting lzReceive would strand the message forever. The leg holds them and the owner can release them after review.
/// Legs call _beforeDebit / _quarantines from their _debit / _credit and implement _payOutQuarantined.
abstract contract StablecoinControls is RateLimiter, Pausable, Ownable {
    address public blacklister;
    mapping(address => bool) public isBlacklisted;
    mapping(address => uint256) public quarantined; // per intended recipient, local decimals
    uint256 public totalQuarantined;

    /// @dev Inbound mint cap per source chain (ADR 0006). The outbound RateLimiter does not limit what ARRIVES, so a
    /// forged inbound message (compromised verifier, as in the DEMOWEAK drill or the Cysic incident) could otherwise
    /// mint any amount at once. Usage decays linearly over `window` like RateLimiter. window == 0 means no cap.
    struct InboundCap {
        uint256 limit;
        uint64 window;
        uint64 lastUpdated;
        uint256 used; // as of lastUpdated
    }

    struct InboundCapConfig {
        uint32 srcEid;
        uint256 limit;
        uint64 window;
    }

    mapping(uint32 srcEid => InboundCap) public inboundCaps;

    event BlacklisterChanged(address indexed blacklister);
    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);
    event Quarantined(address indexed to, uint32 srcEid, uint256 amount);
    event QuarantineReleased(address indexed to, address indexed payee, uint256 amount);
    event InboundCapSet(uint32 srcEid, uint256 limit, uint64 window);
    event InboundCapExceeded(address indexed to, uint32 srcEid, uint256 amount, uint256 available);

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

    /// @notice Set (or with window 0, remove) the inbound mint cap of each source chain. Usage so far is carried over.
    function setInboundCaps(InboundCapConfig[] calldata _configs) external onlyOwner {
        for (uint256 i = 0; i < _configs.length; i++) {
            InboundCap storage cap = inboundCaps[_configs[i].srcEid];
            cap.used = _inboundUsed(cap);
            cap.lastUpdated = uint64(block.timestamp);
            cap.limit = _configs[i].limit;
            cap.window = _configs[i].window;
            emit InboundCapSet(_configs[i].srcEid, _configs[i].limit, _configs[i].window);
        }
    }

    /// @notice How much can still be credited from `_srcEid` right now without being held (max uint if uncapped).
    function inboundAvailable(uint32 _srcEid) public view returns (uint256) {
        InboundCap storage cap = inboundCaps[_srcEid];
        if (cap.window == 0) return type(uint256).max;
        uint256 used = _inboundUsed(cap);
        return used >= cap.limit ? 0 : cap.limit - used;
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

    /// @notice Pay out what was held for `_to` (it was blacklisted, or the message was above the inbound cap), to
    /// `_payee`: `_to` itself once cleared, or e.g. the issuer under a legal order. Owner decision, never automatic,
    /// and it does not count against the inbound cap.
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

    /// @dev Inbound: blocked while paused (the message waits at the executor). Returns true when the credit must be
    /// quarantined instead of paid to `_to`: the recipient is blacklisted, or the message is above what the source
    /// chain's inbound cap still allows (the WHOLE message is held, never split). Only paid credits consume the cap
    /// and give outbound quota back to the path; held funds do neither until the owner releases them.
    function _quarantines(address _to, uint32 _srcEid, uint256 _amountLD) internal whenNotPaused returns (bool) {
        if (isBlacklisted[_to]) {
            _hold(_to, _srcEid, _amountLD);
            return true;
        }
        InboundCap storage cap = inboundCaps[_srcEid];
        if (cap.window != 0) {
            uint256 used = _inboundUsed(cap);
            uint256 available = used >= cap.limit ? 0 : cap.limit - used;
            if (_amountLD > available) {
                _hold(_to, _srcEid, _amountLD);
                emit InboundCapExceeded(_to, _srcEid, _amountLD, available);
                return true;
            }
            cap.used = used + _amountLD;
            cap.lastUpdated = uint64(block.timestamp);
        }
        _inflow(_srcEid, _amountLD);
        return false;
    }

    function _hold(address _to, uint32 _srcEid, uint256 _amountLD) private {
        quarantined[_to] += _amountLD;
        totalQuarantined += _amountLD;
        emit Quarantined(_to, _srcEid, _amountLD);
    }

    /// @dev Usage still counted at this moment: decays by limit/window per second since lastUpdated.
    function _inboundUsed(InboundCap storage cap) private view returns (uint256) {
        if (cap.window == 0) return 0;
        uint256 decay = (block.timestamp - cap.lastUpdated) * cap.limit / cap.window;
        return cap.used > decay ? cap.used - decay : 0;
    }

    /// @dev Move quarantined funds held by the leg to `_payee`.
    function _payOutQuarantined(address _payee, uint256 _amountLD) internal virtual;
}
