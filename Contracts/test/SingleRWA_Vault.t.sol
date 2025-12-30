// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.sol";
import {SingleRWA_Vault} from "../src/SingleRWA_Vault.sol";
import {ISingleRWA_Vault} from "../interfaces/ISingleRWA_Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SingleRWA_VaultTest
 * @notice Comprehensive tests for SingleRWA_Vault contract
 */
contract SingleRWA_VaultTest is BaseTest {
    SingleRWA_Vault public testVault;

    function setUp() public override {
        super.setUp();
        testVault = _deployDefaultVault();

        // Set operator
        vm.prank(admin);
        testVault.setOperator(operator, true);
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsCorrectParameters() public view {
        assertEq(testVault.admin(), admin);
        assertEq(testVault.fundingTarget(), FUNDING_TARGET);
        assertEq(testVault.minDeposit(), MIN_DEPOSIT);
        assertEq(testVault.maxDepositPerUser(), MAX_DEPOSIT_PER_USER);
        assertEq(testVault.earlyRedemptionFeeBps(), EARLY_REDEMPTION_FEE_BPS);
        assertEq(testVault.zkmeVerifier(), address(zkmeVerifier));
        assertEq(testVault.cooperator(), cooperator);
    }

    function test_Constructor_SetsRWADetails() public view {
        ISingleRWA_Vault.RWADetails memory details = testVault.getRWADetails();
        assertEq(details.name, "US Treasury 6-Month Bill");
        assertEq(details.symbol, "USTB6M");
        assertEq(details.documentURI, "ipfs://QmTreasuryDocs");
        assertEq(details.category, "Treasury");
        assertEq(details.expectedAPY, 500);
    }

    function test_Constructor_StartsInFundingState() public view {
        _assertVaultState(testVault, ISingleRWA_Vault.VaultState.Funding);
    }

    function test_Constructor_SetsAdminAsOperator() public view {
        assertTrue(testVault.isOperator(admin));
    }

    function test_Constructor_RevertWhen_ZeroAdmin() public {
        ISingleRWA_Vault.InitParams memory params = _createDefaultInitParams();
        params.admin = address(0);

        vm.expectRevert(ISingleRWA_Vault.ZeroAddress.selector);
        new SingleRWA_Vault(params);
    }

    function test_Constructor_AllowsZeroVerifier() public {
        ISingleRWA_Vault.InitParams memory params = _createDefaultInitParams();
        params.zkmeVerifier = address(0);

        SingleRWA_Vault vaultNoKYC = new SingleRWA_Vault(params);
        assertEq(vaultNoKYC.zkmeVerifier(), address(0));
    }

    // ============================================
    // RWA DETAILS TESTS
    // ============================================

    function test_RwaName_ReturnsCorrectValue() public view {
        assertEq(testVault.rwaName(), "US Treasury 6-Month Bill");
    }

    function test_RwaSymbol_ReturnsCorrectValue() public view {
        assertEq(testVault.rwaSymbol(), "USTB6M");
    }

    function test_RwaDocumentURI_ReturnsCorrectValue() public view {
        assertEq(testVault.rwaDocumentURI(), "ipfs://QmTreasuryDocs");
    }

    function test_RwaCategory_ReturnsCorrectValue() public view {
        assertEq(testVault.rwaCategory(), "Treasury");
    }

    // ============================================
    // KYC VERIFICATION TESTS
    // ============================================

    function test_IsKYCVerified_ReturnsTrueForApprovedUser() public view {
        assertTrue(testVault.isKYCVerified(user1));
    }

    function test_IsKYCVerified_ReturnsFalseForUnapprovedUser() public {
        address unapprovedUser = makeAddr("unapproved");
        assertFalse(testVault.isKYCVerified(unapprovedUser));
    }

    function test_IsKYCVerified_ReturnsTrueWhenNoVerifierSet() public {
        SingleRWA_Vault vaultNoKYC = _deployVaultWithoutKYC();
        address anyUser = makeAddr("anyUser");
        assertTrue(vaultNoKYC.isKYCVerified(anyUser));
    }

    function test_SetZKMEVerifier_UpdatesVerifier() public {
        address newVerifier = makeAddr("newVerifier");

        vm.prank(admin);
        testVault.setZKMEVerifier(newVerifier);

        assertEq(testVault.zkmeVerifier(), newVerifier);
    }

    function test_SetZKMEVerifier_EmitsEvent() public {
        address newVerifier = makeAddr("newVerifier");

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit ISingleRWA_Vault.ZKMEVerifierUpdated(
            address(zkmeVerifier),
            newVerifier
        );
        testVault.setZKMEVerifier(newVerifier);
    }

    function test_SetZKMEVerifier_RevertWhen_NotAdmin() public {
        address newVerifier = makeAddr("newVerifier");

        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.NotAdmin.selector);
        testVault.setZKMEVerifier(newVerifier);
    }

    function test_SetCooperator_UpdatesCooperator() public {
        address newCooperator = makeAddr("newCooperator");

        vm.prank(admin);
        testVault.setCooperator(newCooperator);

        assertEq(testVault.cooperator(), newCooperator);
    }

    function test_SetCooperator_EmitsEvent() public {
        address newCooperator = makeAddr("newCooperator");

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit ISingleRWA_Vault.CooperatorUpdated(cooperator, newCooperator);
        testVault.setCooperator(newCooperator);
    }

    function test_SetCooperator_RevertWhen_NotAdmin() public {
        address newCooperator = makeAddr("newCooperator");

        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.NotAdmin.selector);
        testVault.setCooperator(newCooperator);
    }

    // ============================================
    // DEPOSIT TESTS
    // ============================================

    function test_Deposit_Success() public {
        uint256 shares = _approveAndDeposit(testVault, user1, DEPOSIT_AMOUNT);

        assertGt(shares, 0);
        assertEq(testVault.balanceOf(user1), shares);
        assertEq(testVault.userDeposited(user1), DEPOSIT_AMOUNT);
    }

    function test_Deposit_TransfersTokens() public {
        uint256 balanceBefore = usdc.balanceOf(user1);

        _approveAndDeposit(testVault, user1, DEPOSIT_AMOUNT);

        assertEq(usdc.balanceOf(user1), balanceBefore - DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(testVault)), DEPOSIT_AMOUNT);
    }

    function test_Deposit_WorksInFundingState() public {
        _assertVaultState(testVault, ISingleRWA_Vault.VaultState.Funding);
        _approveAndDeposit(testVault, user1, DEPOSIT_AMOUNT);
        assertGt(testVault.balanceOf(user1), 0);
    }

    function test_Deposit_WorksInActiveState() public {
        // Fund and activate vault
        _approveAndDeposit(testVault, user1, FUNDING_TARGET);
        vm.prank(operator);
        testVault.activateVault();

        _assertVaultState(testVault, ISingleRWA_Vault.VaultState.Active);

        // Deposit in active state
        _approveAndDeposit(testVault, user2, DEPOSIT_AMOUNT);
        assertGt(testVault.balanceOf(user2), 0);
    }

    function test_Deposit_RevertWhen_BelowMinimum() public {
        uint256 smallAmount = MIN_DEPOSIT - 1;

        vm.startPrank(user1);
        usdc.approve(address(testVault), smallAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleRWA_Vault.BelowMinimumDeposit.selector,
                smallAmount,
                MIN_DEPOSIT
            )
        );
        testVault.deposit(smallAmount, user1);
        vm.stopPrank();
    }

    function test_Deposit_RevertWhen_ExceedsMaxPerUser() public {
        uint256 largeAmount = MAX_DEPOSIT_PER_USER + 1;

        vm.startPrank(user1);
        usdc.approve(address(testVault), largeAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleRWA_Vault.ExceedsMaximumDeposit.selector,
                largeAmount,
                MAX_DEPOSIT_PER_USER
            )
        );
        testVault.deposit(largeAmount, user1);
        vm.stopPrank();
    }

    function test_Deposit_RevertWhen_CumulativeExceedsMax() public {
        // First deposit
        _approveAndDeposit(testVault, user1, MAX_DEPOSIT_PER_USER - 1000e6);

        // Second deposit that exceeds max
        vm.startPrank(user1);
        usdc.approve(address(testVault), 2000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleRWA_Vault.ExceedsMaximumDeposit.selector,
                2000e6,
                MAX_DEPOSIT_PER_USER
            )
        );
        testVault.deposit(2000e6, user1);
        vm.stopPrank();
    }

    function test_Deposit_RevertWhen_NotKYCVerified() public {
        address unapprovedUser = makeAddr("unapproved");
        usdc.mint(unapprovedUser, DEPOSIT_AMOUNT);

        vm.startPrank(unapprovedUser);
        usdc.approve(address(testVault), DEPOSIT_AMOUNT);

        vm.expectRevert(ISingleRWA_Vault.NotKYCVerified.selector);
        testVault.deposit(DEPOSIT_AMOUNT, unapprovedUser);
        vm.stopPrank();
    }

    function test_Deposit_RevertWhen_VaultPaused() public {
        vm.prank(operator);
        testVault.pause("Testing pause");

        vm.startPrank(user1);
        usdc.approve(address(testVault), DEPOSIT_AMOUNT);

        vm.expectRevert(ISingleRWA_Vault.VaultPaused.selector);
        testVault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
    }

    function test_Deposit_RevertWhen_VaultMatured() public {
        // Setup and mature vault
        _approveAndDeposit(testVault, user1, FUNDING_TARGET);
        vm.prank(operator);
        testVault.activateVault();

        vm.warp(testVault.maturityDate() + 1);
        vm.prank(operator);
        testVault.matureVault();

        // Try to deposit
        vm.startPrank(user2);
        usdc.approve(address(testVault), DEPOSIT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleRWA_Vault.InvalidVaultState.selector,
                ISingleRWA_Vault.VaultState.Matured,
                ISingleRWA_Vault.VaultState.Active
            )
        );
        testVault.deposit(DEPOSIT_AMOUNT, user2);
        vm.stopPrank();
    }

    // ============================================
    // MINT TESTS
    // ============================================

    function test_Mint_Success() public {
        uint256 sharesToMint = 1000e6;

        vm.startPrank(user1);
        usdc.approve(address(testVault), type(uint256).max);
        uint256 assets = testVault.mint(sharesToMint, user1);
        vm.stopPrank();

        assertEq(testVault.balanceOf(user1), sharesToMint);
        assertGt(assets, 0);
    }

    function test_Mint_RevertWhen_NotKYCVerified() public {
        address unapprovedUser = makeAddr("unapproved");
        usdc.mint(unapprovedUser, DEPOSIT_AMOUNT);

        vm.startPrank(unapprovedUser);
        usdc.approve(address(testVault), DEPOSIT_AMOUNT);

        vm.expectRevert(ISingleRWA_Vault.NotKYCVerified.selector);
        testVault.mint(1000e6, unapprovedUser);
        vm.stopPrank();
    }

    // ============================================
    // VAULT LIFECYCLE TESTS
    // ============================================

    function test_ActivateVault_Success() public {
        _approveAndDeposit(testVault, user1, FUNDING_TARGET);

        vm.prank(operator);
        testVault.activateVault();

        _assertVaultState(testVault, ISingleRWA_Vault.VaultState.Active);
    }

    function test_ActivateVault_EmitsEvent() public {
        _approveAndDeposit(testVault, user1, FUNDING_TARGET);

        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit ISingleRWA_Vault.VaultStateChanged(
            ISingleRWA_Vault.VaultState.Funding,
            ISingleRWA_Vault.VaultState.Active
        );
        testVault.activateVault();
    }

    function test_ActivateVault_RevertWhen_NotOperator() public {
        _approveAndDeposit(testVault, user1, FUNDING_TARGET);

        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.NotOperator.selector);
        testVault.activateVault();
    }

    function test_ActivateVault_RevertWhen_FundingTargetNotMet() public {
        _approveAndDeposit(testVault, user1, FUNDING_TARGET - 1);

        vm.prank(operator);
        vm.expectRevert(ISingleRWA_Vault.FundingTargetNotMet.selector);
        testVault.activateVault();
    }

    function test_ActivateVault_RevertWhen_NotInFundingState() public {
        _approveAndDeposit(testVault, user1, FUNDING_TARGET);

        vm.startPrank(operator);
        testVault.activateVault();

        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleRWA_Vault.InvalidVaultState.selector,
                ISingleRWA_Vault.VaultState.Active,
                ISingleRWA_Vault.VaultState.Funding
            )
        );
        testVault.activateVault();
        vm.stopPrank();
    }

    function test_MatureVault_Success() public {
        _approveAndDeposit(testVault, user1, FUNDING_TARGET);
        vm.prank(operator);
        testVault.activateVault();

        vm.warp(testVault.maturityDate() + 1);

        vm.prank(operator);
        testVault.matureVault();

        _assertVaultState(testVault, ISingleRWA_Vault.VaultState.Matured);
    }

    function test_MatureVault_EmitsEvent() public {
        _approveAndDeposit(testVault, user1, FUNDING_TARGET);
        vm.prank(operator);
        testVault.activateVault();

        vm.warp(testVault.maturityDate() + 1);

        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit ISingleRWA_Vault.VaultStateChanged(
            ISingleRWA_Vault.VaultState.Active,
            ISingleRWA_Vault.VaultState.Matured
        );
        testVault.matureVault();
    }

    function test_MatureVault_RevertWhen_BeforeMaturityDate() public {
        _approveAndDeposit(testVault, user1, FUNDING_TARGET);
        vm.prank(operator);
        testVault.activateVault();

        vm.prank(operator);
        vm.expectRevert(ISingleRWA_Vault.NotMatured.selector);
        testVault.matureVault();
    }

    function test_MatureVault_RevertWhen_NotInActiveState() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISingleRWA_Vault.InvalidVaultState.selector,
                ISingleRWA_Vault.VaultState.Funding,
                ISingleRWA_Vault.VaultState.Active
            )
        );
        testVault.matureVault();
    }

    function test_SetMaturityDate_Success() public {
        uint256 newMaturity = block.timestamp + 2 * ONE_YEAR;

        vm.prank(operator);
        testVault.setMaturityDate(newMaturity);

        assertEq(testVault.maturityDate(), newMaturity);
    }

    function test_SetMaturityDate_EmitsEvent() public {
        uint256 newMaturity = block.timestamp + 2 * ONE_YEAR;

        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit ISingleRWA_Vault.MaturityDateSet(newMaturity);
        testVault.setMaturityDate(newMaturity);
    }

    function test_IsFundingTargetMet_ReturnsCorrectValue() public {
        assertFalse(testVault.isFundingTargetMet());

        _approveAndDeposit(testVault, user1, FUNDING_TARGET);

        assertTrue(testVault.isFundingTargetMet());
    }

    function test_TimeToMaturity_ReturnsCorrectValue() public view {
        uint256 timeToMaturity = testVault.timeToMaturity();
        assertGt(timeToMaturity, 0);
        assertLe(timeToMaturity, ONE_YEAR);
    }

    function test_TimeToMaturity_ReturnsZeroAfterMaturity() public {
        vm.warp(testVault.maturityDate() + 1);
        assertEq(testVault.timeToMaturity(), 0);
    }

    // ============================================
    // DEPOSIT LIMITS TESTS
    // ============================================

    function test_SetDepositLimits_Success() public {
        uint256 newMin = 500e6;
        uint256 newMax = 500_000e6;

        vm.prank(operator);
        testVault.setDepositLimits(newMin, newMax);

        assertEq(testVault.minDeposit(), newMin);
        assertEq(testVault.maxDepositPerUser(), newMax);
    }

    function test_SetDepositLimits_EmitsEvent() public {
        uint256 newMin = 500e6;
        uint256 newMax = 500_000e6;

        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit ISingleRWA_Vault.DepositLimitsUpdated(newMin, newMax);
        testVault.setDepositLimits(newMin, newMax);
    }

    function test_SetDepositLimits_RevertWhen_NotOperator() public {
        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.NotOperator.selector);
        testVault.setDepositLimits(100e6, 1_000_000e6);
    }

    // ============================================
    // ACCESS CONTROL TESTS
    // ============================================

    function test_SetOperator_Success() public {
        address newOperator = makeAddr("newOperator");

        vm.prank(admin);
        testVault.setOperator(newOperator, true);

        assertTrue(testVault.isOperator(newOperator));
    }

    function test_SetOperator_CanRemove() public {
        vm.prank(admin);
        testVault.setOperator(operator, false);

        assertFalse(testVault.isOperator(operator));
    }

    function test_SetOperator_EmitsEvent() public {
        address newOperator = makeAddr("newOperator");

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit ISingleRWA_Vault.OperatorUpdated(newOperator, true);
        testVault.setOperator(newOperator, true);
    }

    function test_SetOperator_RevertWhen_NotAdmin() public {
        vm.prank(operator);
        vm.expectRevert(ISingleRWA_Vault.NotAdmin.selector);
        testVault.setOperator(user1, true);
    }

    function test_SetOperator_RevertWhen_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ISingleRWA_Vault.ZeroAddress.selector);
        testVault.setOperator(address(0), true);
    }

    function test_TransferAdmin_Success() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        testVault.transferAdmin(newAdmin);

        assertEq(testVault.admin(), newAdmin);
    }

    function test_TransferAdmin_RevertWhen_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.NotAdmin.selector);
        testVault.transferAdmin(user1);
    }

    function test_TransferAdmin_RevertWhen_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ISingleRWA_Vault.ZeroAddress.selector);
        testVault.transferAdmin(address(0));
    }

    // ============================================
    // EMERGENCY TESTS
    // ============================================

    function test_Pause_Success() public {
        vm.prank(operator);
        testVault.pause("Security incident");

        assertTrue(testVault.paused());
    }

    function test_Pause_EmitsEvent() public {
        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit ISingleRWA_Vault.EmergencyAction(true, "Security incident");
        testVault.pause("Security incident");
    }

    function test_Pause_RevertWhen_NotOperator() public {
        vm.prank(user1);
        vm.expectRevert(ISingleRWA_Vault.NotOperator.selector);
        testVault.pause("Not allowed");
    }

    function test_Unpause_Success() public {
        vm.startPrank(operator);
        testVault.pause("Testing");
        testVault.unpause();
        vm.stopPrank();

        assertFalse(testVault.paused());
    }

    function test_Unpause_EmitsEvent() public {
        vm.startPrank(operator);
        testVault.pause("Testing");

        vm.expectEmit(false, false, false, true);
        emit ISingleRWA_Vault.EmergencyAction(false, "");
        testVault.unpause();
        vm.stopPrank();
    }

    function test_EmergencyWithdraw_Success() public {
        _approveAndDeposit(testVault, user1, DEPOSIT_AMOUNT);

        uint256 vaultBalance = usdc.balanceOf(address(testVault));

        vm.prank(admin);
        testVault.emergencyWithdraw(recipient);

        assertEq(usdc.balanceOf(recipient), vaultBalance);
        assertEq(usdc.balanceOf(address(testVault)), 0);
        assertTrue(testVault.paused());
    }

    function test_EmergencyWithdraw_RevertWhen_NotAdmin() public {
        vm.prank(operator);
        vm.expectRevert(ISingleRWA_Vault.NotAdmin.selector);
        testVault.emergencyWithdraw(recipient);
    }

    function test_EmergencyWithdraw_RevertWhen_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ISingleRWA_Vault.ZeroAddress.selector);
        testVault.emergencyWithdraw(address(0));
    }

    // ============================================
    // VIEW FUNCTIONS TESTS
    // ============================================

    function test_CurrentAPY_ReturnsExpectedAPYWhenNoDistributions()
        public
        view
    {
        assertEq(testVault.currentAPY(), 500); // Expected APY from init
    }

    function test_ExpectedAPY_ReturnsConfiguredValue() public view {
        assertEq(testVault.expectedAPY(), 500);
    }
}
