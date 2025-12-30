// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title IVaultFactory
 * @notice Interface for creating and managing RWA vaults
 * @dev Supports both single-RWA vaults and the aggregator vault
 */
interface IVaultFactory {
    // ============================================
    // ENUMS
    // ============================================

    /**
     * @notice Type of vault
     * @param SingleRWA Vault dedicated to a single RWA investment
     * @param Aggregator Multi-RWA vault with AI/operator-managed allocation
     */
    enum VaultType {
        SingleRWA,
        Aggregator
    }

    // ============================================
    // STRUCTS
    // ============================================

    /**
     * @notice Vault registration information
     */
    struct VaultInfo {
        address vault;
        VaultType vaultType;
        string name;
        string symbol;
        bool active;
        uint256 createdAt;
    }

    // ============================================
    // EVENTS
    // ============================================

    /// @notice Emitted when a new vault is created
    event VaultCreated(
        address indexed vault,
        VaultType vaultType,
        string name,
        address indexed creator
    );

    /// @notice Emitted when a vault is activated/deactivated
    event VaultStatusChanged(address indexed vault, bool active);

    /// @notice Emitted when aggregator vault is set
    event AggregatorVaultSet(
        address indexed oldVault,
        address indexed newVault
    );

    // ============================================
    // ERRORS
    // ============================================

    /// @notice Thrown when vault already exists
    error VaultAlreadyExists();

    /// @notice Thrown when vault does not exist
    error VaultNotFound();

    /// @notice Thrown when caller is not authorized
    error NotAuthorized();

    // ============================================
    // FUNCTIONS
    // ============================================

    /**
     * @notice Create a new single-RWA vault
     * @param asset The deposit token address (e.g., USDC)
     * @param name Vault share token name
     * @param symbol Vault share token symbol
     * @param rwaName Name of the underlying RWA
     * @param rwaSymbol Symbol of the underlying RWA
     * @param rwaDocumentURI URI to legal documents
     * @param maturityDate Vault maturity timestamp
     * @return vault Address of the created vault
     */
    function createSingleRWAVault(
        address asset,
        string calldata name,
        string calldata symbol,
        string calldata rwaName,
        string calldata rwaSymbol,
        string calldata rwaDocumentURI,
        uint256 maturityDate
    ) external returns (address vault);

    /**
     * @notice Create the aggregator vault (only one can exist)
     * @param asset The deposit token address
     * @param name Vault share token name
     * @param symbol Vault share token symbol
     * @return vault Address of the created vault
     */
    function createAggregatorVault(
        address asset,
        string calldata name,
        string calldata symbol
    ) external returns (address vault);

    /**
     * @notice Get the aggregator vault address
     * @return Address of the aggregator vault
     */
    function aggregatorVault() external view returns (address);

    /**
     * @notice Get all registered vaults
     * @return Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory);

    /**
     * @notice Get all single-RWA vaults
     * @return Array of single-RWA vault addresses
     */
    function getSingleRWAVaults() external view returns (address[] memory);

    /**
     * @notice Get vault info
     * @param vault Address of the vault
     * @return VaultInfo struct
     */
    function getVaultInfo(
        address vault
    ) external view returns (VaultInfo memory);

    /**
     * @notice Check if address is a registered vault
     * @param vault Address to check
     * @return True if registered vault
     */
    function isRegisteredVault(address vault) external view returns (bool);

    /**
     * @notice Activate or deactivate a vault
     * @param vault Address of the vault
     * @param active New status
     */
    function setVaultStatus(address vault, bool active) external;
}
