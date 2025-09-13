// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

interface IOndoInstantManager {
    function subscribe(address depositToken, uint256 depositAmount, uint256 minimumRwaReceived)
        external
        returns (uint256 rwaAmountOut);

    function redeem(uint256 rwaAmount, address receivingToken, uint256 minimumTokenReceived)
        external
        returns (uint256 receiveTokenAmount);

    // RWA token is an ERC20 compliant token
    function rwaToken() external view returns (address);

    function RWA_NORMALIZER() external view returns (uint256);
}

interface IOndoOracle {
    function getAssetPrice(address token) external view returns (uint256 price);
}

interface IOndoFees {
    function getAndUpdateFee(address rwaToken, address stablecoin, bytes32 userID, uint256 usdValue)
        external
        returns (uint256 usdFee);
}
