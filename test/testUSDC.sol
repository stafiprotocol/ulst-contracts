// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// temporary interface for minting USDC
interface ITestUSDC {
    function balanceOf(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function masterMinter() external view returns (address);
}
