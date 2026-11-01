// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Lab stand-in for USDC — the SAME freeze power as USDT, but reached through a proxy.
/// @dev The real USDC is an upgradeable ERC1967 proxy whose logic Circle can swap out. The
///      point of this file is the contrast with MockUSDT, which has no proxy:
///        - USDT: freeze functions are baked into the one deployed contract.
///        - USDC: freeze functions live in the LOGIC contract, called THROUGH the proxy.
///      Either way a single issuer key can freeze — proxy or not is irrelevant to the victim;
///      what matters is that an owner exists who can call `blacklist`. One real difference is
///      kept: USDC only FREEZES, it has no `destroyBlackFunds`-style seize.
contract MockUSDCLogic is ERC20 {
    /// @notice The issuer (Circle). Lives in PROXY storage, set by initialize (not the constructor).
    address public blacklister;
    mapping(address => bool) public isBlacklisted;
    bool private _initialized;

    event Blacklisted(address indexed _account);
    event UnBlacklisted(address indexed _account);

    /// @dev Name/symbol are overridden as constants below, so the constructor sets no proxy
    ///      state — everything the proxy needs comes from initialize().
    constructor() ERC20("", "") {}

    function name() public pure override returns (string memory) {
        return "Mock USD Coin";
    }

    function symbol() public pure override returns (string memory) {
        return "USDC";
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Runs once, in the proxy's context, to set the issuer.
    function initialize(address _blacklister) external {
        require(!_initialized, "USDC: initialized");
        _initialized = true;
        blacklister = _blacklister;
    }

    modifier onlyBlacklister() {
        require(msg.sender == blacklister, "USDC: not issuer");
        _;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    /// @notice Freeze an address: it can neither send nor receive USDC until unblacklisted.
    function blacklist(address _account) external onlyBlacklister {
        isBlacklisted[_account] = true;
        emit Blacklisted(_account);
    }

    function unBlacklist(address _account) external onlyBlacklister {
        isBlacklisted[_account] = false;
        emit UnBlacklisted(_account);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            require(!isBlacklisted[from], "USDC: sender frozen");
            require(!isBlacklisted[to], "USDC: recipient frozen");
        }
        super._update(from, to, value);
    }
}

/// @notice The deployable USDC: an ERC1967 proxy that deploys its own logic and initializes it.
/// @dev Interact with it by casting the proxy address to MockUSDCLogic, e.g.
///      `MockUSDCLogic usdc = MockUSDCLogic(address(new MockUSDC(circle)));`
///      This is what makes USDC a proxy in the lab, where USDT is a plain contract.
contract MockUSDC is ERC1967Proxy {
    constructor(address _blacklister)
        ERC1967Proxy(address(new MockUSDCLogic()), abi.encodeCall(MockUSDCLogic.initialize, (_blacklister)))
    {}
}
