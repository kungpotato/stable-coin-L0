// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IOAppComposer} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

/// @notice Topic 7: "bridge USDC and deposit it in the vault" in one user action.
/// The OFT credits USDC.lz to this contract in lzReceive; the executor then calls lzCompose in a SEPARATE
/// transaction, and this contract deposits for the beneficiary named in the compose message.
/// Between the two, the tokens sit here, so:
///   - only the endpoint may call lzCompose, and only for compose messages queued by our UsdcOFT
///     (any OApp on the endpoint can queue a compose to us, with any amount in it)
///   - a failed deposit refunds the beneficiary instead of reverting: a reverting lzCompose keeps the tokens here
///   - if even the refund fails (e.g. blacklisted beneficiary) the amount is parked for the owner, never lost
contract UsdcDepositComposer is IOAppComposer, Ownable {
    address public immutable endpoint;
    address public immutable oft; // UsdcOFT: the only allowed _from, and the token held
    IERC4626 public immutable vault;
    mapping(address => uint256) public parked;
    // = OFTComposeMsgCodec.COMPOSE_FROM_OFFSET, where composeFrom (bytes 44..76) ENDS and the app payload starts
    uint256 private constant PAYLOAD_OFFSET = 76;

    event Deposited(bytes32 indexed guid, address indexed beneficiary, uint256 assets, uint256 shares);
    event Refunded(bytes32 indexed guid, address indexed beneficiary, uint256 amount);
    event Parked(bytes32 indexed guid, address indexed beneficiary, uint256 amount);

    error OnlyEndpoint(address caller);
    error UntrustedOApp(address from);

    constructor(address _endpoint, address _oft, IERC4626 _vault, address _owner) Ownable(_owner) {
        endpoint = _endpoint;
        oft = _oft;
        vault = _vault;
        IERC20(_oft).approve(address(_vault), type(uint256).max);
    }

    function lzCompose(address _from, bytes32 _guid, bytes calldata _message, address, bytes calldata)
        external
        payable
        override
    {
        if (msg.sender != endpoint) revert OnlyEndpoint(msg.sender);
        if (_from != oft) revert UntrustedOApp(_from);

        uint256 amount = OFTComposeMsgCodec.amountLD(_message);
        // _message = [nonce 0..8][srcEid 8..12][amountLD 12..44][composeFrom 44..76][app payload 76..];
        // our app payload is abi.encode(beneficiary)
        address beneficiary = abi.decode(_message[PAYLOAD_OFFSET:], (address));

        try vault.deposit(amount, beneficiary) returns (uint256 shares) {
            emit Deposited(_guid, beneficiary, amount, shares);
        } catch {
            try IERC20(oft).transfer(beneficiary, amount) returns (bool ok) {
                if (ok) {
                    emit Refunded(_guid, beneficiary, amount);
                    return;
                }
            } catch {}
            parked[beneficiary] += amount;
            emit Parked(_guid, beneficiary, amount);
        }
    }

    /// @notice Pay out a parked amount once the reason is resolved (owner decision).
    function releaseParked(address _beneficiary, address _to) external onlyOwner {
        uint256 amount = parked[_beneficiary];
        parked[_beneficiary] = 0;
        IERC20(oft).transfer(_to, amount);
    }
}
