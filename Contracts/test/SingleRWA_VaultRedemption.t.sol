// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.sol";
import {SingleRWA_Vault} from "../src/SingleRWA_Vault.sol";
import {ISingleRWA_Vault} from "../interfaces/ISingleRWA_Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SingleRWA_VaultRedemptionTest
 * @notice Tests for redemption functionality (standard, at maturity, early)
 */
contract SingleRWA_VaultRedemptionTest is BaseTest {
    SingleRWA_Vault public activeVault;

    function setUp() public override {
        super.setUp();
        activeVault = _setupActiveVault();
    }

    // ============================================
    // STANDARD WITHDRAW TESTS
    // ============================================

    function test_Withdraw_Success() public {
        uint256 sharesBefore = activeVault.balanceOf(user1);
        uint256 assetsToWithdraw = 1000e6;

        vm.prank(user1);
        uint256 shares = activeVault.withdraw(assetsToWithdraw, user1, user1);

        assertGt(shares, 0);
        assertLt(activeVault.balanceOf(user1), sharesBefore);
    }

    function test_Withdraw_RevertWhen_Paused() public {
        vm.prank(operator);
        activeVault.pause("Testing");

        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.VaultPaused.selector);
        activeVault.withdraw(1000e6, user1, user1);
    }

    // ============================================
    // STANDARD REDEEM TESTS
    // ============================================

    function test_Redeem_Success() public {
        uint256 sharesToRedeem = activeVault.balanceOf(user1) / 2;

        vm.prank(user1);
        uint256 assets = activeVault.redeem(sharesToRedeem, user1, user1);

        assertGt(assets, 0);
    }

    function test_Redeem_RevertWhen_Paused() public {
        vm.prank(operator);
        activeVault.pause("Testing");

        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.VaultPaused.selector);
        activeVault.redeem(1000e6, user1, user1);
    }

    // ============================================
    // REDEEM AT MATURITY TESTS
    // ============================================

    function test_RedeemAtMaturity_Success() public {
        // Mature the vault
        vm.warp(activeVault.maturityDate() + 1);
        vm.prank(operator);
        activeVault.matureVault();

        uint256 shares = activeVault.balanceOf(user1);
        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        uint256 assets = activeVault.redeemAtMaturity(shares, user1, user1);

        assertGt(assets, 0);
        assertEq(activeVault.balanceOf(user1), 0);
        assertGt(usdc.balanceOf(user1), balanceBefore);
    }

    function test_RedeemAtMaturity_IncludesPendingYield() public {
        // Distribute yield
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        // Mature the vault
        vm.warp(activeVault.maturityDate() + 1);
        vm.prank(operator);
        activeVault.matureVault();

        uint256 shares = activeVault.balanceOf(user1);
        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        uint256 assets = activeVault.redeemAtMaturity(shares, user1, user1);

        // Should include principal + yield
        assertEq(usdc.balanceOf(user1), balanceBefore + assets);
        assertGt(assets, FUNDING_TARGET); // More than just principal
    }

    function test_RedeemAtMaturity_MarksYieldAsClaimed() public {
        // Distribute yield
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        // Mature the vault
        vm.warp(activeVault.maturityDate() + 1);
        vm.prank(operator);
        activeVault.matureVault();

        uint256 shares = activeVault.balanceOf(user1);

        vm.prank(user1);
        activeVault.redeemAtMaturity(shares, user1, user1);

        // Yield should be marked as claimed
        assertEq(activeVault.pendingYield(user1), 0);
    }

    function test_RedeemAtMaturity_RevertWhen_NotMatured() public {
        uint256 shares = activeVault.balanceOf(user1);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleRWA_Vault.InvalidVaultState.selector,
                ISingleRWA_Vault.VaultState.Active,
                ISingleRWA_Vault.VaultState.Matured
            )
        );
        activeVault.redeemAtMaturity(shares, user1, user1);
    }

    function test_RedeemAtMaturity_RevertWhen_Paused() public {
        // Mature the vault
        vm.warp(activeVault.maturityDate() + 1);
        vm.prank(operator);
        activeVault.matureVault();

        vm.prank(operator);
        activeVault.pause("Testing");

        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.VaultPaused.selector);
        activeVault.redeemAtMaturity(1000e6, user1, user1);
    }

    // ============================================
    // EARLY REDEMPTION REQUEST TESTS
    // ============================================

    function test_RequestEarlyRedemption_Success() public {
        uint256 shares = activeVault.balanceOf(user1) / 2;

        vm.prank(user1);
        uint256 requestId = activeVault.requestEarlyRedemption(shares);

        assertEq(requestId, 1);

        (
            address reqUser,
            uint256 reqShares,
            uint256 reqTime,
            bool processed
        ) = activeVault.redemptionRequests(requestId);

        assertEq(reqUser, user1);
        assertEq(reqShares, shares);
        assertEq(reqTime, block.timestamp);
        assertFalse(processed);
    }

    function test_RequestEarlyRedemption_MultipleRequests() public {
        uint256 shares = activeVault.balanceOf(user1) / 4;

        vm.startPrank(user1);
        uint256 requestId1 = activeVault.requestEarlyRedemption(shares);
        uint256 requestId2 = activeVault.requestEarlyRedemption(shares);
        vm.stopPrank();

        assertEq(requestId1, 1);
        assertEq(requestId2, 2);
    }

    function test_RequestEarlyRedemption_RevertWhen_ZeroShares() public {
        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.ZeroAmount.selector);
        activeVault.requestEarlyRedemption(0);
    }

    function test_RequestEarlyRedemption_RevertWhen_InsufficientShares()
        public
    {
        uint256 tooManyShares = activeVault.balanceOf(user1) + 1;

        vm.prank(user1);
        vm.expectRevert("Insufficient shares");
        activeVault.requestEarlyRedemption(tooManyShares);
    }

    function test_RequestEarlyRedemption_RevertWhen_Paused() public {
        vm.prank(operator);
        activeVault.pause("Testing");

        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.VaultPaused.selector);
        activeVault.requestEarlyRedemption(1000e6);
    }

    // ============================================
    // PROCESS EARLY REDEMPTION TESTS
    // ============================================

    function test_ProcessEarlyRedemption_Success() public {
        uint256 shares = activeVault.balanceOf(user1);

        vm.prank(user1);
        uint256 requestId = activeVault.requestEarlyRedemption(shares);

        uint256 balanceBefore = usdc.balanceOf(user1);
        uint256 expectedAssets = activeVault.previewRedeem(shares);
        uint256 expectedFee = (expectedAssets * EARLY_REDEMPTION_FEE_BPS) /
            10000;
        uint256 expectedNet = expectedAssets - expectedFee;

        vm.prank(operator);
        activeVault.processEarlyRedemption(requestId);

        assertEq(activeVault.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user1), balanceBefore + expectedNet);

        (, , , bool processed) = activeVault.redemptionRequests(requestId);
        assertTrue(processed);
    }

    function test_ProcessEarlyRedemption_AppliesCorrectFee() public {
        uint256 shares = activeVault.balanceOf(user1);

        vm.prank(user1);
        uint256 requestId = activeVault.requestEarlyRedemption(shares);

        uint256 expectedAssets = activeVault.previewRedeem(shares);
        uint256 expectedFee = (expectedAssets * EARLY_REDEMPTION_FEE_BPS) /
            10000; // 2%

        uint256 vaultBalanceBefore = usdc.balanceOf(address(activeVault));

        vm.prank(operator);
        activeVault.processEarlyRedemption(requestId);

        // Fee stays in vault
        uint256 vaultBalanceAfter = usdc.balanceOf(address(activeVault));
        assertEq(
            vaultBalanceBefore - (expectedAssets - expectedFee),
            vaultBalanceAfter
        );
    }

    function test_ProcessEarlyRedemption_RevertWhen_NotOperator() public {
        uint256 shares = activeVault.balanceOf(user1);

        vm.prank(user1);
        uint256 requestId = activeVault.requestEarlyRedemption(shares);

        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.NotOperator.selector);
        activeVault.processEarlyRedemption(requestId);
    }

    function test_ProcessEarlyRedemption_RevertWhen_AlreadyProcessed() public {
        uint256 shares = activeVault.balanceOf(user1);

        vm.prank(user1);
        uint256 requestId = activeVault.requestEarlyRedemption(shares);

        vm.startPrank(operator);
        activeVault.processEarlyRedemption(requestId);

        vm.expectRevert("Already processed");
        activeVault.processEarlyRedemption(requestId);
        vm.stopPrank();
    }

    function test_ProcessEarlyRedemption_RevertWhen_InvalidRequest() public {
        vm.prank(operator);
        vm.expectRevert("Invalid request");
        activeVault.processEarlyRedemption(999);
    }

    // ============================================
    // EARLY REDEMPTION FEE TESTS
    // ============================================

    function test_SetEarlyRedemptionFee_Success() public {
        uint256 newFee = 100; // 1%

        vm.prank(operator);
        activeVault.setEarlyRedemptionFee(newFee);

        assertEq(activeVault.earlyRedemptionFeeBps(), newFee);
    }

    function test_SetEarlyRedemptionFee_RevertWhen_TooHigh() public {
        uint256 tooHighFee = 1001; // > 10%

        vm.prank(operator);
        vm.expectRevert("Fee too high");
        activeVault.setEarlyRedemptionFee(tooHighFee);
    }

    function test_SetEarlyRedemptionFee_RevertWhen_NotOperator() public {
        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.NotOperator.selector);
        activeVault.setEarlyRedemptionFee(100);
    }

    // ============================================
    // TRANSFER TESTS
    // ============================================

    function test_Transfer_Success() public {
        uint256 amount = activeVault.balanceOf(user1) / 2;

        vm.prank(user1);
        bool success = activeVault.transfer(user2, amount);

        assertTrue(success);
        assertEq(activeVault.balanceOf(user2), amount);
    }

    function test_TransferFrom_Success() public {
        uint256 amount = activeVault.balanceOf(user1) / 2;

        vm.prank(user1);
        activeVault.approve(user2, amount);

        vm.prank(user2);
        bool success = activeVault.transferFrom(user1, user2, amount);

        assertTrue(success);
        assertEq(activeVault.balanceOf(user2), amount);
    }
}
