// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {
    ERC1967Utils
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/// @notice Lab stand-in for USDC — the SAME freeze power as USDT, but reached through a proxy.
/// @dev The real USDC is an upgradeable proxy (FiatTokenProxy) whose logic Circle can swap out.
///      The point of this file is the contrast with MockUSDT, which has no proxy:
///        - USDT: freeze functions are baked into the one deployed contract.
///        - USDC: freeze functions live in the LOGIC contract, called THROUGH the proxy, and the
///          logic can be UPGRADED without changing the token's address or moving its balances.
///      Two real traits are kept:
///        - USDC V1 only FREEZES — it has no seize/burn. That is why a thief's USDC just sits
///          frozen forever (the live Circle dispute).
///        - If Circle WANTED seize, it could upgrade the logic in place. MockUSDCLogicV2 shows
///          exactly that: same proxy address, same balances, but now destroyBlackFunds exists.

/// @dev USDC V1: freeze only. No seize, no issuer-side recovery — matches real Circle today.
contract MockUSDCLogic is ERC20 {
    /// @notice The issuer's blacklister role (Circle). Lives in PROXY storage via initialize.
    address public blacklister;
    mapping(address => bool) public isBlacklisted;
    bool private _initialized;

    event Blacklisted(address indexed _account);
    event UnBlacklisted(address indexed _account);

    /// @dev Name/symbol are overridden as constants below, so the constructor sets no proxy state.
    constructor() ERC20("", "") {}

    function name() public pure virtual override returns (string memory) {
        return "Mock USD Coin";
    }

    function symbol() public pure virtual override returns (string memory) {
        return "USDC";
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Runs once, in the proxy's context, to set the blacklister.
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

    function blacklist(address _account) external onlyBlacklister {
        isBlacklisted[_account] = true;
        emit Blacklisted(_account);
    }

    function unBlacklist(address _account) external onlyBlacklister {
        isBlacklisted[_account] = false;
        emit UnBlacklisted(_account);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (from != address(0) && to != address(0)) {
            require(!isBlacklisted[from], "USDC: sender frozen");
            require(!isBlacklisted[to], "USDC: recipient frozen");
        }
        super._update(from, to, value);
    }
}

/// @notice USDC V2 — a hypothetical upgrade where Circle ADDS seize, the power it refuses to add
///         in reality. Deployed as a new logic contract and swapped in via upgradeTo; the proxy
///         address and all balances are untouched. Storage layout is inherited unchanged, so the
///         upgrade is safe (only new functions are added, no new/reordered state).
contract MockUSDCLogicV2 is MockUSDCLogic {
    event DestroyedBlackFunds(address indexed _account, uint256 _balance);

    /// @dev A version tag so a test can prove the upgrade actually took effect.
    function version() external pure returns (uint256) {
        return 2;
    }

    /// @notice The seize power USDC V1 lacks: burn a frozen address's balance, reduce supply.
    function destroyBlackFunds(address _account) external onlyBlacklister {
        require(isBlacklisted[_account], "USDC: not frozen");
        uint256 dirtyFunds = balanceOf(_account);
        _burn(_account, dirtyFunds);
        emit DestroyedBlackFunds(_account, dirtyFunds);
    }

    /// @notice The remint half of recovery: issue replacement supply to the issuer, to hand to the
    ///         victim. With destroyBlackFunds + issue, upgraded USDC matches USDT's full
    ///         burn-and-remint — the exact capability critics say Circle could add but won't.
    function issue(uint256 _amount) external onlyBlacklister {
        _mint(blacklister, _amount);
    }
}

/// @notice The deployable USDC: a transparent admin proxy, modelled on the real FiatTokenProxy.
/// @dev Interact with it by casting the proxy address to the logic ABI, e.g.
///      `MockUSDCLogic usdc = MockUSDCLogic(address(new MockUSDC(admin, circle)));`
///
///      TWO separate roles, exactly like real USDC:
///        - admin  (the key passed as _admin): can ONLY upgrade/changeAdmin via this proxy.
///        - blacklister (_blacklister): the logic role that freezes — a DIFFERENT key.
///      The `ifAdmin` gate makes this "transparent": a call from the admin runs the proxy's own
///      admin function; a call from anyone else is delegated to the logic. So the admin key must
///      NOT also be the blacklister — as admin, its blacklist()/transfer() calls would be trapped
///      by the proxy instead of reaching the logic. Keep ADMIN and ISS as separate keys.
contract MockUSDC is Proxy {
    constructor(address _admin, address _blacklister) {
        ERC1967Utils.upgradeToAndCall(
            address(new MockUSDCLogic()),
            abi.encodeCall(MockUSDCLogic.initialize, (_blacklister))
        );
        ERC1967Utils.changeAdmin(_admin);
    }

    modifier ifAdmin() {
        if (msg.sender == ERC1967Utils.getAdmin()) {
            _;
        } else {
            _fallback(); // non-admin: behave as a plain proxy and delegate to the logic
        }
    }

    /// @notice Current admin (only the admin can read it here; others get delegated).
    function admin() external ifAdmin returns (address) {
        return ERC1967Utils.getAdmin();
    }

    /// @notice Current logic address behind the proxy.
    function implementation() external ifAdmin returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @notice Hand the admin role to a new key.
    function changeAdmin(address newAdmin) external ifAdmin {
        ERC1967Utils.changeAdmin(newAdmin);
    }

    /// @notice Swap the logic WITHOUT changing the token address or its balances.
    function upgradeTo(address newImplementation) external ifAdmin {
        ERC1967Utils.upgradeToAndCall(newImplementation, "");
    }

    /// @notice Upgrade and run an initializer in the same tx.
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable ifAdmin {
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }

    /// @dev Proxy only defines a payable fallback; add receive so plain-ETH sends also route to
    ///      the logic (and to silence solc's missing-receive warning).
    receive() external payable {
        _fallback();
    }

    function _implementation() internal view override returns (address) {
        return ERC1967Utils.getImplementation();
    }
}
