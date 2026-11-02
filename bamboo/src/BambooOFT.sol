// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBambooReceiver} from "./IBambooReceiver.sol";
import {IBridgeToken} from "./IBridgeToken.sol";

interface IBambooGateway {
    function send(uint64 dstChainId, address receiver, bytes calldata payload)
        external returns (bytes32 msgId, uint64 nonce);
    function blockMessage(uint64 srcChainId, address sender, bytes calldata payload, uint64 nonce) external;
}

/// @title BambooOFT
/// @notice Burn-and-mint cross-chain token transfer on the bamboo messaging layer,
///         with a two-way ACK and a Two-Generals-safe cancel/refund.
///
///  Transfer + ACK:
///    A.send()  -> burn, outbound[msgId]=PENDING, message A->B
///    B receive -> mint, send ACK (msgId) back
///    A receive ACK -> outbound[msgId]=DELIVERED
///
///  Cancel + refund (for a stuck PENDING transfer) — safe against double-mint:
///    A.requestCancel(msgId) -> status=CANCEL_REQUESTED, send CANCEL(msgId,to,amount,nonce) A->B
///    B receive CANCEL -> gateway.blockMessage(origMsgId): reverts if ALREADY DELIVERED,
///                        else marks it processed (can never be delivered); send CANCEL_ACK back
///    A receive CANCEL_ACK -> re-mint (refund) to original sender, status=REFUNDED
///  Because delivery and block both consume the SAME `processed[msgId]` flag, exactly
///  one of {deliver, refund} can ever happen. If B already delivered, blockMessage
///  reverts -> no CANCEL_ACK -> no refund (and the ACK marks the transfer DELIVERED).
///
///  Payload: abi.encode(uint8 kind, bytes inner)
///    0 TRANSFER   inner=abi.encode(to,amount)
///    1 ACK        inner=abi.encode(origMsgId)
///    2 CANCEL     inner=abi.encode(origMsgId,to,amount,nonce)
///    3 CANCEL_ACK inner=abi.encode(origMsgId)
contract BambooOFT is IBambooReceiver {
    uint8 internal constant KIND_TRANSFER = 0;
    uint8 internal constant KIND_ACK = 1;
    uint8 internal constant KIND_CANCEL = 2;
    uint8 internal constant KIND_CANCEL_ACK = 3;

    uint8 internal constant ST_NONE = 0;
    uint8 internal constant ST_PENDING = 1;
    uint8 internal constant ST_DELIVERED = 2;
    uint8 internal constant ST_CANCEL_REQUESTED = 3;
    uint8 internal constant ST_REFUNDED = 4;

    IBambooGateway public immutable gateway;
    IBridgeToken public immutable token;

    address public owner;
    address public pendingOwner;

    mapping(uint64 => address) public peer;

    bool public whitelistEnabled = true;
    mapping(address => bool) public whitelisted;

    uint256 public dailyMintCap; // 0 = unlimited
    uint256 public mintedInWindow;
    uint256 public windowStart;

    struct Outbound {
        address sender;
        address to;
        uint256 amount;
        uint64 dstChainId;
        uint64 nonce;
        uint8 status;
        uint64 ts;
    }
    mapping(bytes32 => Outbound) public outbound;

    event PeerSet(uint64 indexed chainId, address peer);
    event WhitelistSet(address indexed account, bool allowed);
    event WhitelistEnabled(bool enabled);
    event DailyMintCapSet(uint256 cap);
    event OwnershipTransferStarted(address indexed newOwner);
    event OwnershipTransferred(address indexed newOwner);
    event SentCrossChain(bytes32 indexed msgId, uint64 indexed dstChainId, address indexed to, uint256 amount);
    event ReceivedCrossChain(uint64 indexed srcChainId, address indexed to, uint256 amount);
    event TransferDelivered(bytes32 indexed msgId);
    event CancelRequested(bytes32 indexed msgId);
    event TransferRefunded(bytes32 indexed msgId, address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _gateway, address _token) {
        gateway = IBambooGateway(_gateway);
        token = IBridgeToken(_token);
        owner = msg.sender;
        windowStart = block.timestamp;
    }

    // --- ownership (2-step) ---
    function transferOwnership(address n) external onlyOwner {
        pendingOwner = n;
        emit OwnershipTransferStarted(n);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "not pending owner");
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(owner);
    }

    // --- admin ---
    function setPeer(uint64 chainId, address p) external onlyOwner {
        peer[chainId] = p;
        emit PeerSet(chainId, p);
    }

    function setWhitelist(address a, bool allowed) external onlyOwner {
        whitelisted[a] = allowed;
        emit WhitelistSet(a, allowed);
    }

    function setWhitelistEnabled(bool e) external onlyOwner {
        whitelistEnabled = e;
        emit WhitelistEnabled(e);
    }

    function setDailyMintCap(uint256 cap) external onlyOwner {
        dailyMintCap = cap;
        emit DailyMintCapSet(cap);
    }

    // --- send: burn here, instruct the peer to mint ---
    function send(uint64 dstChainId, address to, uint256 amount) external returns (bytes32 msgId) {
        address dstApp = peer[dstChainId];
        require(dstApp != address(0), "no peer");
        require(amount > 0, "amount 0");
        if (whitelistEnabled) {
            require(whitelisted[msg.sender], "sender not whitelisted");
            require(whitelisted[to], "recipient not whitelisted");
        }

        token.burnFrom(msg.sender, amount);
        bytes memory payload = abi.encode(KIND_TRANSFER, abi.encode(to, amount));
        uint64 nonce;
        (msgId, nonce) = gateway.send(dstChainId, dstApp, payload);
        outbound[msgId] = Outbound(msg.sender, to, amount, dstChainId, nonce, ST_PENDING, uint64(block.timestamp));
        emit SentCrossChain(msgId, dstChainId, to, amount);
    }

    // --- cancel a stuck PENDING transfer (original sender or owner) ---
    function requestCancel(bytes32 msgId) external {
        Outbound storage o = outbound[msgId];
        require(o.status == ST_PENDING, "not pending");
        require(msg.sender == o.sender || msg.sender == owner, "not sender/owner");
        o.status = ST_CANCEL_REQUESTED;
        // tell the dest peer to block delivery; it carries what B needs to recompute msgId
        bytes memory inner = abi.encode(msgId, o.to, o.amount, o.nonce);
        gateway.send(o.dstChainId, peer[o.dstChainId], abi.encode(KIND_CANCEL, inner));
        emit CancelRequested(msgId);
    }

    // --- receive handler (gateway-only) ---
    function bambooReceive(uint64 srcChainId, address sender, bytes32 msgId, bytes calldata payload) external {
        require(msg.sender == address(gateway), "not gateway");
        require(sender == peer[srcChainId], "sender not peer");
        (uint8 kind, bytes memory inner) = abi.decode(payload, (uint8, bytes));

        if (kind == KIND_TRANSFER) {
            (address to, uint256 amount) = abi.decode(inner, (address, uint256));
            if (whitelistEnabled) require(whitelisted[to], "recipient not whitelisted");
            _checkAndAccrueCap(amount);
            token.mint(to, amount);
            emit ReceivedCrossChain(srcChainId, to, amount);
            gateway.send(srcChainId, peer[srcChainId], abi.encode(KIND_ACK, abi.encode(msgId)));

        } else if (kind == KIND_ACK) {
            bytes32 orig = abi.decode(inner, (bytes32));
            Outbound storage o = outbound[orig];
            if (o.status == ST_PENDING || o.status == ST_CANCEL_REQUESTED) {
                o.status = ST_DELIVERED;
                emit TransferDelivered(orig);
            }

        } else if (kind == KIND_CANCEL) {
            // block the original (undelivered) transfer on THIS (dest) chain, then ack back
            (bytes32 orig, address to, uint256 amount, uint64 nonce) =
                abi.decode(inner, (bytes32, address, uint256, uint64));
            bytes memory origPayload = abi.encode(KIND_TRANSFER, abi.encode(to, amount));
            // sender == the source peer (OFT on srcChain); receiver (=msg.sender inside gateway) == this app.
            // reverts if the transfer was already delivered -> whole cancel reverts -> no refund. Safe.
            gateway.blockMessage(srcChainId, sender, origPayload, nonce);
            gateway.send(srcChainId, peer[srcChainId], abi.encode(KIND_CANCEL_ACK, abi.encode(orig)));

        } else if (kind == KIND_CANCEL_ACK) {
            // dest confirmed the transfer is blocked -> safe to refund on the source
            bytes32 orig = abi.decode(inner, (bytes32));
            Outbound storage o = outbound[orig];
            if (o.status == ST_CANCEL_REQUESTED) {
                o.status = ST_REFUNDED;
                token.mint(o.sender, o.amount); // restore the burned tokens
                emit TransferRefunded(orig, o.sender, o.amount);
            }
        }
    }

    // --- views ---
    function isDelivered(bytes32 msgId) external view returns (bool) {
        return outbound[msgId].status == ST_DELIVERED;
    }

    function isRefunded(bytes32 msgId) external view returns (bool) {
        return outbound[msgId].status == ST_REFUNDED;
    }

    function statusOf(bytes32 msgId) external view returns (uint8) {
        return outbound[msgId].status;
    }

    function isStuck(bytes32 msgId, uint64 timeout) external view returns (bool) {
        Outbound storage o = outbound[msgId];
        return o.status == ST_PENDING && block.timestamp > o.ts + timeout;
    }

    // --- M-3: rolling daily cap ---
    function _checkAndAccrueCap(uint256 amount) internal {
        if (dailyMintCap == 0) return;
        if (block.timestamp >= windowStart + 1 days) {
            windowStart = block.timestamp;
            mintedInWindow = 0;
        }
        mintedInWindow += amount;
        require(mintedInWindow <= dailyMintCap, "daily mint cap");
    }
}
