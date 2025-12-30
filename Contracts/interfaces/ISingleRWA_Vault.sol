// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IZKMEVerify
 * @notice Minimal interface for zkMe verification contract
 */
interface IZKMEVerify {
    function hasApproved(
        address cooperator,
        address user
    ) external view returns (bool);
}

/**
 * @title ISingleRWA_Vault
 * @notice Interface for a Single Real World Asset Yield Vault
 * @dev Each vault represents ONE specific RWA investment (e.g., a specific T-Bill, bond, etc.)
 *      Users deposit a stable asset and receive shares representing their stake in that RWA
 */
interface ISingleRWA_Vault is IERC4626 {
    // ============================================
    // ENUMS
    // ============================================

    /**
     * @notice Vault lifecycle states
     */
    enum VaultState {
        Funding, // Accepting deposits to reach funding target
        Active, // RWA investment is active, generating yield
        Matured, // Investment matured, redemptions enabled
        Closed // Vault is closed
    }

    // ============================================
    // STRUCTS
    // ============================================

    /**
     * @notice RWA details for this vault
     */
    struct RWADetails {
        string name; // e.g., "US Treasury 6-Month Bill"
        string symbol; // e.g., "USTB6M"
        string documentURI; // URI to legal/compliance documents
        string category; // e.g., "Treasury", "Corporate Bond", "Real Estate"
        uint256 expectedAPY; // Expected annual yield in basis points
    }

    /**
     * @notice Initialization parameters
     */
    struct InitParams {
        address asset; // Deposit token (e.g., USDC)
        string name; // Vault share token name
        string symbol; // Vault share token symbol
        address admin; // Admin address
        address zkmeVerifier; // zkMe verifier contract
        address cooperator; // zkMe cooperator address
        uint256 fundingTarget; // Minimum funding amount
        uint256 maturityDate; // Vault maturity timestamp
        uint256 minDeposit; // Minimum deposit per transaction
        uint256 maxDepositPerUser; // Max deposit per user (0 = no limit)
        uint256 earlyRedemptionFeeBps; // Early exit fee in basis points
        RWADetails rwaDetails; // RWA information
    }

    // ============================================
    // EVENTS
    // ============================================

    event ZKMEVerifierUpdated(
        address indexed oldVerifier,
        address indexed newVerifier
    );
    event CooperatorUpdated(
        address indexed oldCooperator,
        address indexed newCooperator
    );
    event YieldDistributed(
        uint256 indexed epoch,
        uint256 amount,
        uint256 timestamp
    );
    event YieldClaimed(
        address indexed user,
        uint256 amount,
        uint256 indexed epoch
    );
    event VaultStateChanged(VaultState oldState, VaultState newState);
    event MaturityDateSet(uint256 maturityDate);
    event DepositLimitsUpdated(uint256 minDeposit, uint256 maxDeposit);
    event OperatorUpdated(address indexed operator, bool status);
    event EmergencyAction(bool paused, string reason);

    // ============================================
    // ERRORS
    // ============================================

    error NotKYCVerified();
    error ZKMEVerifierNotSet();
    error NotOperator();
    error NotAdmin();
    error InvalidVaultState(VaultState current, VaultState expected);
    error BelowMinimumDeposit(uint256 amount, uint256 minimum);
    error ExceedsMaximumDeposit(uint256 amount, uint256 maximum);
    error NotMatured();
    error NoYieldToClaim();
    error FundingTargetNotMet();
    error VaultPaused();
    error ZeroAddress();
    error ZeroAmount();

    // ============================================
    // RWA DETAILS
    // ============================================

    /**
     * @notice Get the RWA details for this vault
     */
    function getRWADetails() external view returns (RWADetails memory);

    /**
     * @notice Get RWA name
     */
    function rwaName() external view returns (string memory);

    /**
     * @notice Get RWA symbol
     */
    function rwaSymbol() external view returns (string memory);

    /**
     * @notice Get RWA document URI
     */
    function rwaDocumentURI() external view returns (string memory);

    /**
     * @notice Get RWA category
     */
    function rwaCategory() external view returns (string memory);

    // ============================================
    // KYC VERIFICATION
    // ============================================

    function isKYCVerified(address user) external view returns (bool);

    function zkmeVerifier() external view returns (address);

    function cooperator() external view returns (address);

    function setZKMEVerifier(address verifier) external;

    function setCooperator(address newCooperator) external;

    // ============================================
    // YIELD DISTRIBUTION
    // ============================================

    function distributeYield(uint256 amount) external returns (uint256 epoch);

    function claimYield() external returns (uint256 amount);

    function claimYieldForEpoch(
        uint256 epoch
    ) external returns (uint256 amount);

    function pendingYield(address user) external view returns (uint256);

    function pendingYieldForEpoch(
        address user,
        uint256 epoch
    ) external view returns (uint256);

    function currentEpoch() external view returns (uint256);

    function epochYield(uint256 epoch) external view returns (uint256);

    function totalYieldDistributed() external view returns (uint256);

    function totalYieldClaimed(address user) external view returns (uint256);

    // ============================================
    // VAULT LIFECYCLE
    // ============================================

    function vaultState() external view returns (VaultState);

    function activateVault() external;

    function matureVault() external;

    function maturityDate() external view returns (uint256);

    function setMaturityDate(uint256 timestamp) external;

    function fundingTarget() external view returns (uint256);

    function isFundingTargetMet() external view returns (bool);

    function timeToMaturity() external view returns (uint256);

    // ============================================
    // DEPOSIT LIMITS
    // ============================================

    function minDeposit() external view returns (uint256);

    function maxDepositPerUser() external view returns (uint256);

    function setDepositLimits(uint256 minAmount, uint256 maxAmount) external;

    function userDeposited(address user) external view returns (uint256);

    // ============================================
    // REDEMPTION
    // ============================================

    function redeemAtMaturity(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);

    function requestEarlyRedemption(
        uint256 shares
    ) external returns (uint256 requestId);

    function earlyRedemptionFeeBps() external view returns (uint256);

    // ============================================
    // ACCESS CONTROL
    // ============================================

    function admin() external view returns (address);

    function isOperator(address account) external view returns (bool);

    function setOperator(address operator, bool status) external;

    function transferAdmin(address newAdmin) external;

    // ============================================
    // EMERGENCY
    // ============================================

    function pause(string calldata reason) external;

    function unpause() external;

    function paused() external view returns (bool);

    function emergencyWithdraw(address recipient) external;

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    function currentAPY() external view returns (uint256);
}
