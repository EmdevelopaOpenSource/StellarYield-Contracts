// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IZKMEVerify} from "../../interfaces/ISingleRWA_Vault.sol";

/**
 * @title MockZKMEVerify
 * @notice Mock zkMe verification contract for testing
 */
contract MockZKMEVerify is IZKMEVerify {
    mapping(address => mapping(address => bool)) private _approved;

    /**
     * @notice Set approval status for a user
     * @param cooperator The cooperator address
     * @param user The user address
     * @param approved Whether the user is KYC approved
     */
    function setApproval(
        address cooperator,
        address user,
        bool approved
    ) external {
        _approved[cooperator][user] = approved;
    }

    /**
     * @notice Batch set approval status for multiple users
     * @param cooperator The cooperator address
     * @param users Array of user addresses
     * @param approved Whether the users are KYC approved
     */
    function batchSetApproval(
        address cooperator,
        address[] calldata users,
        bool approved
    ) external {
        for (uint256 i = 0; i < users.length; i++) {
            _approved[cooperator][users[i]] = approved;
        }
    }

    /// @inheritdoc IZKMEVerify
    function hasApproved(
        address cooperator,
        address user
    ) external view override returns (bool) {
        return _approved[cooperator][user];
    }
}
