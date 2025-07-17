// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ISaToken.sol";
/**
 * @title SaToken
 * @dev A rebasing ERC20 token that represents shares in the CrediFi lending protocol
 * @notice This contract implements a rebasing mechanism where token balances automatically
 * adjust based on the underlying asset value, ensuring fair distribution of protocol yields
 *
 * Key Features:
 * - Rebasing mechanism that adjusts token balances based on underlying asset value
 * - Share-based accounting for precise yield distribution
 * - Integration with the CrediFi protocol for minting/burning operations
 * - Standard ERC20 functionality with rebasing capabilities
 */

contract SaToken is ERC20, Ownable, ISaToken {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable underlyingAsset; // Address of the underlying asset (ETH, USDC, etc.)
    address public lendingProtocol; // Address of the CrediFi protocol contract

    uint256 public totalShares; // Total shares outstanding across all users
    uint256 public totalAssets; // Total underlying assets in the protocol

    // User share tracking
    mapping(address => uint256) private _shareBalances; // Share balances per user

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyLendingProtocol() {
        require(msg.sender == lendingProtocol, "Only lending protocol");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory name,
        string memory symbol,
        address _underlyingAsset,
        address _lendingProtocol
    )
        ERC20(name, symbol)
        Ownable(msg.sender)
    {
        underlyingAsset = _underlyingAsset;
        lendingProtocol = _lendingProtocol;
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the rebased token balance
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (totalShares == 0) return 0;
        return (_shareBalances[account] * totalAssets) / totalShares;
    }

    /**
     * @dev Returns the total rebased supply
     */
    function totalSupply() public view override returns (uint256) {
        return totalAssets;
    }

    /**
     * @dev Returns the internal share balance
     */
    function sharesOf(address account) public view returns (uint256) {
        return _shareBalances[account];
    }

    /**
     * @dev Mint shares to user
     */
    function mint(address to, uint256 assets) external onlyLendingProtocol returns (uint256 shares) {
        require(to != address(0), "Invalid address");
        require(assets > 0, "Invalid amount");

        // Calculate shares
        shares = totalShares == 0 ? assets : (assets * totalShares) / totalAssets;

        // Update balances
        _shareBalances[to] += shares;
        totalShares += shares;
        totalAssets += assets;

        emit SharesMinted(to, shares, assets);
        emit Transfer(address(0), to, assets);

        return shares;
    }

    /**
     * @dev Burn shares from user
     */
    function burn(address from, uint256 shares) external onlyLendingProtocol returns (uint256 assets) {
        require(from != address(0), "Invalid address");
        require(shares > 0, "Invalid shares");
        require(_shareBalances[from] >= shares, "Insufficient shares");

        // Calculate assets to return
        assets = (shares * totalAssets) / totalShares;

        // Update balances
        _shareBalances[from] -= shares;
        totalShares -= shares;
        totalAssets -= assets;

        emit SharesBurned(from, shares, assets);
        emit Transfer(from, address(0), assets);

        return assets;
    }

    /**
     * @dev Update total assets (triggers rebase)
     */
    function rebase(uint256 newTotalAssets) external onlyLendingProtocol {
        require(newTotalAssets >= totalAssets, "Cannot decrease assets");
        totalAssets = newTotalAssets;
        emit Rebase(newTotalAssets);
    }

    /**
     * @dev Transfer tokens (converts to shares internally)
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        _transferShares(msg.sender, to, amount);
        return true;
    }

    /**
     * @dev Transfer tokens with allowance
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transferShares(from, to, amount);
        return true;
    }

    /**
     * @dev Internal transfer function
     */
    function _transferShares(address from, address to, uint256 amount) internal {
        require(from != address(0), "Invalid from address");
        require(to != address(0), "Invalid to address");

        // Convert amount to shares
        uint256 shares = totalShares == 0 ? 0 : (amount * totalShares) / totalAssets;
        require(_shareBalances[from] >= shares, "Insufficient balance");

        // Update share balances
        _shareBalances[from] -= shares;
        _shareBalances[to] += shares;

        emit Transfer(from, to, amount);
    }
}
