// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ILayerZeroExecutor} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/interfaces/ILayerZeroExecutor.sol";

/// @notice Workshop executor: charges nothing. Delivery is done off-chain by calling EndpointV2.lzReceive,
/// which is permissionless, so this contract only has to satisfy the send-side fee interface.
contract LabExecutor is ILayerZeroExecutor {
    event JobAssigned(uint32 dstEid, address sender, uint256 calldataSize, bytes options);

    function assignJob(uint32 _dstEid, address _sender, uint256 _calldataSize, bytes calldata _options)
        external
        returns (uint256)
    {
        emit JobAssigned(_dstEid, _sender, _calldataSize, _options);
        return 0;
    }

    function getFee(uint32, address, uint256, bytes calldata) external pure returns (uint256) {
        return 0;
    }
}
