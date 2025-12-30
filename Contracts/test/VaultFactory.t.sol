// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {SingleRWA_Vault} from "../src/SingleRWA_Vault.sol";
import {ISingleRWA_Vault} from "../interfaces/ISingleRWA_Vault.sol";
import {IVaultFactory} from "../interfaces/IVaultFactory.sol";

/**
 * @title VaultFactoryTest
 * @notice Comprehensive tests for VaultFactory contract
 */
contract VaultFactoryTest is BaseTest {
    VaultFactory public testFactory;

    function setUp() public override {
        super.setUp();
        testFactory = _deployFactory();
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsAdmin() public view {
        assertEq(testFactory.admin(), admin);
    }

    function test_Constructor_SetsDefaultAsset() public view {
        assertEq(testFactory.defaultAsset(), address(usdc));
    }

    function test_Constructor_SetsDefaultZkmeVerifier() public view {
        assertEq(testFactory.defaultZkmeVerifier(), address(zkmeVerifier));
    }

    function test_Constructor_SetsDefaultCooperator() public view {
        assertEq(testFactory.defaultCooperator(), cooperator);
    }

    function test_Constructor_SetsAdminAsOperator() public view {
        assertTrue(testFactory.operators(admin));
    }

    function test_Constructor_RevertWhen_ZeroAdmin() public {
        vm.expectRevert("Zero admin");
        new VaultFactory(
            address(0),
            address(usdc),
            address(zkmeVerifier),
            cooperator
        );
    }

    // ============================================
    // CREATE SINGLE RWA VAULT TESTS
    // ============================================

    function test_CreateSingleRWAVault_Success() public {
        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );

        assertTrue(vaultAddress != address(0));
        assertTrue(testFactory.isRegisteredVault(vaultAddress));
    }

    function test_CreateSingleRWAVault_RegistersVault() public {
        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );

        IVaultFactory.VaultInfo memory info = testFactory.getVaultInfo(
            vaultAddress
        );
        assertEq(info.vault, vaultAddress);
        assertEq(
            uint256(info.vaultType),
            uint256(IVaultFactory.VaultType.SingleRWA)
        );
        assertEq(info.name, "Test Vault");
        assertEq(info.symbol, "TV");
        assertTrue(info.active);
        assertEq(info.createdAt, block.timestamp);
    }

    function test_CreateSingleRWAVault_AddsToAllVaults() public {
        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );

        address[] memory allVaults = testFactory.getAllVaults();
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], vaultAddress);
    }

    function test_CreateSingleRWAVault_AddsToSingleRWAVaults() public {
        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );

        address[] memory singleVaults = testFactory.getSingleRWAVaults();
        assertEq(singleVaults.length, 1);
        assertEq(singleVaults[0], vaultAddress);
    }

    function test_CreateSingleRWAVault_EmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, false);
        emit IVaultFactory.VaultCreated(
            address(0), // We don't know the address yet
            IVaultFactory.VaultType.SingleRWA,
            "Test Vault",
            admin
        );
        testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );
    }

    function test_CreateSingleRWAVault_UsesDefaultAsset() public {
        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVault(
            address(0), // Use default
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );

        SingleRWA_Vault vault = SingleRWA_Vault(vaultAddress);
        assertEq(vault.asset(), address(usdc));
    }

    function test_CreateSingleRWAVault_SetsDefaults() public {
        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );

        SingleRWA_Vault vault = SingleRWA_Vault(vaultAddress);
        assertEq(vault.zkmeVerifier(), address(zkmeVerifier));
        assertEq(vault.cooperator(), cooperator);
        assertEq(vault.earlyRedemptionFeeBps(), 200); // Default 2%
    }

    function test_CreateSingleRWAVault_RevertWhen_NotOperator() public {
        vm.prank(user1);
        vm.expectRevert(IVaultFactory.NotAuthorized.selector);
        testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );
    }

    function test_CreateSingleRWAVault_RevertWhen_NoAsset() public {
        // Set default asset to zero
        vm.prank(admin);
        testFactory.setDefaults(address(0), address(zkmeVerifier), cooperator);

        vm.prank(admin);
        vm.expectRevert("No asset specified");
        testFactory.createSingleRWAVault(
            address(0),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );
    }

    // ============================================
    // CREATE SINGLE RWA VAULT FULL TESTS
    // ============================================

    function test_CreateSingleRWAVaultFull_Success() public {
        ISingleRWA_Vault.RWADetails memory rwaDetails = ISingleRWA_Vault
            .RWADetails({
                name: "US Treasury 6M",
                symbol: "USTB6M",
                documentURI: "ipfs://docs",
                category: "Treasury",
                expectedAPY: 500
            });

        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVaultFull(
            address(usdc),
            "Full Vault",
            "FV",
            rwaDetails,
            block.timestamp + ONE_YEAR,
            100_000e6, // fundingTarget
            1_000e6, // minDeposit
            50_000e6, // maxDepositPerUser
            100 // earlyRedemptionFeeBps (1%)
        );

        SingleRWA_Vault vault = SingleRWA_Vault(vaultAddress);
        assertEq(vault.fundingTarget(), 100_000e6);
        assertEq(vault.minDeposit(), 1_000e6);
        assertEq(vault.maxDepositPerUser(), 50_000e6);
        assertEq(vault.earlyRedemptionFeeBps(), 100);

        ISingleRWA_Vault.RWADetails memory details = vault.getRWADetails();
        assertEq(details.name, "US Treasury 6M");
        assertEq(details.category, "Treasury");
        assertEq(details.expectedAPY, 500);
    }

    // ============================================
    // VAULT MANAGEMENT TESTS
    // ============================================

    function test_SetVaultStatus_Success() public {
        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );

        vm.prank(admin);
        testFactory.setVaultStatus(vaultAddress, false);

        IVaultFactory.VaultInfo memory info = testFactory.getVaultInfo(
            vaultAddress
        );
        assertFalse(info.active);
    }

    function test_SetVaultStatus_EmitsEvent() public {
        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IVaultFactory.VaultStatusChanged(vaultAddress, false);
        testFactory.setVaultStatus(vaultAddress, false);
    }

    function test_SetVaultStatus_RevertWhen_NotAdmin() public {
        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );

        vm.prank(operator);
        vm.expectRevert(IVaultFactory.NotAuthorized.selector);
        testFactory.setVaultStatus(vaultAddress, false);
    }

    function test_SetVaultStatus_RevertWhen_VaultNotFound() public {
        vm.prank(admin);
        vm.expectRevert(IVaultFactory.VaultNotFound.selector);
        testFactory.setVaultStatus(address(0x123), false);
    }

    // ============================================
    // VIEW FUNCTIONS TESTS
    // ============================================

    function test_GetVaultCount_ReturnsCorrectCount() public {
        assertEq(testFactory.getVaultCount(), 0);

        vm.startPrank(admin);
        testFactory.createSingleRWAVault(
            address(usdc),
            "Vault 1",
            "V1",
            "RWA 1",
            "R1",
            "ipfs://1",
            block.timestamp + ONE_YEAR
        );
        testFactory.createSingleRWAVault(
            address(usdc),
            "Vault 2",
            "V2",
            "RWA 2",
            "R2",
            "ipfs://2",
            block.timestamp + ONE_YEAR
        );
        vm.stopPrank();

        assertEq(testFactory.getVaultCount(), 2);
    }

    function test_GetActiveVaults_ReturnsOnlyActive() public {
        vm.startPrank(admin);
        address vault1 = testFactory.createSingleRWAVault(
            address(usdc),
            "Vault 1",
            "V1",
            "RWA 1",
            "R1",
            "ipfs://1",
            block.timestamp + ONE_YEAR
        );
        address vault2 = testFactory.createSingleRWAVault(
            address(usdc),
            "Vault 2",
            "V2",
            "RWA 2",
            "R2",
            "ipfs://2",
            block.timestamp + ONE_YEAR
        );

        testFactory.setVaultStatus(vault1, false);
        vm.stopPrank();

        address[] memory activeVaults = testFactory.getActiveVaults();
        assertEq(activeVaults.length, 1);
        assertEq(activeVaults[0], vault2);
    }

    function test_GetVaultsByCategory_ReturnsCorrectVaults() public {
        ISingleRWA_Vault.RWADetails memory treasuryDetails = ISingleRWA_Vault
            .RWADetails({
                name: "Treasury",
                symbol: "TB",
                documentURI: "ipfs://tb",
                category: "Treasury",
                expectedAPY: 500
            });

        ISingleRWA_Vault.RWADetails memory realEstateDetails = ISingleRWA_Vault
            .RWADetails({
                name: "Real Estate",
                symbol: "RE",
                documentURI: "ipfs://re",
                category: "Real Estate",
                expectedAPY: 800
            });

        vm.startPrank(admin);
        testFactory.createSingleRWAVaultFull(
            address(usdc),
            "Treasury Vault",
            "TV",
            treasuryDetails,
            block.timestamp + ONE_YEAR,
            0,
            0,
            0,
            200
        );
        testFactory.createSingleRWAVaultFull(
            address(usdc),
            "RE Vault",
            "REV",
            realEstateDetails,
            block.timestamp + ONE_YEAR,
            0,
            0,
            0,
            200
        );
        testFactory.createSingleRWAVaultFull(
            address(usdc),
            "Treasury Vault 2",
            "TV2",
            treasuryDetails,
            block.timestamp + ONE_YEAR,
            0,
            0,
            0,
            200
        );
        vm.stopPrank();

        address[] memory treasuryVaults = testFactory.getVaultsByCategory(
            "Treasury"
        );
        address[] memory reVaults = testFactory.getVaultsByCategory(
            "Real Estate"
        );

        assertEq(treasuryVaults.length, 2);
        assertEq(reVaults.length, 1);
    }

    function test_IsRegisteredVault_ReturnsCorrectValue() public {
        assertFalse(testFactory.isRegisteredVault(address(0x123)));

        vm.prank(admin);
        address vaultAddress = testFactory.createSingleRWAVault(
            address(usdc),
            "Test Vault",
            "TV",
            "Test RWA",
            "TRWA",
            "ipfs://docs",
            block.timestamp + ONE_YEAR
        );

        assertTrue(testFactory.isRegisteredVault(vaultAddress));
    }

    // ============================================
    // ADMIN FUNCTIONS TESTS
    // ============================================

    function test_TransferAdmin_Success() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        testFactory.transferAdmin(newAdmin);

        assertEq(testFactory.admin(), newAdmin);
    }

    function test_TransferAdmin_EmitsEvent() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit VaultFactory.AdminTransferred(admin, newAdmin);
        testFactory.transferAdmin(newAdmin);
    }

    function test_TransferAdmin_RevertWhen_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(IVaultFactory.NotAuthorized.selector);
        testFactory.transferAdmin(user1);
    }

    function test_TransferAdmin_RevertWhen_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Zero address");
        testFactory.transferAdmin(address(0));
    }

    function test_SetOperator_Success() public {
        vm.prank(admin);
        testFactory.setOperator(operator, true);

        assertTrue(testFactory.operators(operator));
    }

    function test_SetOperator_CanRemove() public {
        vm.startPrank(admin);
        testFactory.setOperator(operator, true);
        testFactory.setOperator(operator, false);
        vm.stopPrank();

        assertFalse(testFactory.operators(operator));
    }

    function test_SetOperator_EmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit VaultFactory.OperatorUpdated(operator, true);
        testFactory.setOperator(operator, true);
    }

    function test_SetOperator_RevertWhen_NotAdmin() public {
        vm.prank(operator);
        vm.expectRevert(IVaultFactory.NotAuthorized.selector);
        testFactory.setOperator(user1, true);
    }

    function test_SetOperator_RevertWhen_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Zero address");
        testFactory.setOperator(address(0), true);
    }

    function test_SetDefaults_Success() public {
        address newAsset = makeAddr("newAsset");
        address newVerifier = makeAddr("newVerifier");
        address newCooperator = makeAddr("newCooperator");

        vm.prank(admin);
        testFactory.setDefaults(newAsset, newVerifier, newCooperator);

        assertEq(testFactory.defaultAsset(), newAsset);
        assertEq(testFactory.defaultZkmeVerifier(), newVerifier);
        assertEq(testFactory.defaultCooperator(), newCooperator);
    }

    function test_SetDefaults_EmitsEvent() public {
        address newAsset = makeAddr("newAsset");
        address newVerifier = makeAddr("newVerifier");
        address newCooperator = makeAddr("newCooperator");

        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit VaultFactory.DefaultsUpdated(newAsset, newVerifier, newCooperator);
        testFactory.setDefaults(newAsset, newVerifier, newCooperator);
    }

    function test_SetDefaults_RevertWhen_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(IVaultFactory.NotAuthorized.selector);
        testFactory.setDefaults(address(0), address(0), address(0));
    }

    // ============================================
    // BATCH CREATE TESTS
    // ============================================

    function test_BatchCreateVaults_Success() public {
        VaultFactory.BatchVaultParams[]
            memory params = new VaultFactory.BatchVaultParams[](3);

        for (uint256 i = 0; i < 3; i++) {
            params[i] = VaultFactory.BatchVaultParams({
                asset: address(usdc),
                name: string(abi.encodePacked("Vault ", i)),
                symbol: string(abi.encodePacked("V", i)),
                rwaDetails: ISingleRWA_Vault.RWADetails({
                    name: string(abi.encodePacked("RWA ", i)),
                    symbol: string(abi.encodePacked("R", i)),
                    documentURI: "ipfs://docs",
                    category: "Treasury",
                    expectedAPY: 500
                }),
                maturityDate: block.timestamp + ONE_YEAR,
                fundingTarget: 0,
                minDeposit: 0,
                maxDepositPerUser: 0,
                earlyRedemptionFeeBps: 200
            });
        }

        vm.prank(admin);
        address[] memory vaults = testFactory.batchCreateVaults(params);

        assertEq(vaults.length, 3);
        assertEq(testFactory.getVaultCount(), 3);

        for (uint256 i = 0; i < 3; i++) {
            assertTrue(testFactory.isRegisteredVault(vaults[i]));
        }
    }

    function test_BatchCreateVaults_RevertWhen_NotOperator() public {
        VaultFactory.BatchVaultParams[]
            memory params = new VaultFactory.BatchVaultParams[](1);

        params[0] = VaultFactory.BatchVaultParams({
            asset: address(usdc),
            name: "Vault",
            symbol: "V",
            rwaDetails: ISingleRWA_Vault.RWADetails({
                name: "RWA",
                symbol: "R",
                documentURI: "ipfs://docs",
                category: "Treasury",
                expectedAPY: 500
            }),
            maturityDate: block.timestamp + ONE_YEAR,
            fundingTarget: 0,
            minDeposit: 0,
            maxDepositPerUser: 0,
            earlyRedemptionFeeBps: 200
        });

        vm.prank(user1);
        vm.expectRevert(IVaultFactory.NotAuthorized.selector);
        testFactory.batchCreateVaults(params);
    }

    // ============================================
    // AGGREGATOR VAULT TESTS
    // ============================================

    function test_CreateAggregatorVault_Reverts() public {
        vm.prank(admin);
        vm.expectRevert("Aggregator vault not supported");
        testFactory.createAggregatorVault(address(usdc), "Agg", "AGG");
    }

    function test_AggregatorVault_ReturnsZero() public view {
        assertEq(testFactory.aggregatorVault(), address(0));
    }
}
