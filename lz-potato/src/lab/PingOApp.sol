// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/// @notice Smallest useful OApp: send a string, remember the last one received.
contract PingOApp is OApp {
    using OptionsBuilder for bytes;

    uint128 public constant RECEIVE_GAS = 100_000;

    string public lastMessage;
    uint32 public lastSrcEid;
    uint256 public received;

    event Pinged(uint32 dstEid, bytes32 guid, string message);
    event Ponged(uint32 srcEid, bytes32 guid, string message);

    constructor(address _endpoint, address _owner) OApp(_endpoint, _owner) Ownable(_owner) {}

    function options() public pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(RECEIVE_GAS, 0);
    }

    function quote(uint32 _dstEid, string calldata _message) external view returns (MessagingFee memory) {
        return _quote(_dstEid, abi.encode(_message), options(), false);
    }

    function ping(uint32 _dstEid, string calldata _message) external payable returns (MessagingReceipt memory r) {
        r = _lzSend(_dstEid, abi.encode(_message), options(), MessagingFee(msg.value, 0), payable(msg.sender));
        emit Pinged(_dstEid, r.guid, _message);
    }

    function _lzReceive(Origin calldata _origin, bytes32 _guid, bytes calldata _message, address, bytes calldata)
        internal
        override
    {
        lastMessage = abi.decode(_message, (string));
        lastSrcEid = _origin.srcEid;
        received++;
        emit Ponged(_origin.srcEid, _guid, lastMessage);
    }
}
