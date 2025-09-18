// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Ownable.sol";

abstract contract StakePoolManager is Ownable {
    // Custom errors to provide more descriptive revert messages.
    error PoolExist(address poolAddress);

    using EnumerableSet for EnumerableSet.AddressSet;

    struct PoolInfo {
        uint256 era;
        uint256 active;
        mapping(address /* stablecoin */ => uint256 /* fullfilled withdrawal amount */) fullfilledWithdrawalAmountOf;
        mapping(address /* stablecoin */ => uint256 /* bond */) bondOf;
        mapping(address /* stablecoin */ => uint256 /* unbond */) unbondOf;
        mapping(address /* stablecoin */ => uint256 /* active */) activeOf;
    }
    uint256 public minStakeAmount;

    EnumerableSet.AddressSet bondedPools;
    mapping(address => PoolInfo) public poolInfoOf;

    function getBondedPools() public view virtual returns (address[] memory pools) {
        return bondedPools.values();
    }

    function addStakePool(address _poolAddress) external virtual onlyOwner {
        _addStakePool(_poolAddress);
    }

    function setMinStakeAmount(uint256 _minStakeAmount) external virtual onlyOwner {
        minStakeAmount = _minStakeAmount;
    }

    function _initStakePoolParams(address _poolAddress) internal virtual onlyInitializing {
        _addStakePool(_poolAddress);
    }

    function _addStakePool(address _poolAddress) internal virtual {
        if (_poolAddress == address(0)) revert AddressNotAllowed();
        if (!bondedPools.add(_poolAddress)) revert PoolExist(_poolAddress);
    }
}
