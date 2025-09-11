// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Ownable.sol";

abstract contract UnstakePoolManager is Ownable {
    // Custom errors to provide more descriptive revert messages.
    error ZeroUnbondingDuration();
    error GreaterThanMaxUnbondingDuration(uint256 unbondingDuration);

    using EnumerableSet for EnumerableSet.UintSet;

    struct UnstakeInfo {
        uint256 era;
        address pool;
        address stablecoin;
        address receiver;
        uint256 amount;
    }

    uint256 public constant UNSTAKE_TIMES_LIMIT = 100;
    uint256 public constant MAX_UNBONDING_DURATION = 32;

    uint256 public unbondingDuration;

    // unstake info
    uint256 public nextUnstakeIndex;
    mapping(uint256 => UnstakeInfo) public unstakeAtIndex;
    mapping(address => EnumerableSet.UintSet) unstakesOfUser;

    event SetUnbondingDuration(uint256 unbondingDuration);

    function getUnstakeIndexListOf(address _staker) public view virtual returns (uint256[] memory unstakeIndexList) {
        return unstakesOfUser[_staker].values();
    }

    function setUnbondingDuration(uint256 _unbondingDuration) external virtual onlyOwner {
        _setUnbondingDuration(_unbondingDuration);
    }

    function _initUnstakeParams(uint256 _unbondingDuration) internal virtual onlyInitializing {
        _setUnbondingDuration(_unbondingDuration);
    }

    function _setUnbondingDuration(uint256 _unbondingDuration) internal virtual {
        if (_unbondingDuration == 0) revert ZeroUnbondingDuration();
        if (_unbondingDuration > MAX_UNBONDING_DURATION) revert GreaterThanMaxUnbondingDuration(_unbondingDuration);

        unbondingDuration = _unbondingDuration;
        emit SetUnbondingDuration(_unbondingDuration);
    }
}
