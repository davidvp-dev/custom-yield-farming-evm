// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/ERC20Token.sol";

contract ERC20TokenTest is Test {
    ERC20Token token;
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18; // 1M tokens

    function setUp() public {
        vm.startPrank(owner);
        token = new ERC20Token("TEST_TOKEN", "TST", INITIAL_SUPPLY);
        vm.stopPrank();
    }

    function test_deployAndInitialMint_OK() public view {
        uint256 ownerBalance = token.balanceOf(owner);
        uint256 expectedOwnerInitialBalance = INITIAL_SUPPLY;

        assertNotEq(address(token), address(0));
        assertEq(ownerBalance, expectedOwnerInitialBalance);
    }

    function test_mintTokens_OK() public {
        uint256 userBalBefore = token.balanceOf(user1);
        uint256 amountMinted = 100 ether;
        vm.startPrank(owner);
        token.mint(user1, amountMinted);
        vm.stopPrank();

        uint256 userBalAfter = token.balanceOf(user1);
        uint256 totalSupplyAfter = token.totalSupply();

        assert(userBalAfter == amountMinted + userBalBefore);
        assert(totalSupplyAfter == amountMinted + INITIAL_SUPPLY);
    }

    function test_burnTokens_OK() public {
        uint256 userBalBefore = token.balanceOf(user1);
        uint256 amountMinted = 100 ether;
        vm.startPrank(owner);
        token.mint(user1, amountMinted);
        vm.stopPrank();

        uint256 balanceAfterMint = token.balanceOf(user1);
        uint256 totalSupplyAfterMint = token.totalSupply();

        assert(balanceAfterMint == amountMinted + userBalBefore);
        assert(totalSupplyAfterMint == amountMinted + INITIAL_SUPPLY);

        vm.startPrank(user1);
        uint256 amountBurned = 1 ether;
        token.burn(amountBurned);
        uint256 balanceAfterBurn = token.balanceOf(user1);

        assert(balanceAfterBurn == balanceAfterMint - amountBurned);
        assert(token.totalSupply() == totalSupplyAfterMint - amountBurned);
        vm.stopPrank();
    }
}
