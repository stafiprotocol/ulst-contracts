// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

interface IOndoFees {
    function getAndUpdateFee(address rwaToken, address stablecoin, bytes32 userID, uint256 usdValue)
        external
        returns (uint256 usdFee);
}
