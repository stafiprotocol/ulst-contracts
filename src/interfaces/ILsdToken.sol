// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

interface ILsdToken {
    function mint(address to, uint256 amount) external;
    function initMinter(address _minter) external;
    function updateMinter(address _newMinter) external;
}
