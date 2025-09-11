// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./Ownable.sol";
import "../interfaces/IRateProvider.sol";

abstract contract Rate is Ownable, IRateProvider {
    // Custom errors to provide more descriptive revert messages.
    error GreaterThanMaxRateChangeLimit(uint256 rateChangeLimit);
    error RateChangeExceedLimit(uint256 oldRate, uint256 newRate);

    uint256 public constant MAX_RATE_CHANGE_LIMIT = 5 * 1e15;
    uint256 constant EIGHTEEN_DECIMALS = 1e18;

    uint256 public rate; // (1e18*token)/rToken
    uint256 public rateChangeLimit;
    mapping(uint256 => uint256) public eraRate;

    function getRate() public view virtual override returns (uint256) {
        return rate;
    }

    function setRateChangeLimit(uint256 _rateChangeLimit) external virtual onlyOwner {
        _setRateChangeLimit(_rateChangeLimit);
    }

    function _initRateParams(uint256 _rateChangeLimit) internal virtual onlyInitializing {
        _setRateChangeLimit(_rateChangeLimit);
        rate = EIGHTEEN_DECIMALS;
        eraRate[0] = rate;
    }

    function _setRateChangeLimit(uint256 _rateChangeLimit) internal virtual {
        if (_rateChangeLimit > MAX_RATE_CHANGE_LIMIT) revert GreaterThanMaxRateChangeLimit(_rateChangeLimit);

        rateChangeLimit = _rateChangeLimit;
    }

    function _setEraRate(uint256 _era, uint256 _rate) internal virtual {
        if (rateChangeLimit > 0) {
            uint256 rateChange = _rate > rate ? _rate - rate : rate - _rate;
            if ((rateChange * EIGHTEEN_DECIMALS) / rate > rateChangeLimit) revert RateChangeExceedLimit(rate, _rate);
        }

        rate = _rate;
        eraRate[_era] = rate;
    }

    function _calRate(uint256 _totalActive, uint256 _totalLst) internal view virtual returns (uint256) {
        if (_totalLst == 0) {
            return EIGHTEEN_DECIMALS;
        }
        uint256 calRate = (_totalActive * EIGHTEEN_DECIMALS) / _totalLst;
        if (calRate < EIGHTEEN_DECIMALS && EIGHTEEN_DECIMALS - calRate < 20) {
            calRate = EIGHTEEN_DECIMALS;
        }
        return calRate;
    }
}
