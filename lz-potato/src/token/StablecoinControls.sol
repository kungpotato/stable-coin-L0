// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BridgeControls} from "./BridgeControls.sol";

/// @notice Controls of every USDC bridge leg (ADR 0003, ADR 0005, ADR 0006): BridgeControls (pause, outbound rate
/// limit, inbound mint cap) plus a blacklist run by a separate blacklister role. A blacklisted account can neither
/// bridge out nor receive: what arrives for it is QUARANTINED, not reverted (a reverting lzReceive would strand the
/// message forever), and released funds never go to a still-blacklisted payee.
abstract contract StablecoinControls is BridgeControls {
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

    function _checkSender(address _from) internal view override {
        if (isBlacklisted[_from]) revert AccountBlacklisted(_from);
    }

    function _mustHold(address _to) internal view override returns (bool) {
        return isBlacklisted[_to];
    }

    function _checkPayee(address _payee) internal view override {
        if (isBlacklisted[_payee]) revert AccountBlacklisted(_payee);
    }
}
