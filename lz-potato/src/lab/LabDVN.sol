// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILayerZeroDVN} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/interfaces/ILayerZeroDVN.sol";

interface IReceiveUln302 {
    function verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations) external;
}

/// @notice Workshop DVN: free to assign, and an off-chain signer (owner) attests packets by calling verify().
/// @dev Lab only. A production DVN checks quorum signatures, fees and per-path permissions.
contract LabDVN is ILayerZeroDVN, Ownable {
    event JobAssigned(uint32 dstEid, bytes packetHeader, bytes32 payloadHash, uint64 confirmations, address sender);

    constructor(address _signer) Ownable(_signer) {}

    function assignJob(AssignJobParam calldata _param, bytes calldata) external payable returns (uint256) {
        emit JobAssigned(_param.dstEid, _param.packetHeader, _param.payloadHash, _param.confirmations, _param.sender);
        return 0;
    }

    function getFee(uint32, uint64, address, bytes calldata) external pure returns (uint256) {
        return 0;
    }

    /// @notice ReceiveUln302 records the attestation under msg.sender, so it must be this contract calling.
    function verify(address _receiveLib, bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations)
        external
        onlyOwner
    {
        IReceiveUln302(_receiveLib).verify(_packetHeader, _payloadHash, _confirmations);
    }
}
