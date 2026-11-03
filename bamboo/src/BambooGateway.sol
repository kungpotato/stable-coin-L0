// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBambooReceiver} from "./IBambooReceiver.sol";

/// @title BambooGateway
/// @notice GENERIC cross-chain messaging gateway. Carries arbitrary `payload` bytes;
///         token transfer (BambooOFT) is just one app on top. The gateway never
///         touches tokens or funds.
///
///         Trust model: (1) attesters sign a DOMAIN-BOUND digest of msgId, (2) a
///         threshold N-of-M is required. Replay is prevented per msgId.
///
///  Hardening in this version (from the self-audit):
///   H-1 domain separation: the signed digest binds to this gateway + its EVM chain,
///       so a signature cannot be replayed on another gateway/chain.
///   H-3 recovery: delivery is wrapped in try/catch; a failed delivery is stored and
///       can be re-attempted via retry() instead of reverting forever or being lost.
///   H-4 liveness: removing attesters cannot drop the set below the threshold.
///   M-1 pause: owner (→ consortium multisig) can pause in an emergency.
///   M-4 governance: 2-step ownership; owner is meant to be a multisig + timelock.
///   L-2 reentrancy: receiveMessage/retry are nonReentrant (plus checks-effects order).
contract BambooGateway {
    /// @dev minimum signatures ever allowed — blocks the 1-of-1 / single-verifier
    ///      misconfiguration that caused the largest 2026 bridge loss (Kelp DAO, ~$292M).
    uint256 public constant MIN_THRESHOLD = 2;

    uint64 public immutable localChainId; // logical chain id (not the EVM chainid)
    address public owner;
    address public pendingOwner;
    address public guardian; // emergency pause only (e.g. BOT) — faster than owner multisig
    bool public paused;

    mapping(address => bool) public isAttester;
    uint256 public attesterCount;
    uint256 public threshold;

    uint64 public outNonce;
    mapping(bytes32 => bool) public processed; // msgId => consumed (delivered OR cancelled)
    mapping(bytes32 => bool) public cancelled; // msgId => blocked by the cancel protocol

    struct FailedMsg {
        uint64 srcChainId;
        address sender;
        address receiver;
        bool exists;
        bytes payload;
    }
    mapping(bytes32 => FailedMsg) public failed;

    uint256 private _lock = 1;

    event AttesterSet(address indexed attester, bool allowed);
    event ThresholdSet(uint256 threshold);
    event PausedSet(bool paused);
    event GuardianSet(address indexed guardian);
    event OwnershipTransferStarted(address indexed newOwner);
    event OwnershipTransferred(address indexed newOwner);
    event MessageSent(
        bytes32 indexed msgId,
        uint64 srcChainId,
        uint64 dstChainId,
        address sender,
        address receiver,
        bytes payload,
        uint64 nonce
    );
    event MessageReceived(bytes32 indexed msgId, uint64 srcChainId, address sender, address receiver);
    event MessageFailed(bytes32 indexed msgId);
    event MessageCancelled(bytes32 indexed msgId);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    modifier nonReentrant() {
        require(_lock == 1, "reentrant");
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(uint64 _localChainId) {
        localChainId = _localChainId;
        owner = msg.sender;
    }

    // --- ownership (M-4: 2-step; owner should be a multisig + timelock) ---
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
    function setGuardian(address g) external onlyOwner {
        guardian = g;
        emit GuardianSet(g);
    }

    /// @notice Emergency pause — owner OR guardian (fast incident response).
    function pause() external {
        require(msg.sender == owner || msg.sender == guardian, "not owner/guardian");
        paused = true;
        emit PausedSet(true);
    }

    /// @notice Unpause — owner only (guardian cannot resume, only halt).
    function unpause() external onlyOwner {
        paused = false;
        emit PausedSet(false);
    }

    function setAttester(address a, bool allowed) external onlyOwner {
        if (allowed && !isAttester[a]) {
            attesterCount++;
        } else if (!allowed && isAttester[a]) {
            attesterCount--;
            // H-4: never leave the set unable to meet the threshold
            require(threshold == 0 || attesterCount >= threshold, "would break threshold");
        }
        isAttester[a] = allowed;
        emit AttesterSet(a, allowed);
    }

    function setThreshold(uint256 t) external onlyOwner {
        require(t >= MIN_THRESHOLD, "below min threshold"); // anti 1-of-1 (Kelp DAO)
        require(t <= attesterCount, "threshold > attesters");
        threshold = t;
        emit ThresholdSet(t);
    }

    // --- message id (same on both chains; for dedup) ---
    function computeMsgId(
        uint64 srcChainId,
        uint64 dstChainId,
        address sender,
        address receiver,
        bytes32 payloadHash,
        uint64 nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(srcChainId, dstChainId, sender, receiver, payloadHash, nonce));
    }

    // --- H-1: domain-bound digest (binds to THIS gateway + its EVM chain) ---
    function digest(bytes32 msgId) public view returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(block.chainid, address(this), msgId));
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner));
    }

    // --- send: emit a generic message for the relay to carry ---
    function send(uint64 dstChainId, address receiver, bytes calldata payload)
        external
        whenNotPaused
        returns (bytes32 msgId, uint64 nonce)
    {
        require(receiver != address(0), "receiver 0");
        nonce = outNonce++;
        msgId = computeMsgId(localChainId, dstChainId, msg.sender, receiver, keccak256(payload), nonce);
        emit MessageSent(msgId, localChainId, dstChainId, msg.sender, receiver, payload, nonce);
    }

    /// @notice Block an UNDELIVERED inbound message addressed to the caller, so it can
    ///         never be delivered. Used by the cancel/refund protocol: the dest app
    ///         blocks its own pending inbound BEFORE the source refunds, so a transfer
    ///         can never both mint (here) and refund (on the source) — no double-mint.
    ///         Permissionless, but only affects msgIds whose receiver == msg.sender,
    ///         so no app can block another app's messages.
    function blockMessage(uint64 srcChainId, address sender, bytes calldata payload, uint64 nonce)
        external
        whenNotPaused
    {
        bytes32 msgId = computeMsgId(srcChainId, localChainId, sender, msg.sender, keccak256(payload), nonce);
        require(!processed[msgId], "already processed"); // already delivered or cancelled
        processed[msgId] = true;
        cancelled[msgId] = true;
        emit MessageCancelled(msgId);
    }

    // --- receive: verify threshold, then deliver (recoverable on failure) ---
    function receiveMessage(
        uint64 srcChainId,
        address sender,
        address receiver,
        bytes calldata payload,
        uint64 nonce,
        bytes[] calldata sigs
    ) external whenNotPaused nonReentrant {
        require(threshold > 0, "threshold unset");
        bytes32 msgId =
            computeMsgId(srcChainId, localChainId, sender, receiver, keccak256(payload), nonce);
        require(!processed[msgId], "replay");
        _verify(msgId, sigs);

        processed[msgId] = true; // effects before interaction
        // H-3: do not let an app revert lose the message — store it for retry()
        try IBambooReceiver(receiver).bambooReceive(srcChainId, sender, msgId, payload) {
            emit MessageReceived(msgId, srcChainId, sender, receiver);
        } catch {
            failed[msgId] = FailedMsg(srcChainId, sender, receiver, true, payload);
            emit MessageFailed(msgId);
        }
    }

    // --- H-3: re-attempt a previously failed delivery (anyone may call) ---
    function retry(bytes32 msgId) external nonReentrant {
        FailedMsg memory f = failed[msgId];
        require(f.exists, "no failed msg");
        delete failed[msgId];
        IBambooReceiver(f.receiver).bambooReceive(f.srcChainId, f.sender, msgId, f.payload); // reverts if still failing
        emit MessageReceived(msgId, f.srcChainId, f.sender, f.receiver);
    }

    // --- verification: (1) signatures + (2) threshold ---
    function _verify(bytes32 msgId, bytes[] calldata sigs) internal view {
        bytes32 d = digest(msgId);
        address last = address(0);
        uint256 count;
        for (uint256 i = 0; i < sigs.length; i++) {
            address signer = _recover(d, sigs[i]);
            require(signer > last, "unsorted/dup"); // strictly ascending => unique
            require(isAttester[signer], "not attester");
            last = signer;
            count++;
        }
        require(count >= threshold, "below threshold");
    }

    function _recover(bytes32 d, bytes calldata sig) internal pure returns (address) {
        require(sig.length == 65, "bad sig len");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
        require(v == 27 || v == 28, "bad v");
        require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, "high s");
        address signer = ecrecover(d, v, r, s);
        require(signer != address(0), "bad sig");
        return signer;
    }
}
