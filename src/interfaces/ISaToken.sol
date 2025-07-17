// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ISaToken
 * @dev Interface for the SaToken rebasing ERC20 token
 * @notice This interface defines all external functions and events for the SaToken contract
 */
interface ISaToken {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emitted when shares are minted
     * @param to Address receiving the shares
     * @param shares Number of shares minted
     * @param assets Number of underlying assets represented
     */
    event SharesMinted(address indexed to, uint256 shares, uint256 assets);

    /**
     * @dev Emitted when shares are burned
     * @param from Address burning the shares
     * @param shares Number of shares burned
     * @param assets Number of underlying assets returned
     */
    event SharesBurned(address indexed from, uint256 shares, uint256 assets);

    /**
     * @dev Emitted when the token rebases
     * @param newTotalAssets New total assets value
     */
    event Rebase(uint256 newTotalAssets);

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the internal share balance for an account
     * @param account Address to check shares for
     * @return Share balance
     */
    function sharesOf(address account) external view returns (uint256);

    /**
     * @dev Mint shares to user (lending protocol only)
     * @param to Address to mint shares to
     * @param assets Amount of underlying assets
     * @return shares Number of shares minted
     */
    function mint(address to, uint256 assets) external returns (uint256 shares);

    /**
     * @dev Burn shares from user (lending protocol only)
     * @param from Address to burn shares from
     * @param shares Number of shares to burn
     * @return assets Amount of underlying assets returned
     */
    function burn(address from, uint256 shares) external returns (uint256 assets);

    /**
     * @dev Update total assets (triggers rebase) (lending protocol only)
     * @param newTotalAssets New total assets value
     */
    function rebase(uint256 newTotalAssets) external;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Underlying asset address
     */
    function underlyingAsset() external view returns (address);

    /**
     * @dev Lending protocol address
     */
    function lendingProtocol() external view returns (address);

    /**
     * @dev Total shares outstanding
     */
    function totalShares() external view returns (uint256);

    /**
     * @dev Total underlying assets
     */
    function totalAssets() external view returns (uint256);
}
