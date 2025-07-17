// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SaToken } from "../SaToken.sol";

/**
 * @title ICrediFiProtocol
 * @dev Interface for the CrediFi lending protocol
 * @notice This interface defines all external functions, events, and structs for the CrediFi protocol
 */
interface ICrediFiProtocol {
    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Credit profile structure for users
     * @notice Packed for gas optimization - 8 slots total
     */
    struct CreditProfile {
        uint256 score; // Credit score (100-1000) - slot 0
        uint256 totalBorrowed; // Total borrowed amount (lifetime) - slot 1
        uint256 totalRepaid; // Total repaid amount (lifetime) - slot 2
        uint256 onTimePayments; // Number of on-time payments - slot 3
        uint256 latePayments; // Number of late payments - slot 4
        uint256 liquidatedPrincipal; // The principal that was repaid by liquidation - slot 5
        bool isActive; // Whether profile is active - slot 6
        bool isBlacklisted; // Whether user is blacklisted - slot 6
    }

    /**
     * @dev Borrow position structure
     * @notice Packed for gas optimization - 9 slots total
     */
    struct BorrowPosition {
        address borrowedAsset; // Asset that was borrowed - slot 0
        uint256 borrowedAmount; // Amount borrowed - slot 1
        uint256 interestRate; // Interest rate at time of borrowing - slot 2
        uint256 accruedInterest; // Interest accrued so far - slot 3
        address collateralAsset; // Collateral asset address - slot 4
        uint256 collateralAmount; // Collateral amount - slot 5
        uint256 borrowTime; // When the borrow occurred - slot 6
        uint256 dueDate; // Due date for repayment - slot 7
        bool isActive; // Whether position is active - slot 8
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emitted when a user deposits assets
     * @param user Address of the depositor
     * @param asset Address of the deposited asset
     * @param amount Amount deposited
     * @param shares Shares minted
     */
    event Deposit(address indexed user, address indexed asset, uint256 amount, uint256 shares);

    /**
     * @dev Emitted when a user withdraws assets
     * @param user Address of the withdrawer
     * @param asset Address of the withdrawn asset
     * @param amount Amount withdrawn
     * @param shares Shares burned
     */
    event Withdraw(address indexed user, address indexed asset, uint256 amount, uint256 shares);

    /**
     * @dev Emitted when interest is distributed to lenders
     * @param asset Address of the asset
     * @param amount Amount of interest distributed
     */
    event InterestDistributed(address indexed asset, uint256 amount);

    /**
     * @dev Emitted when a credit profile is created
     * @param user Address of the user
     * @param initialScore Initial credit score
     */
    event CreditProfileCreated(address indexed user, uint256 initialScore);

    /**
     * @dev Emitted when a user borrows assets
     * @param user Address of the borrower
     * @param borrowAsset Address of the borrowed asset
     * @param borrowAmount Amount borrowed
     * @param collateralAsset Address of the collateral asset
     * @param collateralAmount Amount of collateral
     * @param interestRate Interest rate applied
     * @param dueDate Due date for repayment
     */
    event Borrow(
        address indexed user,
        address indexed borrowAsset,
        uint256 borrowAmount,
        address collateralAsset,
        uint256 collateralAmount,
        uint256 interestRate,
        uint256 dueDate
    );

    /**
     * @dev Emitted when a user repays a loan
     * @param user Address of the borrower
     * @param positionIndex Index of the position being repaid
     * @param principalRepaid Amount of principal repaid
     * @param interestPaid Amount of interest paid
     * @param isFullyRepaid Whether the loan was fully repaid
     */
    event Repay(
        address indexed user, uint256 positionIndex, uint256 principalRepaid, uint256 interestPaid, bool isFullyRepaid
    );

    /**
     * @dev Emitted when a user's credit score is updated
     * @param user Address of the user
     * @param oldScore Previous credit score
     * @param newScore New credit score
     */
    event CreditScoreUpdated(address indexed user, uint256 oldScore, uint256 newScore);

    /**
     * @dev Emitted when a position is liquidated
     * @param user Address of the borrower
     * @param positionIndex Index of the liquidated position
     * @param liquidator Address of the liquidator
     */
    event Liquidation(address indexed user, uint256 positionIndex, address indexed liquidator);

    /**
     * @dev Emitted when a new asset is added to the protocol
     * @param asset Address of the asset
     * @param saToken Address of the corresponding saToken
     * @param borrowLimit Maximum borrow limit for the asset
     */
    event AssetAdded(address indexed asset, address indexed saToken, uint256 borrowLimit);

    /**
     * @dev Emitted when an asset is removed from the protocol
     * @param asset Address of the removed asset
     */
    event AssetRemoved(address indexed asset);

    /**
     * @dev Emitted when a borrow limit is updated
     * @param asset Address of the asset
     * @param newLimit New borrow limit
     */
    event BorrowLimitUpdated(address indexed asset, uint256 newLimit);

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deposit ETH or ERC20 tokens to receive saTokens
     * @param asset ETH_ADDRESS for ETH, token address for ERC20
     * @param amount Amount for ERC20 (0 for ETH, use msg.value)
     */
    function deposit(address asset, uint256 amount) external payable;

    /**
     * @dev Withdraw ETH or ERC20 tokens by burning saTokens
     * @param asset ETH_ADDRESS for ETH, token address for ERC20
     * @param shares Amount of shares to burn
     */
    function withdraw(address asset, uint256 shares) external;

    /*//////////////////////////////////////////////////////////////
                            ASSET MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Add a new supported asset with its saToken
     * @param asset Address of the asset (use address(0) for ETH)
     * @param name Name for the saToken
     * @param symbol Symbol for the saToken
     * @param borrowLimit Maximum amount that can be borrowed for this asset
     */
    function addSupportedAsset(address asset, string memory name, string memory symbol, uint256 borrowLimit) external;

