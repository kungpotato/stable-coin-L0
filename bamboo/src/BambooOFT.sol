// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IBambooReceiver} from "./IBambooReceiver.sol";
import {IBridgeToken} from "./IBridgeToken.sol";

interface IBambooGateway {
    function send(uint64 dstChainId, address receiver, bytes calldata payload) external returns (bytes32);
}

/// @title BambooOFT
/// @notice Burn-and-mint cross-chain token transfer, as an APP on the bamboo
///         messaging layer. Integrates with the issuer's own token via IBridgeToken
///         (issuer keeps proxy/upgradability/controls, grants this app a minter role).
///
///  Hardening (self-audit):
///   M-2 whitelist: only KYC'd wallets can send / receive (BOT requirement).
///   M-3 mint cap: a rolling daily inbound cap bounds damage from a compromised
///       attester set (0 = unlimited).
///   M-4 governance: 2-step ownership; owner is meant to be a multisig + timelock.
contract BambooOFT is IBambooReceiver {
    IBambooGateway public immutable gateway;
    IBridgeToken public immutable token;

    address public owner;
    address public pendingOwner;

    /// dstChainId => sibling BambooOFT address on that chain (trusted peer)
    mapping(uint64 => address) public peer;

    // M-2 whitelist
    bool public whitelistEnabled = true;
    mapping(address => bool) public whitelisted;

    // M-3 rolling daily inbound mint cap (0 = unlimited)
    uint256 public dailyMintCap;
    uint256 public mintedInWindow;
    uint256 public windowStart;

    event PeerSet(uint64 indexed chainId, address peer);
    event WhitelistSet(address indexed account, bool allowed);
    event WhitelistEnabled(bool enabled);
    event DailyMintCapSet(uint256 cap);
    event OwnershipTransferStarted(address indexed newOwner);
    event OwnershipTransferred(address indexed newOwner);
    event SentCrossChain(uint64 indexed dstChainId, address indexed to, uint256 amount);
    event ReceivedCrossChain(uint64 indexed srcChainId, address indexed to, uint256 amount);

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
            require(whitelisted[to], "recipient not whitelisted"); // M-2
        }

        token.burnFrom(msg.sender, amount);
        bytes memory payload = abi.encode(to, amount);
        msgId = gateway.send(dstChainId, dstApp, payload);
        emit SentCrossChain(dstChainId, to, amount);
    }

    // --- receive: called by the gateway after threshold verification ---
    function bambooReceive(uint64 srcChainId, address sender, bytes calldata payload) external {
        require(msg.sender == address(gateway), "not gateway");
        require(sender == peer[srcChainId], "sender not peer"); // only our sibling may mint
        (address to, uint256 amount) = abi.decode(payload, (address, uint256));

        if (whitelistEnabled) require(whitelisted[to], "recipient not whitelisted"); // M-2
        _checkAndAccrueCap(amount); // M-3

        token.mint(to, amount);
        emit ReceivedCrossChain(srcChainId, to, amount);
    }

    // --- M-3: rolling daily cap ---
    function _checkAndAccrueCap(uint256 amount) internal {
        if (dailyMintCap == 0) return; // unlimited
        if (block.timestamp >= windowStart + 1 days) {
            windowStart = block.timestamp;
            mintedInWindow = 0;
        }
        mintedInWindow += amount;
        require(mintedInWindow <= dailyMintCap, "daily mint cap");
    }
}
