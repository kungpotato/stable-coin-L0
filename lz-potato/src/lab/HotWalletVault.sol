// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Lab model of the ONE control that would have shrunk both 2026 drains: an on-chain
///         circuit breaker on hot-wallet outflow. Binance 14 (EIP-7702) and Mercado Bitcoin
///         (one stolen seed) both emptied wallets in ~25 minutes while humans reacted in hours.
///         A breaker that trips automatically closes exactly that gap — it caps the loss without
///         waiting for anyone to press a button.
/// @dev Two independent brakes:
///      1. AUTO rolling-window cap: withdrawals exceeding `windowCap` within `window` seconds trip
///         the breaker and revert. The attacker gets at most one window's worth, not the whole vault.
///      2. MANUAL guardian pause: the T+0 "stop the bleeding" switch, a separate key from the
///         operator so a compromised operator cannot un-pause itself.
///      The withdrawal token is ERC20 (USDT/USDC-style). ETH is out of scope on purpose — the
///      lesson from both cases is that ETH, once out, cannot be frozen; keep it from leaving at all.
contract HotWalletVault {
    IERC20 public immutable token;
    /// @notice Signs day-to-day withdrawals. The key an attacker steals (seed / 7702 auth).
    address public operator;
    /// @notice Separate incident-response key. Can pause/resume + retune the cap. Never withdraws.
    address public guardian;

    uint256 public window;      // rolling window length, seconds
    uint256 public windowCap;   // max tokens allowed out per window
    uint256 public windowStart; // start of the current window
    uint256 public windowOut;   // tokens already sent in the current window

    bool public tripped;        // auto breaker fired
    bool public paused;         // guardian stopped the bleeding

    event Withdrawn(address indexed to, uint256 amount, uint256 windowOut);
    event BreakerTripped(uint256 attempted, uint256 windowOut, uint256 windowCap);
    event Paused(address indexed by);
    event Resumed(address indexed by);
    event CapChanged(uint256 window, uint256 windowCap);

    constructor(IERC20 _token, address _operator, address _guardian, uint256 _window, uint256 _windowCap) {
        token = _token;
        operator = _operator;
        guardian = _guardian;
        window = _window;
        windowCap = _windowCap;
        windowStart = block.timestamp;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "vault: not operator");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "vault: not guardian");
        _;
    }

    /// @notice Normal withdrawal path. Reverts (and latches `tripped`) the moment a withdrawal
    ///         would push outflow past the window cap — so a stolen operator key drains one
    ///         window at most, then every further sweep bounces until the guardian investigates.
    function withdraw(address to, uint256 amount) external onlyOperator {
        require(!paused, "vault: paused");
        require(!tripped, "vault: breaker tripped");

        // Roll the window forward if it has elapsed.
        if (block.timestamp >= windowStart + window) {
            windowStart = block.timestamp;
            windowOut = 0;
        }

        // The over-cap withdrawal does NOT transfer and latches the breaker. We cannot both revert
        // and persist the latch (a revert rolls back the storage write), so the tripping call
        // succeeds as a no-op that records the trip; every later call then bounces on `tripped`.
        if (windowOut + amount > windowCap) {
            tripped = true;
            emit BreakerTripped(amount, windowOut, windowCap);
            return;
        }

        windowOut += amount;
        require(token.transfer(to, amount), "vault: transfer failed");
        emit Withdrawn(to, amount, windowOut);
    }

    /// @notice T+0 kill switch. A compromised operator cannot call this (separate key), and cannot
    ///         withdraw while it is on.
    function pause() external onlyGuardian {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Clears both brakes after triage. Resets the window so a fresh cap applies.
    function resume() external onlyGuardian {
        paused = false;
        tripped = false;
        windowStart = block.timestamp;
        windowOut = 0;
        emit Resumed(msg.sender);
    }

    function setCap(uint256 _window, uint256 _windowCap) external onlyGuardian {
        window = _window;
        windowCap = _windowCap;
        emit CapChanged(_window, _windowCap);
    }
}
