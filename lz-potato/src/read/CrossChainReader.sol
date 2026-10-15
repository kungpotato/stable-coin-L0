// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OAppRead} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppRead.sol";
import {Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ReadCodecV1, EVMCallRequestV1} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";

/// @notice Topic 7 (lzRead): read a uint256 view on another chain, delivered back here by read DVNs.
/// Stablecoin use: a spoke chain can check the home chain's lockbox balance on-chain (e.g. before minting),
/// instead of trusting an off-chain monitor. Workshop target: Ping.received() on Sepolia.
contract CrossChainReader is OAppRead {
    using OptionsBuilder for bytes;

    uint32 public constant READ_CHANNEL = 4294967295;
    uint16 internal constant READ_TYPE = 1;
    uint16 public constant TARGET_CONFIRMATIONS = 15;

    uint128 public receiveGas = 200_000; // gas for _lzReceive here; owner-tunable (topic 4 lesson)
    uint256 public lastValue;
    uint32 public lastTargetEid;
    address public lastTarget;
    uint256 public reads;

    event ReadRequested(bytes32 indexed guid, uint32 targetEid, address target);
    event ReadAnswered(bytes32 indexed guid, uint256 value);

    constructor(address _endpoint, address _owner) OAppRead(_endpoint, _owner) Ownable(_owner) {}

    function setReceiveGas(uint128 _gas) external onlyOwner {
        receiveGas = _gas;
    }

    /// @dev Read `_callData` on `_target` of chain `_targetEid` at this moment's timestamp, after 15 confirmations there.
    function command(uint32 _targetEid, address _target, bytes calldata _callData) public view returns (bytes memory) {
        EVMCallRequestV1[] memory req = new EVMCallRequestV1[](1);
        req[0] = EVMCallRequestV1({
            appRequestLabel: READ_TYPE,
            targetEid: _targetEid,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: TARGET_CONFIRMATIONS,
            to: _target,
            callData: _callData
        });
        return ReadCodecV1.encode(0, req);
    }

    function options() public view returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReadOption(receiveGas, 32, 0); // response: one uint256
    }

    function quote(uint32 _targetEid, address _target, bytes calldata _callData) external view returns (MessagingFee memory) {
        return _quote(READ_CHANNEL, command(_targetEid, _target, _callData), options(), false);
    }

    function read(uint32 _targetEid, address _target, bytes calldata _callData) external payable returns (MessagingReceipt memory r) {
        r = _lzSend(READ_CHANNEL, command(_targetEid, _target, _callData), options(), MessagingFee(msg.value, 0), payable(msg.sender));
        lastTargetEid = _targetEid;
        lastTarget = _target;
        emit ReadRequested(r.guid, _targetEid, _target);
    }

    /// @dev The read DVNs' answer: the view's raw return data.
    function _lzReceive(Origin calldata, bytes32 _guid, bytes calldata _message, address, bytes calldata) internal override {
        lastValue = abi.decode(_message, (uint256));
        reads++;
        emit ReadAnswered(_guid, lastValue);
    }
}
