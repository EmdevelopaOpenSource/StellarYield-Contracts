// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISingleRWA_Vault, IZKMEVerify} from "../interfaces/ISingleRWA_Vault.sol";

/**
 * @title SingleRWA_Vault
 * @notice ERC4626 vault for a SINGLE Real World Asset investment
 * @dev Each vault instance represents one specific RWA (e.g., a Treasury Bill, corporate bond, etc.)
 *      Users deposit a stable asset (USDC) and receive vault shares representing their stake
 *
 *      Key Features:
 *      - One vault = One RWA investment
 *      - zkMe KYC verification for compliance
 *      - Yield distribution per epoch
 *      - Vault lifecycle: Funding → Active → Matured
 *      - Early redemption with fees
 */
contract SingleRWA_Vault is ERC4626, ReentrancyGuard, ISingleRWA_Vault {
    using SafeERC20 for IERC20;

    // ============================================
    // STATE VARIABLES
    // ============================================

    // --- RWA Details (Immutable after deployment) ---
    string private _rwaName;
    string private _rwaSymbol;
    string private _rwaDocumentURI;
    string private _rwaCategory;
    uint256 private _expectedAPY;

    // --- Access Control ---
    address public override admin;
    mapping(address => bool) private _operators;

    // --- zkMe KYC ---
    address public override zkmeVerifier;
    address public override cooperator;

    // --- Vault State ---
    VaultState private _vaultState;
    bool private _paused;

    // --- Vault Configuration ---
    uint256 public override maturityDate;
    uint256 public override fundingTarget;
    uint256 public override minDeposit;
    uint256 public override maxDepositPerUser;
    uint256 public override earlyRedemptionFeeBps;

    // --- User Tracking ---
    mapping(address => uint256) public override userDeposited;

    // --- Yield Distribution ---
    uint256 public override currentEpoch;
    uint256 public override totalYieldDistributed;
    mapping(address => uint256) public override totalYieldClaimed;
    mapping(uint256 => uint256) public override epochYield;
    mapping(uint256 => uint256) public epochTotalShares;
    mapping(address => mapping(uint256 => bool)) public hasClaimedEpoch;
    mapping(address => mapping(uint256 => uint256)) public userSharesAtEpoch;
    mapping(address => mapping(uint256 => bool)) public hasSnapshotForEpoch;
    mapping(address => uint256) public lastInteractionEpoch;

    // --- Early Redemption ---
    uint256 private _redemptionRequestCounter;
    struct RedemptionRequest {
        address user;
        uint256 shares;
        uint256 requestTime;
        bool processed;
    }
    mapping(uint256 => RedemptionRequest) public redemptionRequests;

    // ============================================
    // MODIFIERS
    // ============================================

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyOperator() {
        _onlyOperator();
        _;
    }

    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    modifier onlyKYCVerified(address user) {
        _onlyKYCVerified(user);
        _;
    }

    modifier inState(VaultState expected) {
        _inState(expected);
        _;
    }

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Creates a new Single RWA Vault
     * @param params Initialization parameters
     */
    constructor(
        InitParams memory params
    ) ERC4626(IERC20(params.asset)) ERC20(params.name, params.symbol) {
        if (params.admin == address(0)) revert ZeroAddress();

        // Set RWA details (immutable)
        _rwaName = params.rwaDetails.name;
        _rwaSymbol = params.rwaDetails.symbol;
        _rwaDocumentURI = params.rwaDetails.documentURI;
        _rwaCategory = params.rwaDetails.category;
        _expectedAPY = params.rwaDetails.expectedAPY;

        // Set admin and config
        admin = params.admin;
        zkmeVerifier = params.zkmeVerifier;
        cooperator = params.cooperator;
        fundingTarget = params.fundingTarget;
        maturityDate = params.maturityDate;
        minDeposit = params.minDeposit;
        maxDepositPerUser = params.maxDepositPerUser;
        earlyRedemptionFeeBps = params.earlyRedemptionFeeBps;

        _vaultState = VaultState.Funding;
        _operators[params.admin] = true;
    }

    // ============================================
    // MODIFIER FUNCTIONS
    // ============================================

    function _onlyAdmin() internal view {
        if (msg.sender != admin) revert NotAdmin();
    }

    function _onlyOperator() internal view {
        if (!_operators[msg.sender] && msg.sender != admin)
            revert NotOperator();
    }

    function _whenNotPaused() internal view {
        if (_paused) revert VaultPaused();
    }

    function _onlyKYCVerified(address user) internal view {
        if (isKYCVerified(user)) revert NotKYCVerified();
    }

    function _inState(VaultState expected) internal view {
        if (_vaultState != expected) {
            revert InvalidVaultState(_vaultState, expected);
        }
    }

    // ============================================
    // RWA DETAILS
    // ============================================

    /// @inheritdoc ISingleRWA_Vault
    function getRWADetails()
        external
        view
        override
        returns (RWADetails memory)
    {
        return
            RWADetails({
                name: _rwaName,
                symbol: _rwaSymbol,
                documentURI: _rwaDocumentURI,
                category: _rwaCategory,
                expectedAPY: _expectedAPY
            });
    }

    /// @inheritdoc ISingleRWA_Vault
    function rwaName() external view override returns (string memory) {
        return _rwaName;
    }

    /// @inheritdoc ISingleRWA_Vault
    function rwaSymbol() external view override returns (string memory) {
        return _rwaSymbol;
    }

    /// @inheritdoc ISingleRWA_Vault
    function rwaDocumentURI() external view override returns (string memory) {
        return _rwaDocumentURI;
    }

    /// @inheritdoc ISingleRWA_Vault
    function rwaCategory() external view override returns (string memory) {
        return _rwaCategory;
    }

    // ============================================
    // ZKME KYC VERIFICATION
    // ============================================

    /// @inheritdoc ISingleRWA_Vault
    function isKYCVerified(address user) public view override returns (bool) {
        if (zkmeVerifier == address(0)) {
            // If no verifier set, allow all (for testing/gradual rollout)
            return true;
        }
        return IZKMEVerify(zkmeVerifier).hasApproved(cooperator, user);
    }

    /// @inheritdoc ISingleRWA_Vault
    function setZKMEVerifier(address verifier) external override onlyAdmin {
        address oldVerifier = zkmeVerifier;
        zkmeVerifier = verifier;
        emit ZKMEVerifierUpdated(oldVerifier, verifier);
    }

    /// @inheritdoc ISingleRWA_Vault
    function setCooperator(address newCooperator) external override onlyAdmin {
        address oldCooperator = cooperator;
        cooperator = newCooperator;
        emit CooperatorUpdated(oldCooperator, newCooperator);
    }

    // ============================================
    // ERC4626 OVERRIDES WITH KYC & LIMITS
    // ============================================

    /// @dev Override deposit to add KYC check and limits
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        virtual
        override(ERC4626, IERC4626)
        whenNotPaused
        onlyKYCVerified(msg.sender)
        returns (uint256)
    {
        if (
            _vaultState != VaultState.Funding &&
            _vaultState != VaultState.Active
        ) {
            revert InvalidVaultState(_vaultState, VaultState.Active);
        }
        if (assets < minDeposit) revert BelowMinimumDeposit(assets, minDeposit);
        if (
            maxDepositPerUser > 0 &&
            userDeposited[receiver] + assets > maxDepositPerUser
        ) {
            revert ExceedsMaximumDeposit(assets, maxDepositPerUser);
        }

        _updateUserSnapshot(receiver);
        userDeposited[receiver] += assets;

        return super.deposit(assets, receiver);
    }

    /// @dev Override mint to add KYC check
    function mint(
        uint256 shares,
        address receiver
    )
        public
        virtual
        override(ERC4626, IERC4626)
        whenNotPaused
        onlyKYCVerified(msg.sender)
        returns (uint256)
    {
        if (
            _vaultState != VaultState.Funding &&
            _vaultState != VaultState.Active
        ) {
            revert InvalidVaultState(_vaultState, VaultState.Active);
        }

        uint256 assets = previewMint(shares);
        if (assets < minDeposit) revert BelowMinimumDeposit(assets, minDeposit);
        if (
            maxDepositPerUser > 0 &&
            userDeposited[receiver] + assets > maxDepositPerUser
        ) {
            revert ExceedsMaximumDeposit(assets, maxDepositPerUser);
        }

        _updateUserSnapshot(receiver);
        userDeposited[receiver] += assets;

        return super.mint(shares, receiver);
    }

    /// @dev Override withdraw to add checks
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        virtual
        override(ERC4626, IERC4626)
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        _updateUserSnapshot(owner);
        return super.withdraw(assets, receiver, owner);
    }

    /// @dev Override redeem to add checks
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        virtual
        override(ERC4626, IERC4626)
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        _updateUserSnapshot(owner);
        return super.redeem(shares, receiver, owner);
    }

    /// @dev Override transfer to update snapshots
    function transfer(
        address to,
        uint256 amount
    ) public virtual override(ERC20, IERC20) returns (bool) {
        _updateUserSnapshot(msg.sender);
        _updateUserSnapshot(to);
        return super.transfer(to, amount);
    }

    /// @dev Override transferFrom to update snapshots
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override(ERC20, IERC20) returns (bool) {
        _updateUserSnapshot(from);
        _updateUserSnapshot(to);
        return super.transferFrom(from, to, amount);
    }

    // ============================================
    // YIELD DISTRIBUTION
    // ============================================

    /// @inheritdoc ISingleRWA_Vault
    function distributeYield(
        uint256 amount
    ) external override onlyOperator whenNotPaused returns (uint256 epoch) {
        if (amount == 0) revert ZeroAmount();
        if (_vaultState != VaultState.Active) {
            revert InvalidVaultState(_vaultState, VaultState.Active);
        }

        // Transfer yield into vault
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        currentEpoch++;
        epoch = currentEpoch;

        epochYield[epoch] = amount;
        epochTotalShares[epoch] = totalSupply();
        totalYieldDistributed += amount;

        emit YieldDistributed(epoch, amount, block.timestamp);

        return epoch;
    }

    /// @inheritdoc ISingleRWA_Vault
    function claimYield()
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 amount)
    {
        amount = pendingYield(msg.sender);
        if (amount == 0) revert NoYieldToClaim();

        // Mark all epochs as claimed
        for (uint256 i = 1; i <= currentEpoch; i++) {
            if (
                !hasClaimedEpoch[msg.sender][i] &&
                _getUserSharesForEpoch(msg.sender, i) > 0
            ) {
                hasClaimedEpoch[msg.sender][i] = true;
            }
        }

        totalYieldClaimed[msg.sender] += amount;
        IERC20(asset()).safeTransfer(msg.sender, amount);

        emit YieldClaimed(msg.sender, amount, currentEpoch);
        return amount;
    }

    /// @inheritdoc ISingleRWA_Vault
    function claimYieldForEpoch(
        uint256 epoch
    ) external override whenNotPaused nonReentrant returns (uint256 amount) {
        if (hasClaimedEpoch[msg.sender][epoch]) revert NoYieldToClaim();

        amount = pendingYieldForEpoch(msg.sender, epoch);
        if (amount == 0) revert NoYieldToClaim();

        hasClaimedEpoch[msg.sender][epoch] = true;
        totalYieldClaimed[msg.sender] += amount;

        IERC20(asset()).safeTransfer(msg.sender, amount);

        emit YieldClaimed(msg.sender, amount, epoch);
        return amount;
    }

    /// @inheritdoc ISingleRWA_Vault
    function pendingYield(
        address user
    ) public view override returns (uint256 total) {
        for (uint256 i = 1; i <= currentEpoch; i++) {
            if (!hasClaimedEpoch[user][i]) {
                total += pendingYieldForEpoch(user, i);
            }
        }
        return total;
    }

    /// @inheritdoc ISingleRWA_Vault
    function pendingYieldForEpoch(
        address user,
        uint256 epoch
    ) public view override returns (uint256) {
        if (
            epoch == 0 || epoch > currentEpoch || hasClaimedEpoch[user][epoch]
        ) {
            return 0;
        }

        uint256 userShares = _getUserSharesForEpoch(user, epoch);
        uint256 totalShares = epochTotalShares[epoch];

        if (totalShares == 0 || userShares == 0) return 0;

        return (epochYield[epoch] * userShares) / totalShares;
    }

    /// @dev Get user's share balance for a specific epoch
    function _getUserSharesForEpoch(
        address user,
        uint256 epoch
    ) internal view returns (uint256) {
        if (hasSnapshotForEpoch[user][epoch]) {
            return userSharesAtEpoch[user][epoch];
        }
        return balanceOf(user);
    }

    /// @dev Update user snapshot for yield tracking
    function _updateUserSnapshot(address user) internal {
        uint256 lastEpoch = lastInteractionEpoch[user];
        uint256 currentBal = balanceOf(user);

        for (uint256 i = lastEpoch + 1; i <= currentEpoch; i++) {
            if (!hasSnapshotForEpoch[user][i]) {
                userSharesAtEpoch[user][i] = currentBal;
                hasSnapshotForEpoch[user][i] = true;
            }
        }

        lastInteractionEpoch[user] = currentEpoch;
    }

    // ============================================
    // VAULT LIFECYCLE
    // ============================================

    /// @inheritdoc ISingleRWA_Vault
    function vaultState() external view override returns (VaultState) {
        return _vaultState;
    }

    /// @inheritdoc ISingleRWA_Vault
    function activateVault()
        external
        override
        onlyOperator
        inState(VaultState.Funding)
    {
        if (!isFundingTargetMet()) revert FundingTargetNotMet();

        VaultState oldState = _vaultState;
        _vaultState = VaultState.Active;

        emit VaultStateChanged(oldState, VaultState.Active);
    }

    /// @inheritdoc ISingleRWA_Vault
    function matureVault()
        external
        override
        onlyOperator
        inState(VaultState.Active)
    {
        if (block.timestamp < maturityDate) revert NotMatured();

        VaultState oldState = _vaultState;
        _vaultState = VaultState.Matured;

        emit VaultStateChanged(oldState, VaultState.Matured);
    }

    /// @inheritdoc ISingleRWA_Vault
    function setMaturityDate(uint256 timestamp) external override onlyOperator {
        maturityDate = timestamp;
        emit MaturityDateSet(timestamp);
    }

    /// @inheritdoc ISingleRWA_Vault
    function isFundingTargetMet() public view override returns (bool) {
        return totalAssets() >= fundingTarget;
    }

    /// @inheritdoc ISingleRWA_Vault
    function timeToMaturity() external view override returns (uint256) {
        if (block.timestamp >= maturityDate) return 0;
        return maturityDate - block.timestamp;
    }

    // ============================================
    // DEPOSIT LIMITS
    // ============================================

    /// @inheritdoc ISingleRWA_Vault
    function setDepositLimits(
        uint256 minAmount,
        uint256 maxAmount
    ) external override onlyOperator {
        minDeposit = minAmount;
        maxDepositPerUser = maxAmount;
        emit DepositLimitsUpdated(minAmount, maxAmount);
    }

    // ============================================
    // REDEMPTION
    // ============================================

    /// @inheritdoc ISingleRWA_Vault
    function redeemAtMaturity(
        uint256 shares,
        address receiver,
        address owner
    )
        external
        override
        whenNotPaused
        nonReentrant
        inState(VaultState.Matured)
        returns (uint256 assets)
    {
        // Claim any pending yield first
        uint256 pending = pendingYield(owner);
        if (pending > 0) {
            for (uint256 i = 1; i <= currentEpoch; i++) {
                hasClaimedEpoch[owner][i] = true;
            }
            totalYieldClaimed[owner] += pending;
        }

        _updateUserSnapshot(owner);
        assets = super.redeem(shares, receiver, owner);

        // Add pending yield to transfer
        if (pending > 0) {
            IERC20(asset()).safeTransfer(receiver, pending);
            assets += pending;
        }

        return assets;
    }

    /// @inheritdoc ISingleRWA_Vault
    function requestEarlyRedemption(
        uint256 shares
    ) external override whenNotPaused returns (uint256 requestId) {
        if (shares == 0) revert ZeroAmount();
        require(balanceOf(msg.sender) >= shares, "Insufficient shares");

        _redemptionRequestCounter++;
        requestId = _redemptionRequestCounter;

        redemptionRequests[requestId] = RedemptionRequest({
            user: msg.sender,
            shares: shares,
            requestTime: block.timestamp,
            processed: false
        });

        return requestId;
    }

    /**
     * @notice Process an early redemption request (operator only)
     * @param requestId The request ID to process
     */
    function processEarlyRedemption(
        uint256 requestId
    ) external onlyOperator nonReentrant {
        RedemptionRequest storage request = redemptionRequests[requestId];
        require(!request.processed, "Already processed");
        require(request.user != address(0), "Invalid request");

        request.processed = true;

        uint256 assets = previewRedeem(request.shares);
        uint256 fee = (assets * earlyRedemptionFeeBps) / 10000;
        uint256 netAssets = assets - fee;

        _updateUserSnapshot(request.user);
        _burn(request.user, request.shares);

        IERC20(asset()).safeTransfer(request.user, netAssets);
        // Fee stays in vault for other depositors
    }

    // ============================================
    // ACCESS CONTROL
    // ============================================

    /// @inheritdoc ISingleRWA_Vault
    function isOperator(address account) external view override returns (bool) {
        return _operators[account];
    }

    /// @inheritdoc ISingleRWA_Vault
    function setOperator(
        address operator,
        bool status
    ) external override onlyAdmin {
        if (operator == address(0)) revert ZeroAddress();
        _operators[operator] = status;
        emit OperatorUpdated(operator, status);
    }

    /// @inheritdoc ISingleRWA_Vault
    function transferAdmin(address newAdmin) external override onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        admin = newAdmin;
    }

    // ============================================
    // EMERGENCY FUNCTIONS
    // ============================================

    /// @inheritdoc ISingleRWA_Vault
    function pause(string calldata reason) external override onlyOperator {
        _paused = true;
        emit EmergencyAction(true, reason);
    }

    /// @inheritdoc ISingleRWA_Vault
    function unpause() external override onlyOperator {
        _paused = false;
        emit EmergencyAction(false, "");
    }

    /// @inheritdoc ISingleRWA_Vault
    function paused() external view override returns (bool) {
        return _paused;
    }

    /// @inheritdoc ISingleRWA_Vault
    function emergencyWithdraw(address recipient) external override onlyAdmin {
        if (recipient == address(0)) revert ZeroAddress();

        uint256 balance = IERC20(asset()).balanceOf(address(this));
        IERC20(asset()).safeTransfer(recipient, balance);

        _paused = true;
        emit EmergencyAction(true, "Emergency withdrawal executed");
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @inheritdoc ISingleRWA_Vault
    function currentAPY() external view override returns (uint256) {
        // If no distributions yet, return expected APY
        if (currentEpoch == 0 || totalAssets() == 0) {
            return _expectedAPY;
        }

        // Calculate realized APY based on distributions
        return (totalYieldDistributed * 10000) / totalAssets();
    }

    /**
     * @notice Get expected APY as configured
     */
    function expectedAPY() external view returns (uint256) {
        return _expectedAPY;
    }

    /**
     * @notice Set funding target (operator only)
     */
    function setFundingTarget(uint256 target) external onlyOperator {
        fundingTarget = target;
    }

    /**
     * @notice Set early redemption fee (operator only)
     * @param feeBps Fee in basis points (max 10%)
     */
    function setEarlyRedemptionFee(uint256 feeBps) external onlyOperator {
        require(feeBps <= 1000, "Fee too high"); // Max 10%
        earlyRedemptionFeeBps = feeBps;
    }
}
