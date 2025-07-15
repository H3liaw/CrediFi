// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SaToken.sol";

/**
 * @title CrediFiProtocol
 * @dev CrediFi protocol is a lending protocol based on credit rating system as a form of
 * collateral for ETH, USDC, and MATIC.
 */
contract CrediFiProtocol is Ownable, ReentrancyGuard {

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
    
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event Deposit(address indexed user, address indexed asset, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, address indexed asset, uint256 amount, uint256 shares);
    event InterestAdded(address indexed asset, uint256 amount);
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address _usdc, address _matic) Ownable(msg.sender) {
        USDC = _usdc;
        MATIC = _matic;
        
        saETH = new SaToken("Share ETH", "saETH", ETH_ADDRESS, address(this));
        saUSDC = new SaToken("Share USDC", "saUSDC", USDC, address(this));
        saMATIC = new SaToken("Share MATIC", "saMATIC", MATIC, address(this));
    }
    
    /*//////////////////////////////////////////////////////////////
                            DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Deposit ETH and receive saETH tokens
     */
    function depositETH() external payable nonReentrant {
        require(msg.value > 0, "Amount must be greater than 0");
        
        uint256 shares = saETH.mint(msg.sender, msg.value);
        totalReserves[ETH_ADDRESS] += msg.value;
        
        emit Deposit(msg.sender, ETH_ADDRESS, msg.value, shares);
    }
    
    /**
     * @dev Deposit USDC and receive saUSDC tokens
     */
    function depositUSDC(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        ERC20(USDC).transferFrom(msg.sender, address(this), amount);
        
        uint256 shares = saUSDC.mint(msg.sender, amount);
        totalReserves[USDC] += amount;
        
        emit Deposit(msg.sender, USDC, amount, shares);
    }
    
    /**
     * @dev Deposit MATIC and receive saMATIC tokens
     */
    function depositMATIC(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        ERC20(MATIC).transferFrom(msg.sender, address(this), amount);
        
        uint256 shares = saMATIC.mint(msg.sender, amount);
        totalReserves[MATIC] += amount;
        
        emit Deposit(msg.sender, MATIC, amount, shares);
    }
    
    /*//////////////////////////////////////////////////////////////
                            WITHDRAW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Withdraw ETH by burning saETH tokens
     */
    function withdrawETH(uint256 shares) external nonReentrant {
        require(shares > 0, "Shares must be greater than 0");
        
        uint256 assets = saETH.burn(msg.sender, shares);
        require(address(this).balance >= assets, "Insufficient ETH liquidity");
        
        totalReserves[ETH_ADDRESS] -= assets;
        
        payable(msg.sender).transfer(assets);
        
        emit Withdraw(msg.sender, ETH_ADDRESS, assets, shares);
    }
    
    /**
     * @dev Withdraw USDC by burning saUSDC tokens
     */
    function withdrawUSDC(uint256 shares) external nonReentrant {
        require(shares > 0, "Shares must be greater than 0");
        
        uint256 assets = saUSDC.burn(msg.sender, shares);
        require(ERC20(USDC).balanceOf(address(this)) >= assets, "Insufficient USDC liquidity");
        
        totalReserves[USDC] -= assets;
        
        ERC20(USDC).transfer(msg.sender, assets);
        
        emit Withdraw(msg.sender, USDC, assets, shares);
    }
    
    /**
     * @dev Withdraw MATIC by burning saMATIC tokens
     */
    function withdrawMATIC(uint256 shares) external nonReentrant {
        require(shares > 0, "Shares must be greater than 0");
        
        uint256 assets = saMATIC.burn(msg.sender, shares);
        require(ERC20(MATIC).balanceOf(address(this)) >= assets, "Insufficient MATIC liquidity");
        
        totalReserves[MATIC] -= assets;
        
        ERC20(MATIC).transfer(msg.sender, assets);
        
        emit Withdraw(msg.sender, MATIC, assets, shares);
    }
    
    /**
     * @dev Add interest to ETH pool (for testing rebasing)
     */
    function addETHInterest() external payable onlyOwner {
        require(msg.value > 0, "Interest must be greater than 0");
        
        totalReserves[ETH_ADDRESS] += msg.value;
        saETH.rebase(totalReserves[ETH_ADDRESS]);
        
        emit InterestAdded(ETH_ADDRESS, msg.value);
    }
    
    /**
     * @dev Add interest to USDC pool (for testing rebasing)
     */
    function addUSDCInterest(uint256 amount) external onlyOwner {
        require(amount > 0, "Interest must be greater than 0");
        
        ERC20(USDC).transferFrom(msg.sender, address(this), amount);
        
        totalReserves[USDC] += amount;
        saUSDC.rebase(totalReserves[USDC]);
        
        emit InterestAdded(USDC, amount);
    }
    
    /**
     * @dev Add interest to MATIC pool (for testing rebasing)
     */
    function addMATICInterest(uint256 amount) external onlyOwner {
        require(amount > 0, "Interest must be greater than 0");
        
        ERC20(MATIC).transferFrom(msg.sender, address(this), amount);
        
        totalReserves[MATIC] += amount;
        saMATIC.rebase(totalReserves[MATIC]);
        
        emit InterestAdded(MATIC, amount);
    }
    
    /*//////////////////////////////////////////////////////////////
                            RECEIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Receive ETH
     */
    receive() external payable {}
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}