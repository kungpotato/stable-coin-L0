// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPoolToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
}

/// @title FastPayPool
/// @notice Fast-path liquidity pool for retail cross-chain payments (the "buy fruit" flow).
///         It sits on the MERCHANT's chain and is prefunded with stablecoin. When a user
///         on another chain pays, the PSP/operator instantly credits the merchant LOCALLY
///         from this pool (~1s, one same-chain transfer) — the merchant does not wait for
///         cross-chain settlement. The pool is later replenished by bamboo, which settles
///         the netted user payments cross-chain in BATCHES (see BambooOFT.sendBatch).
///
///         Trust: the operator fronts liquidity and bears short-term credit risk until
///         settlement (exactly like a card acquirer). Risk is bounded by pool size,
///         per-payout + daily caps, pause, and — in the regulated model — the operator
///         being a licensed, accountable PSP.
contract FastPayPool {
    IPoolToken public immutable token;
    address public owner;
    address public operator; // PSP allowed to front instant payouts
    bool public paused;

    uint256 public maxPayout;       // 0 = unlimited (per payout)
    uint256 public dailyPayoutCap;  // 0 = unlimited (per 24h)
    uint256 public paidInWindow;
    uint256 public windowStart;

    mapping(bytes32 => bool) public paid; // paymentRef => already paid (anti double-pay)

    event OperatorSet(address indexed operator);
    event PausedSet(bool paused);
    event CapsSet(uint256 maxPayout, uint256 dailyPayoutCap);
    event MerchantPaid(address indexed merchant, uint256 amount, bytes32 indexed ref);
    event Withdrawn(address indexed to, uint256 amount);

    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }
    modifier onlyOperator() { require(msg.sender == operator, "not operator"); _; }
    modifier whenNotPaused() { require(!paused, "paused"); _; }

    constructor(address _token) {
        token = IPoolToken(_token);
        owner = msg.sender;
        windowStart = block.timestamp;
    }

    // --- admin ---
    function setOperator(address o) external onlyOwner { operator = o; emit OperatorSet(o); }
    function setPaused(bool p) external onlyOwner { paused = p; emit PausedSet(p); }
    function setCaps(uint256 _maxPayout, uint256 _dailyPayoutCap) external onlyOwner {
        maxPayout = _maxPayout; dailyPayoutCap = _dailyPayoutCap; emit CapsSet(_maxPayout, _dailyPayoutCap);
    }
    function withdraw(address to, uint256 amount) external onlyOwner {
        require(token.transfer(to, amount), "transfer failed");
        emit Withdrawn(to, amount);
    }

    // --- fast path: instant local payout to a merchant ---
    /// @param ref a unique reference to the user's off-chain-verified payment (anti double-pay)
    function payMerchant(address merchant, uint256 amount, bytes32 ref)
        external onlyOperator whenNotPaused
    {
        require(merchant != address(0), "merchant 0");
        require(amount > 0, "amount 0");
        require(!paid[ref], "already paid");
        if (maxPayout > 0) require(amount <= maxPayout, "over max payout");
        _accrueDaily(amount);
        paid[ref] = true;
        require(token.transfer(merchant, amount), "transfer failed"); // instant, local
        emit MerchantPaid(merchant, amount, ref);
    }

    function poolBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // --- internal ---
    function _accrueDaily(uint256 amount) internal {
        if (dailyPayoutCap == 0) return;
        if (block.timestamp >= windowStart + 1 days) { windowStart = block.timestamp; paidInWindow = 0; }
        paidInWindow += amount;
        require(paidInWindow <= dailyPayoutCap, "daily payout cap");
    }
}
