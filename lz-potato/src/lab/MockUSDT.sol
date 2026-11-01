// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Lab stand-in for USDT (6 decimals, anyone can mint).
/// @dev Mirrors real Tether's "help after a hack": there is NO proxy. The freeze powers are
///      baked straight into this one contract and only the issuer (owner) can call them —
///      exactly how `0xdAC17...ec7` works on mainnet. This is the stablecoin layer that
///      actually limited the Binance 14 loss: once the thief's address is blacklisted the
///      stolen USDT can no longer move, and `destroyBlackFunds` can even burn it on the spot.
contract MockUSDT is ERC20 {
    /// @notice The issuer (Tether). Only this address can freeze/seize.
    address public owner;
    /// @notice Addresses the issuer has frozen. Same name Tether uses on-chain.
    mapping(address => bool) public isBlackListed;

    event AddedBlackList(address indexed _user);
    event RemovedBlackList(address indexed _user);
    event DestroyedBlackFunds(address indexed _blackListedUser, uint256 _balance);

    constructor() ERC20("Mock Tether", "USDT") {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "USDT: not issuer");
        _;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    /// @notice Issuer mints fresh supply to its own treasury (owner). This is the real Tether
    ///         `issue` primitive — the second half of burn-and-remint recovery: after
    ///         destroyBlackFunds burns a thief's stolen USDT, the issuer issues replacement
    ///         tokens and (off-chain, usually under a court order) sends them to the victim.
    /// @dev Replacing burned tokens is possible only because the issuer controls supply; a burned
    ///      ETH balance can never be re-minted by anyone.
    function issue(uint256 _amount) external onlyOwner {
        _mint(owner, _amount);
    }

    /// @notice Freeze an address: it can neither send nor receive USDT until removed.
    function addBlackList(address _user) external onlyOwner {
        isBlackListed[_user] = true;
        emit AddedBlackList(_user);
    }

    function removeBlackList(address _user) external onlyOwner {
        isBlackListed[_user] = false;
        emit RemovedBlackList(_user);
    }

    /// @notice Seize: burn a frozen address's entire balance (reduces totalSupply).
    /// @dev This is the extra power USDT has that USDC does not — the issuer can destroy
    ///      stolen funds, not just freeze them.
    function destroyBlackFunds(address _blackListedUser) external onlyOwner {
        require(isBlackListed[_blackListedUser], "USDT: not frozen");
        uint256 dirtyFunds = balanceOf(_blackListedUser);
        _burn(_blackListedUser, dirtyFunds);
        emit DestroyedBlackFunds(_blackListedUser, dirtyFunds);
    }

    /// @dev Block any transfer touching a frozen address; mint/burn (from/to == 0) stay open
    ///      so the issuer can still seize via destroyBlackFunds.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            require(!isBlackListed[from], "USDT: sender frozen");
            require(!isBlackListed[to], "USDT: recipient frozen");
        }
        super._update(from, to, value);
    }
}
