// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {OFTAdapter} from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";

// Topic 3 (security): a disposable token pair for DVN attack drills, so POTATO and USDC.lz stay clean.
// A forged message consumes the path's next nonce, which breaks the real path afterwards.

/// @notice Home token (anvil): owner mints.
contract DemoToken is ERC20, Ownable {
    constructor(string memory _symbol, address _owner) ERC20(string.concat("Demo ", _symbol), _symbol) Ownable(_owner) {}

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}

/// @notice Locks DemoToken on the home chain.
contract DemoAdapter is OFTAdapter {
    constructor(address _token, address _endpoint, address _owner) OFTAdapter(_token, _endpoint, _owner) Ownable(_owner) {}
}

/// @notice Bridged demo token on the other chains: minted only by verified messages.
contract DemoOFT is OFT {
    constructor(string memory _symbol, address _endpoint, address _owner)
        OFT(string.concat("Demo ", _symbol, " (LayerZero)"), string.concat(_symbol, ".lz"), _endpoint, _owner)
        Ownable(_owner)
    {}
}
