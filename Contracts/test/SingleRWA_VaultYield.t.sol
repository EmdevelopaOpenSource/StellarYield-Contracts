// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.sol";
import {SingleRWA_Vault} from "../src/SingleRWA_Vault.sol";
import {ISingleRWA_Vault} from "../interfaces/ISingleRWA_Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SingleRWA_VaultYieldTest
 * @notice Tests for yield distribution and claiming functionality
 */
contract SingleRWA_VaultYieldTest is BaseTest {
    SingleRWA_Vault public activeVault;

    function setUp() public override {
        super.setUp();
        activeVault = _setupActiveVault();
    }

    // ============================================
    // YIELD DISTRIBUTION TESTS
    // ============================================

    function test_DistributeYield_Success() public {
        uint256 epoch = _approveAndDistributeYield(
            activeVault,
            operator,
            YIELD_AMOUNT
        );

        assertEq(epoch, 1);
        assertEq(activeVault.currentEpoch(), 1);
        assertEq(activeVault.epochYield(1), YIELD_AMOUNT);
        assertEq(activeVault.totalYieldDistributed(), YIELD_AMOUNT);
    }

    function test_DistributeYield_TransfersTokens() public {
        uint256 operatorBalanceBefore = usdc.balanceOf(operator);
        uint256 vaultBalanceBefore = usdc.balanceOf(address(activeVault));

        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        assertEq(
            usdc.balanceOf(operator),
            operatorBalanceBefore - YIELD_AMOUNT
        );
        assertEq(
            usdc.balanceOf(address(activeVault)),
            vaultBalanceBefore + YIELD_AMOUNT
        );
    }

    function test_DistributeYield_EmitsEvent() public {
        vm.startPrank(operator);
        usdc.approve(address(activeVault), YIELD_AMOUNT);

        vm.expectEmit(true, false, false, true);
        emit ISingleRWA_Vault.YieldDistributed(
            1,
            YIELD_AMOUNT,
            block.timestamp
        );
        activeVault.distributeYield(YIELD_AMOUNT);
        vm.stopPrank();
    }

    function test_DistributeYield_MultipleEpochs() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT * 2);
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT * 3);

        assertEq(activeVault.currentEpoch(), 3);
        assertEq(activeVault.epochYield(1), YIELD_AMOUNT);
        assertEq(activeVault.epochYield(2), YIELD_AMOUNT * 2);
        assertEq(activeVault.epochYield(3), YIELD_AMOUNT * 3);
        assertEq(
            activeVault.totalYieldDistributed(),
            YIELD_AMOUNT + YIELD_AMOUNT * 2 + YIELD_AMOUNT * 3
        );
    }

    function test_DistributeYield_RevertWhen_ZeroAmount() public {
        vm.prank(operator);
        vm.expectRevert(ISingleRWA_Vault.ZeroAmount.selector);
        activeVault.distributeYield(0);
    }

    function test_DistributeYield_RevertWhen_NotOperator() public {
        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.NotOperator.selector);
        activeVault.distributeYield(YIELD_AMOUNT);
    }

    function test_DistributeYield_RevertWhen_NotActiveState() public {
        SingleRWA_Vault fundingVault = _deployDefaultVault();

        vm.startPrank(admin);
        fundingVault.setOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        usdc.approve(address(fundingVault), YIELD_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleRWA_Vault.InvalidVaultState.selector,
                ISingleRWA_Vault.VaultState.Funding,
                ISingleRWA_Vault.VaultState.Active
            )
        );
        fundingVault.distributeYield(YIELD_AMOUNT);
        vm.stopPrank();
    }

    function test_DistributeYield_RevertWhen_Paused() public {
        vm.prank(operator);
        activeVault.pause("Testing");

        vm.startPrank(operator);
        usdc.approve(address(activeVault), YIELD_AMOUNT);

        vm.expectRevert(ISingleRWA_Vault.VaultPaused.selector);
        activeVault.distributeYield(YIELD_AMOUNT);
        vm.stopPrank();
    }

    // ============================================
    // PENDING YIELD TESTS
    // ============================================

    function test_PendingYield_CalculatesCorrectly() public {
        // User1 has all shares from funding
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        uint256 pending = activeVault.pendingYield(user1);
        assertEq(pending, YIELD_AMOUNT); // User1 has 100% of shares
    }

    function test_PendingYield_MultipleUsers() public {
        // User2 deposits same amount
        _approveAndDeposit(activeVault, user2, FUNDING_TARGET);

        // Distribute yield
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        // Each user should get 50%
        uint256 pendingUser1 = activeVault.pendingYield(user1);
        uint256 pendingUser2 = activeVault.pendingYield(user2);

        assertEq(pendingUser1, YIELD_AMOUNT / 2);
        assertEq(pendingUser2, YIELD_AMOUNT / 2);
    }

    function test_PendingYieldForEpoch_ReturnsCorrectValue() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        uint256 pending = activeVault.pendingYieldForEpoch(user1, 1);
        assertEq(pending, YIELD_AMOUNT);
    }

    function test_PendingYieldForEpoch_ReturnsZeroForInvalidEpoch() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        assertEq(activeVault.pendingYieldForEpoch(user1, 0), 0);
        assertEq(activeVault.pendingYieldForEpoch(user1, 2), 0); // Future epoch
    }

    function test_PendingYieldForEpoch_ReturnsZeroAfterClaim() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        vm.prank(user1);
        activeVault.claimYieldForEpoch(1);

        assertEq(activeVault.pendingYieldForEpoch(user1, 1), 0);
    }

    // ============================================
    // CLAIM YIELD TESTS
    // ============================================

    function test_ClaimYield_Success() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        uint256 claimed = activeVault.claimYield();

        assertEq(claimed, YIELD_AMOUNT);
        assertEq(usdc.balanceOf(user1), balanceBefore + YIELD_AMOUNT);
        assertEq(activeVault.totalYieldClaimed(user1), YIELD_AMOUNT);
    }

    function test_ClaimYield_EmitsEvent() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        vm.prank(user1);
        vm.expectEmit(true, false, true, true);
        emit ISingleRWA_Vault.YieldClaimed(user1, YIELD_AMOUNT, 1);
        activeVault.claimYield();
    }

    function test_ClaimYield_MultipleEpochs() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT * 2);

        vm.prank(user1);
        uint256 claimed = activeVault.claimYield();

        assertEq(claimed, YIELD_AMOUNT + YIELD_AMOUNT * 2);
    }

    function test_ClaimYield_RevertWhen_NoYieldToClaim() public {
        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.NoYieldToClaim.selector);
        activeVault.claimYield();
    }

    function test_ClaimYield_RevertWhen_AlreadyClaimed() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        vm.startPrank(user1);
        activeVault.claimYield();

        vm.expectRevert(ISingleRWA_Vault.NoYieldToClaim.selector);
        activeVault.claimYield();
        vm.stopPrank();
    }

    function test_ClaimYield_RevertWhen_Paused() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        vm.prank(operator);
        activeVault.pause("Testing");

        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.VaultPaused.selector);
        activeVault.claimYield();
    }

    function test_ClaimYieldForEpoch_Success() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT * 2);

        vm.prank(user1);
        uint256 claimed = activeVault.claimYieldForEpoch(1);

        assertEq(claimed, YIELD_AMOUNT);

        // Epoch 2 still claimable
        uint256 pending = activeVault.pendingYieldForEpoch(user1, 2);
        assertEq(pending, YIELD_AMOUNT * 2);
    }

    function test_ClaimYieldForEpoch_RevertWhen_AlreadyClaimed() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        vm.startPrank(user1);
        activeVault.claimYieldForEpoch(1);

        vm.expectRevert(ISingleRWA_Vault.NoYieldToClaim.selector);
        activeVault.claimYieldForEpoch(1);
        vm.stopPrank();
    }

    // ============================================
    // YIELD SNAPSHOT TESTS
    // ============================================

    function test_YieldSnapshot_TracksSharesCorrectly() public {
        // User1 deposits first
        // User2 deposits after first yield
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        // User2 deposits after epoch 1
        _approveAndDeposit(activeVault, user2, FUNDING_TARGET);

        // Distribute second yield
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        // User1 should get 100% of epoch 1, 50% of epoch 2
        // User2 should get 0% of epoch 1, 50% of epoch 2
        uint256 user1Epoch1 = activeVault.pendingYieldForEpoch(user1, 1);
        uint256 user1Epoch2 = activeVault.pendingYieldForEpoch(user1, 2);
        uint256 user2Epoch1 = activeVault.pendingYieldForEpoch(user2, 1);
        uint256 user2Epoch2 = activeVault.pendingYieldForEpoch(user2, 2);

        assertEq(user1Epoch1, YIELD_AMOUNT); // 100%
        assertEq(user1Epoch2, YIELD_AMOUNT / 2); // 50%
        assertEq(user2Epoch1, 0); // 0% (joined after)
        assertEq(user2Epoch2, YIELD_AMOUNT / 2); // 50%
    }

    function test_YieldSnapshot_UpdatesOnTransfer() public {
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        // User1 transfers half shares to user2
        uint256 halfShares = activeVault.balanceOf(user1) / 2;
        vm.prank(user1);
        activeVault.transfer(user2, halfShares);

        // Distribute more yield
        _approveAndDistributeYield(activeVault, operator, YIELD_AMOUNT);

        // Epoch 1: User1 100%, User2 0%
        // Epoch 2: User1 50%, User2 50%
        assertEq(activeVault.pendingYieldForEpoch(user1, 1), YIELD_AMOUNT);
        assertEq(activeVault.pendingYieldForEpoch(user2, 1), 0);
        assertEq(activeVault.pendingYieldForEpoch(user1, 2), YIELD_AMOUNT / 2);
        assertEq(activeVault.pendingYieldForEpoch(user2, 2), YIELD_AMOUNT / 2);
    }
}
