// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {SaToken} from "../src/SaToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract SaTokenTest is Test {
    SaToken public saToken;
    MockERC20 public mockToken;
    address public lendingProtocol;
    address public user1;
    address public user2;
    address public user3;

    event SharesMinted(address indexed to, uint256 shares, uint256 assets);
    event SharesBurned(address indexed from, uint256 shares, uint256 assets);
    event Rebase(uint256 newTotalAssets);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        lendingProtocol = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        mockToken = new MockERC20();
        saToken = new SaToken("Share Token", "saTOKEN", address(mockToken), lendingProtocol);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view{
        assertEq(saToken.name(), "Share Token");
        assertEq(saToken.symbol(), "saTOKEN");
        assertEq(saToken.underlyingAsset(), address(mockToken));
        assertEq(saToken.lendingProtocol(), lendingProtocol);
        assertEq(saToken.totalShares(), 0);
        assertEq(saToken.totalAssets(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint_FirstDeposit() public {
        uint256 depositAmount = 1000 * 10**18;
        
        vm.expectEmit(true, false, false, true);
        emit SharesMinted(user1, depositAmount, depositAmount);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, depositAmount);
        
        uint256 shares = saToken.mint(user1, depositAmount);
        
        assertEq(shares, depositAmount);
        assertEq(saToken.balanceOf(user1), depositAmount);
        assertEq(saToken.sharesOf(user1), depositAmount);
        assertEq(saToken.totalShares(), depositAmount);
        assertEq(saToken.totalAssets(), depositAmount);
        assertEq(saToken.totalSupply(), depositAmount);
    }

    function test_Mint_SubsequentDeposits() public {
        // First deposit
        uint256 firstDeposit = 1000 * 10**18;
        saToken.mint(user1, firstDeposit);
        
        // Second deposit
        uint256 secondDeposit = 500 * 10**18;
        uint256 expectedShares = (secondDeposit * saToken.totalShares()) / saToken.totalAssets();
        
        uint256 shares = saToken.mint(user2, secondDeposit);
        
        assertEq(shares, expectedShares);
        assertEq(saToken.balanceOf(user2), secondDeposit);
        assertEq(saToken.sharesOf(user2), expectedShares);
        assertEq(saToken.totalShares(), firstDeposit + expectedShares);
        assertEq(saToken.totalAssets(), firstDeposit + secondDeposit);
    }

    function test_Mint_RevertIfNotLendingProtocol() public {
        vm.prank(user1);
        vm.expectRevert("Only lending protocol");
        saToken.mint(user1, 1000 * 10**18);
    }

    function test_Mint_RevertIfZeroAmount() public {
        vm.expectRevert("Invalid amount");
        saToken.mint(user1, 0);
    }

    function test_Mint_RevertIfZeroAddress() public {
        vm.expectRevert("Invalid address");
        saToken.mint(address(0), 1000 * 10**18);
    }

    /*//////////////////////////////////////////////////////////////
                            BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Burn_Simple() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        uint256 burnShares = 500 * 10**18;
        uint256 expectedAssets = (burnShares * saToken.totalAssets()) / saToken.totalShares();
        
        vm.expectEmit(true, false, false, true);
        emit SharesBurned(user1, burnShares, expectedAssets);
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, address(0), expectedAssets);
        
        uint256 assets = saToken.burn(user1, burnShares);
        
        assertEq(assets, expectedAssets);
        assertEq(saToken.balanceOf(user1), depositAmount - expectedAssets);
        assertEq(saToken.sharesOf(user1), depositAmount - burnShares);
        assertEq(saToken.totalShares(), depositAmount - burnShares);
        assertEq(saToken.totalAssets(), depositAmount - expectedAssets);
    }

    function test_Burn_AllShares() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        uint256 assets = saToken.burn(user1, depositAmount);
        
        assertEq(assets, depositAmount);
        assertEq(saToken.balanceOf(user1), 0);
        assertEq(saToken.sharesOf(user1), 0);
        assertEq(saToken.totalShares(), 0);
        assertEq(saToken.totalAssets(), 0);
    }

    function test_Burn_RevertIfNotLendingProtocol() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        vm.prank(user1);
        vm.expectRevert("Only lending protocol");
        saToken.burn(user1, 500 * 10**18);
    }

    function test_Burn_RevertIfInsufficientShares() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        vm.expectRevert("Insufficient shares");
        saToken.burn(user1, depositAmount + 1);
    }

    function test_Burn_RevertIfZeroShares() public {
        vm.expectRevert("Invalid shares");
        saToken.burn(user1, 0);
    }

    function test_Burn_RevertIfZeroAddress() public {
        vm.expectRevert("Invalid address");
        saToken.burn(address(0), 1000 * 10**18);
    }

    /*//////////////////////////////////////////////////////////////
                            REBASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Rebase_IncreaseAssets() public {
        uint256 initialDeposit = 1000 * 10**18;
        saToken.mint(user1, initialDeposit);
        
        uint256 newTotalAssets = 1500 * 10**18;
        
        vm.expectEmit(false, false, false, true);
        emit Rebase(newTotalAssets);
        
        saToken.rebase(newTotalAssets);
        
        assertEq(saToken.totalAssets(), newTotalAssets);
        assertEq(saToken.balanceOf(user1), newTotalAssets);
        assertEq(saToken.totalSupply(), newTotalAssets);
    }

    function test_Rebase_WithMultipleUsers() public {
        // First user deposits
        uint256 firstDeposit = 1000 * 10**18;
        saToken.mint(user1, firstDeposit);
        
        // Second user deposits
        uint256 secondDeposit = 500 * 10**18;
        saToken.mint(user2, secondDeposit);
        
        // Rebase increases total assets
        uint256 newTotalAssets = 2000 * 10**18;
        saToken.rebase(newTotalAssets);
        
        // Both users should see their balances increase proportionally
        uint256 user1ExpectedBalance = (firstDeposit * newTotalAssets) / (firstDeposit + secondDeposit);
        uint256 user2ExpectedBalance = (secondDeposit * newTotalAssets) / (firstDeposit + secondDeposit);
        
        assertEq(saToken.balanceOf(user1), user1ExpectedBalance);
        assertEq(saToken.balanceOf(user2), user2ExpectedBalance);
    }

    function test_Rebase_RevertIfDecrease() public {
        uint256 initialDeposit = 1000 * 10**18;
        saToken.mint(user1, initialDeposit);
        
        vm.expectRevert("Cannot decrease assets");
        saToken.rebase(500 * 10**18);
    }

    function test_Rebase_RevertIfNotLendingProtocol() public {
        uint256 initialDeposit = 1000 * 10**18;
        saToken.mint(user1, initialDeposit);
        
        vm.prank(user1);
        vm.expectRevert("Only lending protocol");
        saToken.rebase(1500 * 10**18);
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transfer_Simple() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        uint256 transferAmount = 500 * 10**18;
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, user2, transferAmount);
        
        bool success = saToken.transfer(user2, transferAmount);
        
        assertTrue(success);
        assertEq(saToken.balanceOf(user1), depositAmount - transferAmount);
        assertEq(saToken.balanceOf(user2), transferAmount);
    }

    function test_Transfer_AfterRebase() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        // Rebase increases total assets
        saToken.rebase(2000 * 10**18);
        
        uint256 transferAmount = 1000 * 10**18;
        
        vm.prank(user1);
        bool success = saToken.transfer(user2, transferAmount);
        
        assertTrue(success);
        assertEq(saToken.balanceOf(user1), 1000 * 10**18); // 2000 - 1000
        assertEq(saToken.balanceOf(user2), 1000 * 10**18);
    }

    function test_Transfer_RevertIfInsufficientBalance() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        vm.prank(user1);
        vm.expectRevert("Insufficient balance");
        saToken.transfer(user2, depositAmount + 1);
    }

    function test_Transfer_RevertIfZeroAddress() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        vm.prank(user1);
        vm.expectRevert("Invalid to address");
        saToken.transfer(address(0), 500 * 10**18);
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFERFROM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferFrom_Simple() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        uint256 transferAmount = 500 * 10**18;
        
        // Approve user2 to spend user1's tokens
        vm.prank(user1);
        saToken.approve(user2, transferAmount);
        
        vm.prank(user2);
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, user3, transferAmount);
        
        bool success = saToken.transferFrom(user1, user3, transferAmount);
        
        assertTrue(success);
        assertEq(saToken.balanceOf(user1), depositAmount - transferAmount);
        assertEq(saToken.balanceOf(user3), transferAmount);
        assertEq(saToken.allowance(user1, user2), 0);
    }

    function test_TransferFrom_RevertIfInsufficientAllowance() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        uint256 transferAmount = 500 * 10**18;
        
        // Approve less than transfer amount
        vm.prank(user1);
        saToken.approve(user2, transferAmount - 100);
        
        vm.prank(user2);
        vm.expectRevert();
        saToken.transferFrom(user1, user3, transferAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            BALANCE AND SHARES TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BalanceOf_ZeroShares() public view{
        assertEq(saToken.balanceOf(user1), 0);
    }

    function test_SharesOf_ZeroShares() public view{
        assertEq(saToken.sharesOf(user1), 0);
    }

    function test_TotalSupply_ZeroShares() public view{
        assertEq(saToken.totalSupply(), 0);
    }

    function test_BalanceCalculation_WithRebase() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        saToken.mint(user2, depositAmount);
        
        // Rebase to double the assets
        saToken.rebase(4000 * 10**18);
        
        // Both users should have doubled their balance
        assertEq(saToken.balanceOf(user1), 2000 * 10**18);
        assertEq(saToken.balanceOf(user2), 2000 * 10**18);
        
        // But share balances remain the same
        assertEq(saToken.sharesOf(user1), depositAmount);
        assertEq(saToken.sharesOf(user2), depositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Mint_WithVerySmallAmount() public {
        uint256 smallAmount = 1;
        uint256 shares = saToken.mint(user1, smallAmount);
        
        assertEq(shares, smallAmount);
        assertEq(saToken.balanceOf(user1), smallAmount);
    }

    function test_Burn_WithVerySmallAmount() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        uint256 smallBurn = 1;
        uint256 assets = saToken.burn(user1, smallBurn);
        
        assertEq(assets, smallBurn);
        assertEq(saToken.balanceOf(user1), depositAmount - smallBurn);
    }

    function test_Transfer_ToSelf() public {
        uint256 depositAmount = 1000 * 10**18;
        saToken.mint(user1, depositAmount);
        
        uint256 transferAmount = 500 * 10**18;
        
        vm.prank(user1);
        bool success = saToken.transfer(user1, transferAmount);
        
        assertTrue(success);
        assertEq(saToken.balanceOf(user1), depositAmount); // Should remain the same
    }
} 