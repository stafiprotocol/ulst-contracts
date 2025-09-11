// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./Era.sol";
import "./Rate.sol";
import "./StakePoolManager.sol";
import "./UnstakePoolManager.sol";
import "./Protocol.sol";
import "./DelegationBalancer.sol";

abstract contract Manager is Era, Rate, StakePoolManager, UnstakePoolManager, Protocol, DelegationBalancer {
    uint256 public constant MAX_VALIDATORS_LEN = 30;

    function _initManagerParams(
        address _lsdToken,
        address _poolAddress,
        address _factoryAddress,
        uint256 _unbondingDuration,
        uint256 _rateChangeLimit
    ) internal virtual onlyInitializing {
        _initProtocolParams(_lsdToken, _factoryAddress);
        _initEraParams();
        _initRateParams(_rateChangeLimit);
        _initStakePoolParams(_poolAddress);
        _initUnstakeParams(_unbondingDuration);
        _initDelegationBalancer();
    }
}
