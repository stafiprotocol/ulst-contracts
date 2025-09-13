// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./Ownable.sol";

abstract contract Era is Ownable {
    // Custom errors to provide more descriptive revert messages.
    error LessThanMinEraSeconds(uint256 eraSeconds);
    error GreaterThanMaxEraSeconds(uint256 eraSeconds);
    error WrongEraParameters(uint256 eraSeconds, uint256 eraOffset);

    uint256 public constant MIN_ERA_SECONDS = 600;
    uint256 public constant MAX_ERA_SECONDS = 86400 * 2;
    uint256 public constant DEFAULT_ERA_SECONDS = 86400;

    uint256 public eraSeconds;
    uint256 public eraOffset;

    uint256 public latestEra;

    function currentEra() public view virtual returns (uint256) {
        return block.timestamp / eraSeconds - eraOffset;
    }

    function setEraParams(uint256 _eraSeconds, uint256 _eraOffset) external virtual onlyOwner {
        if (eraSeconds == 0) revert NotInitialized();
        if (_eraSeconds < MIN_ERA_SECONDS) revert LessThanMinEraSeconds(_eraSeconds);
        if (_eraSeconds > MAX_ERA_SECONDS) revert GreaterThanMaxEraSeconds(_eraSeconds);
        if (currentEra() != block.timestamp / _eraSeconds - _eraOffset) {
            revert WrongEraParameters(_eraSeconds, _eraOffset);
        }

        eraSeconds = _eraSeconds;
        eraOffset = _eraOffset;
    }

    function _initEraParams() internal virtual onlyInitializing {
        eraSeconds = DEFAULT_ERA_SECONDS;
        eraOffset = block.timestamp / eraSeconds;
    }
}
