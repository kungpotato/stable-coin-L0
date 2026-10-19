// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Inbound mint cap per source chain, and the quarantine that holds what is not paid out (ADR 0006).
/// An outbound rate limit does not limit what ARRIVES, so a forged inbound message (compromised verifier, as in the
/// DEMOWEAK drill or the Cysic incident) could otherwise mint or unlock any amount at once. A credit above what the
/// cap still allows is QUARANTINED whole, not reverted (a reverting lzReceive strands the message forever) and not
/// split (or every forged message would pay out up to the cap). The leg holds it; the owner releases it after review.
/// Usage decays linearly over `window` like RateLimiter; window == 0 means no cap (the default).
/// Used by every bridge leg: USDC through StablecoinControls (which adds blacklist, pause, rate limit), POTATO directly.
abstract contract InboundMintCap is Ownable {
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
    mapping(address => uint256) public quarantined; // per intended recipient, local decimals
    uint256 public totalQuarantined;

    event InboundCapSet(uint32 srcEid, uint256 limit, uint64 window);
    event InboundCapExceeded(address indexed to, uint32 srcEid, uint256 amount, uint256 available);
    event Quarantined(address indexed to, uint32 srcEid, uint256 amount);
    event QuarantineReleased(address indexed to, address indexed payee, uint256 amount);

    error NothingQuarantined(address to);

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

    /// @notice Pay out what was held for `_to` to `_payee`: `_to` itself once cleared, or e.g. the issuer under a
    /// legal order. Owner decision, never automatic, and it does not count against the inbound cap.
    function releaseQuarantined(address _to, address _payee) external onlyOwner {
        uint256 amount = quarantined[_to];
        if (amount == 0) revert NothingQuarantined(_to);
        _checkPayee(_payee);
        quarantined[_to] = 0;
        totalQuarantined -= amount;
        _payOutQuarantined(_payee, amount);
        emit QuarantineReleased(_to, _payee, amount);
    }

    /// @dev Returns true (and holds the credit) when it is above what `_srcEid`'s cap still allows; otherwise the
    /// credit is counted against the cap and the caller pays it out. Held credits do not use the cap.
    function _capHolds(address _to, uint32 _srcEid, uint256 _amountLD) internal returns (bool) {
        InboundCap storage cap = inboundCaps[_srcEid];
        if (cap.window == 0) return false;
        uint256 used = _inboundUsed(cap);
        uint256 available = used >= cap.limit ? 0 : cap.limit - used;
        if (_amountLD > available) {
            _hold(_to, _srcEid, _amountLD);
            emit InboundCapExceeded(_to, _srcEid, _amountLD, available);
            return true;
        }
        cap.used = used + _amountLD;
        cap.lastUpdated = uint64(block.timestamp);
        return false;
    }

    function _hold(address _to, uint32 _srcEid, uint256 _amountLD) internal {
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

    /// @dev Reject a payee that must not receive released funds (e.g. a blacklisted account). Default: any.
    function _checkPayee(address _payee) internal view virtual {}

    /// @dev Move quarantined funds held by the leg to `_payee`.
    function _payOutQuarantined(address _payee, uint256 _amountLD) internal virtual;
}
