// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

interface IStakePool {
    function delegate(address depositToken, uint256 amount) external returns (uint256);
    function undelegate(address receivingToken, uint256 claimAmount) external returns (uint256);
    function withdrawForStaker(address receivingToken, address staker, uint256 amount) external;
    function getDelegated(address stablecoin) external view returns (uint256);
    function undelegatePaused(address stablecoin) external view returns (bool);
}
