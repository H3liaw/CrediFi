// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {CrediFiProtocol} from "../src/CrediFiProtocol.sol";
import {SaToken} from "../src/SaToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 10000000 * 10**6);
    }
}

contract MockMATIC is ERC20 {
    constructor() ERC20("Polygon", "MATIC") {
        _mint(msg.sender, 10000000 * 10**18);
    }
}

contract CrediFiProtocolTest is Test {
    CrediFiProtocol public protocol;
    MockUSDC public usdc;
    MockMATIC public matic;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public liquidator;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        liquidator = makeAddr("liquidator");
        
        usdc = new MockUSDC();
        matic = new MockMATIC();
        
        protocol = new CrediFiProtocol(address(usdc), address(matic));
        
        // // Fund users
        usdc.transfer(user1, 1000000 * 10**6);
        usdc.transfer(user2, 1000000 * 10**6);
        usdc.transfer(user3, 1000000 * 10**6);
        usdc.transfer(liquidator, 1000000 * 10**6);
        
        matic.transfer(user1, 1000000 * 10**18);
        matic.transfer(user2, 1000000 * 10**18);
        matic.transfer(user3, 1000000 * 10**18);
        matic.transfer(liquidator, 1000000 * 10**18);
        
        // Fund protocol with initial liquidity
        vm.deal(address(this), 1000 ether);
        protocol.deposit{value: 100 ether}(address(0), 0);
        
        usdc.approve(address(protocol), type(uint256).max);
        protocol.deposit(address(usdc), 1000000 * 10**6);
        
        matic.approve(address(protocol), type(uint256).max);
        protocol.deposit(address(matic), 1000000 * 10**18);
    }

    function test_Constructor() public view{
        assertEq(protocol.USDC(), address(usdc));
        assertEq(protocol.MATIC(), address(matic));
        assertEq(protocol.ETH_ADDRESS(), address(0));
        assertEq(protocol.owner(), owner);
    }

    function test_DepositETH() public {
        uint256 depositAmount = 10 ether;
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        protocol.deposit{value: depositAmount}(address(0), 0);
        
        assertEq(protocol.totalReserves(address(0)), 110 ether);
        assertEq(protocol.saTokens(address(0)).balanceOf(user1), depositAmount);
    }

    function test_DepositUSDC() public {
        uint256 depositAmount = 10000 * 10**6;
        vm.startPrank(user1);
        usdc.approve(address(protocol), depositAmount);
        protocol.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        assertEq(protocol.totalReserves(address(usdc)), 1010000 * 10**6);
        assertEq(protocol.saTokens(address(usdc)).balanceOf(user1), depositAmount);
    }

    function test_WithdrawETH() public {
        uint256 depositAmount = 10 ether;
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        protocol.deposit{value: depositAmount}(address(0), 0);
        
        uint256 withdrawShares = 5 ether;
        uint256 initialBalance = user1.balance;
        
        vm.prank(user1);
        protocol.withdraw(address(0), withdrawShares);
        
        assertEq(user1.balance, initialBalance + 5 ether);
        assertEq(protocol.totalReserves(address(0)), 105 ether);
    }

    function test_Borrow_ETH() public {
        uint256 borrowAmount = 5 ether;
        uint256 collateralAmount = 10 ether;
        
        vm.deal(user1, collateralAmount);
        vm.prank(user1);
        protocol.borrow{value: collateralAmount}(address(0), borrowAmount, address(0), collateralAmount);
        
        CrediFiProtocol.BorrowPosition[] memory positions = protocol.getBorrowPositions(user1);
        assertEq(positions.length, 1);
        assertEq(positions[0].borrowedAmount, borrowAmount);
        assertTrue(positions[0].isActive);
        
        assertEq(protocol.totalBorrowed(address(0)), borrowAmount);
    }

    function test_Repay_FullRepayment() public {
        uint256 borrowAmount = 5 ether;
        uint256 collateralAmount = 10 ether;
        vm.deal(user1, collateralAmount);
        vm.prank(user1);
        protocol.borrow{value: collateralAmount}(address(0), borrowAmount, address(0), collateralAmount);
        
        vm.warp(block.timestamp + 15 days);
        
        (,, uint256 totalDebt) = protocol.getPositionDebt(user1, 0);
        
        vm.deal(user1, totalDebt);
        vm.prank(user1);
        protocol.repay{value: totalDebt}(0, totalDebt);
        
        CrediFiProtocol.BorrowPosition[] memory positions = protocol.getBorrowPositions(user1);
        assertFalse(positions[0].isActive);
        assertEq(protocol.totalBorrowed(address(0)), 0);
    }

    function test_Liquidate() public {
        uint256 borrowAmount = 5 ether;
        uint256 collateralAmount = 10 ether;
        vm.deal(user1, collateralAmount);
        vm.prank(user1);
        protocol.borrow{value: collateralAmount}(address(0), borrowAmount, address(0), collateralAmount);
        
        vm.warp(block.timestamp + 31 days);
        
        (,, uint256 totalDebt) = protocol.getPositionDebt(user1, 0);

        
        vm.deal(liquidator, totalDebt);
        console.log(liquidator.balance,"liquidator.balance");
        vm.prank(liquidator);
        protocol.liquidate{value: totalDebt}(user1, 0);
                console.log(liquidator.balance,"liquidator.balance2");

        CrediFiProtocol.BorrowPosition[] memory positions = protocol.getBorrowPositions(user1);
        assertFalse(positions[0].isActive);
        assertEq(liquidator.balance, collateralAmount);
    }

    function test_GetAvailableLiquidity() public view{
        assertEq(protocol.getAvailableLiquidity(address(0)), 100 ether);
        assertEq(protocol.getAvailableLiquidity(address(usdc)), 1000000 * 10**6);
    }

    function test_SetBorrowLimit() public {
        uint256 newLimit = 2000 ether;
        protocol.setBorrowLimit(address(0), newLimit);
        assertEq(protocol.maxBorrowLimit(address(0)), newLimit);
    }

    function test_PauseUnpause() public {
        protocol.pause();
        assertTrue(protocol.paused());
        
        protocol.unpause();
        assertFalse(protocol.paused());
    }

    function test_MultipleBorrows() public {
        vm.deal(user1, 40 ether);
        vm.prank(user1);
        protocol.borrow{value: 20 ether}(address(0), 5 ether, address(0), 20 ether);
        
        vm.prank(user1);
        protocol.borrow{value: 20 ether}(address(0), 3 ether, address(0), 20 ether);
        
        CrediFiProtocol.BorrowPosition[] memory positions = protocol.getBorrowPositions(user1);
        assertEq(positions.length, 2);
        assertEq(protocol.totalBorrowed(address(0)), 8 ether);
    }

    function test_InterestDistribution() public {
        vm.deal(user1, 50 ether);
        vm.deal(user2, 50 ether);
        vm.prank(user1);
        protocol.deposit{value: 50 ether}(address(0), 0);
        vm.prank(user2);
        protocol.deposit{value: 50 ether}(address(0), 0);
        
        vm.deal(user3, 20 ether);
        vm.prank(user3);
        protocol.borrow{value: 20 ether}(address(0), 10 ether, address(0), 20 ether);
        
        vm.warp(block.timestamp + 30 days);
        (,, uint256 totalDebt) = protocol.getPositionDebt(user3, 0);
        vm.deal(user3, totalDebt);
        vm.prank(user3);
        protocol.repay{value: totalDebt}(0, totalDebt);
        
        assertGt(protocol.saTokens(address(0)).balanceOf(user1), 50 ether);
        assertGt(protocol.saTokens(address(0)).balanceOf(user2), 50 ether);
    }
} 