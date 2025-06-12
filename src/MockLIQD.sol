// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockLIQD
 * @notice A basic ERC20 token for testing the StLIQD staking contract
 * @dev Basic ERC20 with mint function for testing
 */
contract MockLIQD is ERC20, Ownable {
    /**
     * @notice Initializes the MockLIQD token contract
     * @param name Name of the token
     * @param symbol Symbol of the token
     * @param initialOwner Address that will own the contract and can mint tokens
     */
    constructor(
        string memory name,
        string memory symbol,
        address initialOwner
    ) ERC20(name, symbol) Ownable(initialOwner) {}

    /**
     * @notice Mints new tokens
     * @dev Only the contract owner can mint tokens
     * @param to Address to receive the newly minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
} 