// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./SaToken.sol";

/**
 * @title CrediFiProtocol
 * @dev Improved CrediFi protocol with proper credit system, borrowing, and interest distribution
 */
contract CrediFiProtocol is Ownable, ReentrancyGuard, Pausable {

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    address public constant ETH_ADDRESS = address(0);
    address public immutable USDC;
    address public immutable MATIC;
    
    SaToken public saETH;
    SaToken public saUSDC;
    SaToken public saMATIC;
    
    mapping(address => uint256) public totalReserves;
    mapping(address => uint256) public totalBorrowed;
    mapping(address => uint256) public accumulatedInterest;
    
    uint256 public constant BASE_INTEREST_RATE = 500; // 5% base rate
    uint256 public constant CREDIT_DISCOUNT_RATE = 10; // 0.1% discount per 100 credit score points
    uint256 public constant LATE_PENALTY_RATE = 1000; // 10% penalty rate
    
    // Credit system variables
    struct CreditProfile {
        uint256 score;              // Credit score (100-1000)
        uint256 totalBorrowed;      // Total borrowed amount (lifetime)
        uint256 totalRepaid;        // Total repaid amount (lifetime)
        uint256 onTimePayments;     // Number of on-time payments
        uint256 latePayments;       // Number of late payments
        uint256 liquidatedPrincipal;    // The principal that was repaid by liquidation
        bool isActive;              // Whether profile is active
        bool isBlacklisted;         // Whether user is blacklisted
    }
    
    struct BorrowPosition {
        address borrowedAsset;      // Asset that was borrowed
        uint256 borrowedAmount;     // Amount borrowed
        uint256 interestRate;       // Interest rate at time of borrowing
        uint256 accruedInterest;    // Interest accrued so far
        address collateralAsset;    // Collateral asset address
        uint256 collateralAmount;   // Collateral amount
        uint256 borrowTime;         // When the borrow occurred
        uint256 dueDate;            // Due date for repayment
        bool isActive;              // Whether position is active
    }
    
    mapping(address => CreditProfile) public creditProfiles;
    mapping(address => BorrowPosition[]) public borrowPositions;
    
    uint256 public constant DEFAULT_CREDIT_SCORE = 300;
    uint256 public constant MIN_CREDIT_SCORE = 100;
    uint256 public constant MAX_CREDIT_SCORE = 1000;
    uint256 public constant LOAN_DURATION = 30 days;
    uint256 public constant LIQUIDATION_THRESHOLD = 95; // 95% of collateral value
    uint256 public constant PROTOCOL_FEE = 50; // 0.5% protocol fee
    
    mapping(address => uint256) public maxBorrowLimit; // Per-asset borrow limits
    uint256 public globalBorrowLimit = 10000000 * 10**6; // 10M USDC equivalent
    
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event Deposit(address indexed user, address indexed asset, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, address indexed asset, uint256 amount, uint256 shares);
    event InterestDistributed(address indexed asset, uint256 amount);
    event CreditProfileCreated(address indexed user, uint256 initialScore);
    event Borrow(
        address indexed user, 
        address indexed borrowAsset, 
        uint256 borrowAmount, 
        address collateralAsset,
        uint256 collateralAmount, 
        uint256 interestRate,
        uint256 dueDate
    );
    event Repay(
        address indexed user, 
        uint256 positionIndex, 
        uint256 principalRepaid,
        uint256 interestPaid,
        bool isFullyRepaid
    );
    event CreditScoreUpdated(address indexed user, uint256 oldScore, uint256 newScore);
    event Liquidation(address indexed user, uint256 positionIndex, address indexed liquidator);
    event BorrowLimitUpdated(address indexed asset, uint256 newLimit);
    
    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier notBlacklisted() {
        require(!creditProfiles[msg.sender].isBlacklisted, "User is blacklisted");
        _;
    }
    
    modifier validAsset(address asset) {
        require(
            asset == ETH_ADDRESS || asset == USDC || asset == MATIC,
            "Unsupported asset"
        );
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address _usdc, address _matic) Ownable(msg.sender) {
        USDC = _usdc;
        MATIC = _matic;
        
        saETH = new SaToken("Share ETH", "saETH", ETH_ADDRESS, address(this));
        saUSDC = new SaToken("Share USDC", "saUSDC", USDC, address(this));
        saMATIC = new SaToken("Share MATIC", "saMATIC", MATIC, address(this));
        
        maxBorrowLimit[ETH_ADDRESS] = 1000 ether;
        maxBorrowLimit[USDC] = 5000000 * 10**6; // 5M USDC
        maxBorrowLimit[MATIC] = 3000000 * 10**18; // 3M MATIC
    }
    
    /*//////////////////////////////////////////////////////////////
                            DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function depositETH() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Amount must be greater than 0");
        
        uint256 shares = saETH.mint(msg.sender, msg.value);
        totalReserves[ETH_ADDRESS] += msg.value;
        
        emit Deposit(msg.sender, ETH_ADDRESS, msg.value, shares);
    }
    
    function depositUSDC(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        
        ERC20(USDC).transferFrom(msg.sender, address(this), amount);
        
        uint256 shares = saUSDC.mint(msg.sender, amount);
        totalReserves[USDC] += amount;
        
        emit Deposit(msg.sender, USDC, amount, shares);
    }
    
    function depositMATIC(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        
        ERC20(MATIC).transferFrom(msg.sender, address(this), amount);
        
        uint256 shares = saMATIC.mint(msg.sender, amount);
        totalReserves[MATIC] += amount;
        
        emit Deposit(msg.sender, MATIC, amount, shares);
    }
    
    /*//////////////////////////////////////////////////////////////
                            WITHDRAW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function withdrawETH(uint256 shares) external nonReentrant {
        require(shares > 0, "Shares must be greater than 0");
        
        uint256 assets = saETH.burn(msg.sender, shares);
        uint256 availableLiquidity = getAvailableLiquidity(ETH_ADDRESS);
        require(availableLiquidity >= assets, "Insufficient ETH liquidity");
        
        totalReserves[ETH_ADDRESS] -= assets;
        
        payable(msg.sender).transfer(assets);
        
        emit Withdraw(msg.sender, ETH_ADDRESS, assets, shares);
    }
    
    function withdrawUSDC(uint256 shares) external nonReentrant {
        require(shares > 0, "Shares must be greater than 0");
        
        uint256 assets = saUSDC.burn(msg.sender, shares);
        uint256 availableLiquidity = getAvailableLiquidity(USDC);
        require(availableLiquidity >= assets, "Insufficient USDC liquidity");
        
        totalReserves[USDC] -= assets;
        
        ERC20(USDC).transfer(msg.sender, assets);
        
        emit Withdraw(msg.sender, USDC, assets, shares);
    }
    
    function withdrawMATIC(uint256 shares) external nonReentrant {
        require(shares > 0, "Shares must be greater than 0");
        
        uint256 assets = saMATIC.burn(msg.sender, shares);
        uint256 availableLiquidity = getAvailableLiquidity(MATIC);
        require(availableLiquidity >= assets, "Insufficient MATIC liquidity");
        
        totalReserves[MATIC] -= assets;
        
        ERC20(MATIC).transfer(msg.sender, assets);
        
        emit Withdraw(msg.sender, MATIC, assets, shares);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CREDIT SYSTEM FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    
    function getCollateralRatio(address user) public view returns (uint256) {
        uint256 score = creditProfiles[user].score;
        
        if (score >= 800) return 11000;      // 110% collateral
        if (score >= 600) return 13000;      // 130% collateral
        if (score >= 400) return 15000;      // 150% collateral
        if (score >= 200) return 18000;      // 180% collateral
        
        return 200;                        // 200% collateral (default)
    }
    
    function getBorrowInterestRate(address user) public view returns (uint256) {
        uint256 score = creditProfiles[user].score;
        uint256 discount = (score / 100) * CREDIT_DISCOUNT_RATE;
        
        return BASE_INTEREST_RATE > discount ? BASE_INTEREST_RATE - discount : 0;
    }
    
    /*//////////////////////////////////////////////////////////////
                            BORROWING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function borrow(
        address borrowAsset,
        uint256 borrowAmount,
        address collateralAsset,
        uint256 collateralAmount
    ) external payable nonReentrant whenNotPaused notBlacklisted validAsset(borrowAsset) validAsset(collateralAsset) {
        _ensureCreditProfile(msg.sender);
        require(borrowAmount > 0, "Borrow amount must be greater than 0");
        
        require(totalBorrowed[borrowAsset] + borrowAmount <= maxBorrowLimit[borrowAsset], "Asset borrow limit exceeded");
        
        // TODO: Implement price oracle to get USD values
        // uint256 borrowValueUSD = oracle.getPrice(borrowAsset) * borrowAmount;
        // require(getTotalBorrowedValueUSD() + borrowValueUSD <= globalBorrowLimit, "Global borrow limit exceeded");
        
        uint256 requiredRatio = getCollateralRatio(msg.sender);
        
        // TODO: Use oracle prices for cross-asset collateral calculation
        // uint256 borrowValue = oracle.getPrice(borrowAsset) * borrowAmount;
        // uint256 requiredCollateralValue = (borrowValue * requiredRatio) / 100;
        // uint256 collateralValue = oracle.getPrice(collateralAsset) * collateralAmount;
        // require(collateralValue >= requiredCollateralValue, "Insufficient collateral");
        
        if (borrowAsset == collateralAsset) {
            uint256 requiredCollateral = (borrowAmount * requiredRatio) / 10000;
            require(collateralAmount >= requiredCollateral, "Insufficient collateral");
        } else {
            // TODO: Remove this restriction when oracle is implemented
            revert("Cross-asset collateral requires price oracle");
        }
        
        uint256 availableLiquidity = getAvailableLiquidity(borrowAsset);
        require(availableLiquidity >= borrowAmount, "Insufficient liquidity");
        
        if (collateralAsset == ETH_ADDRESS) {
            require(msg.value == collateralAmount, "ETH amount mismatch");
        } else {
            ERC20(collateralAsset).transferFrom(msg.sender, address(this), collateralAmount);
        }
        
        uint256 interestRate = getBorrowInterestRate(msg.sender);
        
        borrowPositions[msg.sender].push(BorrowPosition({
            borrowedAsset: borrowAsset,
            borrowedAmount: borrowAmount,
            interestRate: interestRate,
            accruedInterest: 0,
            collateralAsset: collateralAsset,
            collateralAmount: collateralAmount,
            borrowTime: block.timestamp,
            dueDate: block.timestamp + LOAN_DURATION,
            isActive: true
        }));
        
        totalBorrowed[borrowAsset] += borrowAmount;
        creditProfiles[msg.sender].totalBorrowed += borrowAmount;
        
        if (borrowAsset == ETH_ADDRESS) {
            payable(msg.sender).transfer(borrowAmount);
        } else {
            ERC20(borrowAsset).transfer(msg.sender, borrowAmount);
        }
        
        emit Borrow(
            msg.sender, 
            borrowAsset, 
            borrowAmount, 
            collateralAsset, 
            collateralAmount, 
            interestRate,
            block.timestamp + LOAN_DURATION
        );
    }
    
    function repay(uint256 positionIndex, uint256 repayAmount) external payable nonReentrant whenNotPaused {
        require(positionIndex < borrowPositions[msg.sender].length, "Invalid position index");
        
        BorrowPosition storage position = borrowPositions[msg.sender][positionIndex];
        require(position.isActive, "Position not active");
        require(repayAmount > 0, "Repay amount must be greater than 0");
        
        uint256 timeElapsed = block.timestamp - position.borrowTime;
        uint256 currentInterest = (position.borrowedAmount * position.interestRate * timeElapsed) / (365 days * 10000);
        uint256 totalDebt = position.borrowedAmount + currentInterest;
        
        uint256 actualRepayAmount = repayAmount > totalDebt ? totalDebt : repayAmount;
        
        if (position.borrowedAsset == ETH_ADDRESS) {
            require(msg.value >= actualRepayAmount, "Insufficient ETH sent");
            if (msg.value > actualRepayAmount) {
                payable(msg.sender).transfer(msg.value - actualRepayAmount);
            }
        } else {
            ERC20(position.borrowedAsset).transferFrom(msg.sender, address(this), actualRepayAmount);
        }
        
        uint256 interestPaid = 0;
        uint256 principalPaid = 0;
        
        if (actualRepayAmount <= currentInterest) {
            interestPaid = actualRepayAmount;
            position.accruedInterest += interestPaid;
        } else {
            interestPaid = currentInterest;
            principalPaid = actualRepayAmount - currentInterest;
            position.borrowedAmount -= principalPaid;
            position.accruedInterest += interestPaid;
        }
        
        if (principalPaid > 0) {
            totalBorrowed[position.borrowedAsset] -= principalPaid;
        }
        
        if (interestPaid > 0) {
            _distributeInterest(position.borrowedAsset, interestPaid);
        }
        
        bool isFullyRepaid = position.borrowedAmount == 0;
        
        if (isFullyRepaid) {
            if (position.collateralAsset == ETH_ADDRESS) {
                payable(msg.sender).transfer(position.collateralAmount);
            } else {
                ERC20(position.collateralAsset).transfer(msg.sender, position.collateralAmount);
            }
            
            bool isOnTime = block.timestamp <= position.dueDate;
            
            creditProfiles[msg.sender].totalRepaid += actualRepayAmount;
            
            if (isOnTime) {
                creditProfiles[msg.sender].onTimePayments++;
                _updateCreditScore(msg.sender, true, 0);
            } else {
                creditProfiles[msg.sender].latePayments++;
                _updateCreditScore(msg.sender, false, 0);
            }
            
            position.isActive = false;
        } else {
            creditProfiles[msg.sender].totalRepaid += actualRepayAmount;
        }
        
        emit Repay(msg.sender, positionIndex, principalPaid, interestPaid, isFullyRepaid);
    }
    
    function liquidate(address borrower, uint256 positionIndex) external nonReentrant whenNotPaused payable{
        require(positionIndex < borrowPositions[borrower].length, "Invalid position index");
        
        BorrowPosition storage position = borrowPositions[borrower][positionIndex];
        require(position.isActive, "Position not active");
        require(block.timestamp > position.dueDate, "Position not yet liquidatable");
        
        // TODO: Implement proper liquidation with oracle prices
        // uint256 borrowValue = oracle.getPrice(position.borrowedAsset) * position.borrowedAmount;
        // uint256 collateralValue = oracle.getPrice(position.collateralAsset) * position.collateralAmount;
        // require(collateralValue < (borrowValue * LIQUIDATION_THRESHOLD) / 100, "Position still healthy");
        
        uint256 timeElapsed = block.timestamp - position.borrowTime;
        uint256 interest = (position.borrowedAmount * position.interestRate * timeElapsed) / (365 days * 10000);
        uint256 totalDebt = position.borrowedAmount + interest;
        
        if (position.borrowedAsset == ETH_ADDRESS) {
            require(msg.value >= totalDebt, "Insufficient ETH sent");
            if (msg.value > totalDebt) {
                payable(msg.sender).transfer(msg.value - totalDebt);
            }
        } else {
            ERC20(position.borrowedAsset).transferFrom(msg.sender, address(this), totalDebt);
        }
        
        totalBorrowed[position.borrowedAsset] -= position.borrowedAmount;
        
        _distributeInterest(position.borrowedAsset, interest);
        
        if (position.collateralAsset == ETH_ADDRESS) {
            payable(msg.sender).transfer(position.collateralAmount);
        } else {
            ERC20(position.collateralAsset).transfer(msg.sender, position.collateralAmount);
        }
        
        creditProfiles[borrower].liquidatedPrincipal += position.borrowedAmount;
        _updateCreditScore(borrower, false, position.borrowedAmount);
        
        position.isActive = false;
        
        emit Liquidation(borrower, positionIndex, msg.sender);
    }
    
    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _ensureCreditProfile(address user) internal {
        if (!creditProfiles[user].isActive) {
            creditProfiles[user] = CreditProfile({
                score: DEFAULT_CREDIT_SCORE,
                totalBorrowed: 0,
                totalRepaid: 0,
                onTimePayments: 0,
                latePayments: 0,
                liquidatedPrincipal: 0,
                isActive: true,
                isBlacklisted: false
            });
            
            emit CreditProfileCreated(user, DEFAULT_CREDIT_SCORE);
        }
    }
    
    function _distributeInterest(address asset, uint256 interest) internal {
        if (interest == 0) return;
        
        uint256 protocolFee = (interest * PROTOCOL_FEE) / 10000;
        uint256 lenderInterest = interest - protocolFee;
        
        accumulatedInterest[asset] += protocolFee;
        
        totalReserves[asset] += lenderInterest;
        
        if (asset == ETH_ADDRESS) {
            saETH.rebase(totalReserves[ETH_ADDRESS]);
        } else if (asset == USDC) {
            saUSDC.rebase(totalReserves[USDC]);
        } else if (asset == MATIC) {
            saMATIC.rebase(totalReserves[MATIC]);
        }
        
        emit InterestDistributed(asset, lenderInterest);
    }
    
    function _updateCreditScore(address user, bool isPositive, uint256 liquidatedPrincipal) internal {
        CreditProfile storage profile = creditProfiles[user];
        uint256 oldScore = profile.score;
        uint256 newScore = oldScore;
        
        if (liquidatedPrincipal > 0) {
            newScore = newScore > 200 ? newScore - 200 : MIN_CREDIT_SCORE;
            
            if (profile.liquidatedPrincipal > 100000 * 10**6) { // $100k equivalent
                profile.isBlacklisted = true;
            }
        } else if (isPositive) {
            uint256 increase = 10;
            if (profile.onTimePayments > 10) increase = 15;
            if (profile.onTimePayments > 20) increase = 20;
            
            newScore = newScore + increase > MAX_CREDIT_SCORE ? MAX_CREDIT_SCORE : newScore + increase;
        } else {
            uint256 decrease = 30;
            if (profile.latePayments > 5) decrease = 50;
            
            newScore = newScore > decrease ? newScore - decrease : MIN_CREDIT_SCORE;
        }
        
        profile.score = newScore;
        
        if (newScore != oldScore) {
            emit CreditScoreUpdated(user, oldScore, newScore);
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getAvailableLiquidity(address asset) public view returns (uint256) {
        return totalReserves[asset] - totalBorrowed[asset];
    }
    
    function getBorrowPositions(address user) external view returns (BorrowPosition[] memory) {
        return borrowPositions[user];
    }
    
    function getActiveBorrowPositions(address user) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < borrowPositions[user].length; i++) {
            if (borrowPositions[user][i].isActive) count++;
        }
        
        uint256[] memory activePositions = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < borrowPositions[user].length; i++) {
            if (borrowPositions[user][i].isActive) {
                activePositions[index] = i;
                index++;
            }
        }
        
        return activePositions;
    }
    
    function getCreditProfile(address user) external view returns (CreditProfile memory) {
        return creditProfiles[user];
    }
    
    function canBorrow(address user) external view returns (bool) {
        return creditProfiles[user].isActive && 
               !creditProfiles[user].isBlacklisted &&
               creditProfiles[user].score >= MIN_CREDIT_SCORE;
    }
    
    function getUtilizationRate(address asset) external view returns (uint256) {
        if (totalReserves[asset] == 0) return 0;
        return (totalBorrowed[asset] * 10000) / totalReserves[asset];
    }
    
    function getPositionDebt(address user, uint256 positionIndex) external view returns (uint256 principal, uint256 interest, uint256 totalDebt) {
        require(positionIndex < borrowPositions[user].length, "Invalid position index");
        
        BorrowPosition storage position = borrowPositions[user][positionIndex];
        
        if (!position.isActive) {
            return (0, 0, 0);
        }
        
        principal = position.borrowedAmount;
        uint256 timeElapsed = block.timestamp - position.borrowTime;
        interest = (principal * position.interestRate * timeElapsed) / (365 days * 10000);
        totalDebt = principal + interest;
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function setBorrowLimit(address asset, uint256 newLimit) external onlyOwner {
        maxBorrowLimit[asset] = newLimit;
        emit BorrowLimitUpdated(asset, newLimit);
    }
    
    function setGlobalBorrowLimit(uint256 newLimit) external onlyOwner {
        globalBorrowLimit = newLimit;
    }
    
    function withdrawProtocolFees(address asset) external onlyOwner {
        uint256 amount = accumulatedInterest[asset];
        require(amount > 0, "No fees to withdraw");
        
        accumulatedInterest[asset] = 0;
        
        if (asset == ETH_ADDRESS) {
            payable(owner()).transfer(amount);
        } else {
            ERC20(asset).transfer(owner(), amount);
        }
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /*//////////////////////////////////////////////////////////////
                            RECEIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    receive() external payable {}
    fallback() external payable {}
}