    /**
     * @dev Remove a supported asset (only if no active positions)
     * @param asset Address of the asset to remove
     */
    function removeSupportedAsset(address asset) external;

    /**
     * @dev Update borrow limit for an existing asset
     * @param asset Address of the asset
     * @param newLimit New borrow limit
     */
    function updateBorrowLimit(address asset, uint256 newLimit) external;

    /*//////////////////////////////////////////////////////////////
                            CREDIT SYSTEM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get the required collateral ratio for a user based on their credit score
     * @param user Address of the user
     * @return Required collateral ratio in basis points
     */
    function getCollateralRatio(address user) external view returns (uint256);

    /**
     * @dev Get the borrow interest rate for a user based on their credit score
     * @param user Address of the user
     * @return Interest rate in basis points
     */
    function getBorrowInterestRate(address user) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            BORROWING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Borrow assets by providing collateral
     * @param borrowAsset Asset to borrow
     * @param borrowAmount Amount to borrow
     * @param collateralAsset Asset to use as collateral
     * @param collateralAmount Amount of collateral
     */
    function borrow(
        address borrowAsset,
        uint256 borrowAmount,
        address collateralAsset,
        uint256 collateralAmount
    )
        external
        payable;

    /**
     * @dev Repay a borrow position
     * @param positionIndex Index of the position to repay
     * @param repayAmount Amount to repay
     */
    function repay(uint256 positionIndex, uint256 repayAmount) external payable;

    /**
     * @dev Liquidate an overdue position
     * @param borrower Address of the borrower
     * @param positionIndex Index of the position to liquidate
     */
    function liquidate(address borrower, uint256 positionIndex) external payable;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get available liquidity for an asset
     * @param asset Address of the asset
     * @return Available liquidity
     */
    function getAvailableLiquidity(address asset) external view returns (uint256);

    /**
     * @dev Get all borrow positions for a user
     * @param user Address of the user
     * @return Array of borrow positions
     */
    function getBorrowPositions(address user) external view returns (BorrowPosition[] memory);

    /**
     * @dev Get active borrow position indices for a user
     * @param user Address of the user
     * @return Array of active position indices
     */
    function getActiveBorrowPositions(address user) external view returns (uint256[] memory);

    /**
     * @dev Get credit profile for a user
     * @param user Address of the user
     * @return Credit profile
     */
    function getCreditProfile(address user) external view returns (CreditProfile memory);

    /**
     * @dev Check if a user can borrow
     * @param user Address of the user
     * @return Whether the user can borrow
     */
    function canBorrow(address user) external view returns (bool);

    /**
     * @dev Get utilization rate for an asset
     * @param asset Address of the asset
     * @return Utilization rate in basis points
     */
    function getUtilizationRate(address asset) external view returns (uint256);

    /**
     * @dev Get debt information for a specific position
     * @param user Address of the user
     * @param positionIndex Index of the position
     * @return principal Principal amount
     * @return interest Accrued interest
     * @return totalDebt Total debt (principal + interest)
     */
    function getPositionDebt(
        address user,
        uint256 positionIndex
    )
        external
        view
        returns (uint256 principal, uint256 interest, uint256 totalDebt);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Set borrow limit for an asset (owner only)
     * @param asset Address of the asset
     * @param newLimit New borrow limit
     */
    function setBorrowLimit(address asset, uint256 newLimit) external;

    /**
     * @dev Set global borrow limit (owner only)
     * @param newLimit New global borrow limit
     */
    function setGlobalBorrowLimit(uint256 newLimit) external;

    /**
     * @dev Withdraw accumulated protocol fees (owner only)
     * @param asset Address of the asset
     */
    function withdrawProtocolFees(address asset) external;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev ETH address constant
     */
    function ETH_ADDRESS() external view returns (address);

    /**
     * @dev USDC token address
     */
    function USDC() external view returns (address);

    /**
     * @dev MATIC token address
     */
    function MATIC() external view returns (address);

    /**
     * @dev Total reserves for each asset
     */
    function totalReserves(address asset) external view returns (uint256);

    /**
     * @dev Total borrowed for each asset
     */
    function totalBorrowed(address asset) external view returns (uint256);

    /**
     * @dev Accumulated interest for each asset
     */
    function accumulatedInterest(address asset) external view returns (uint256);

    /**
     * @dev SaToken mapping for each asset
     */
    function saTokens(address asset) external view returns (SaToken);

    /**
     * @dev Whether an asset is supported
     */
    function supportedAssets(address asset) external view returns (bool);

    /**
     * @dev Credit profile for each user
     */
    function creditProfiles(address user)
        external
        view
        returns (
            uint256 score,
            uint256 totalBorrowed,
            uint256 totalRepaid,
            uint256 onTimePayments,
            uint256 latePayments,
            uint256 liquidatedPrincipal,
            bool isActive,
            bool isBlacklisted
        );

    /**
     * @dev Borrow positions for each user
     */
    function borrowPositions(
        address user,
        uint256 index
    )
        external
        view
        returns (
            address borrowedAsset,
            uint256 borrowedAmount,
            uint256 interestRate,
            uint256 accruedInterest,
            address collateralAsset,
            uint256 collateralAmount,
            uint256 borrowTime,
            uint256 dueDate,
            bool isActive
        );

    /**
     * @dev Maximum borrow limit for each asset
     */
    function maxBorrowLimit(address asset) external view returns (uint256);

    /**
     * @dev Global borrow limit
     */
    function globalBorrowLimit() external view returns (uint256);
}
