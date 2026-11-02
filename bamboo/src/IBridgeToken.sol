// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IBridgeToken
/// @notice The ONLY surface bamboo needs from an issuer's token. The issuer keeps
///         their own token contract — proxy, upgradability, blacklist, pause, caps,
///         everything — and merely grants the bamboo gateway a minter/burner role.
///
///   - mint(to, amount):     callable by addresses the issuer authorized (gateway).
///   - burnFrom(from, amount):allowance-based (OZ ERC20Burnable style) — the user
///                            approves the gateway, the gateway burns on send().
///
/// Point the gateway at the issuer's PROXY address, so future logic upgrades are
/// transparent to bamboo as long as this interface + role grant remain.
interface IBridgeToken {
    function mint(address to, uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
}
