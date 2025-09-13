// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IStakePool.sol";
import "./interfaces/ILsdToken.sol";
import "./base/Manager.sol";
import {IOndoOracle} from "./interfaces/Ondo.sol";

contract StakeManager is Initializable, Manager, UUPSUpgradeable {
    // Custom errors to provide more descriptive revert messages.
    error PoolNotEmpty();
    error DelegateNotEmpty();
    error PoolNotExist(address poolAddress);
    error ValidatorNotExist();
    error ValidatorDuplicated();
    error ZeroRedelegateAmount();
    error NotEnoughStakeAmount();
    error ZeroUnstakeAmount();
    error ZeroWithdrawAmount();
    error UnstakeTimesExceedLimit();
    error AlreadyWithdrawed();
    error EraNotMatch();
    error NotEnoughAmountToUndelegate();
    error StablecoinDuplicated(address stablecoin);
    error StablecoinNotExist(address stablecoin);

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    address public stablecoin;

    // pool => validator Id => max claimed nonce
    mapping(address => mapping(uint256 => uint256)) public maxClaimedNonceOf;

    // events
    event Stake(address staker, address poolAddress, address stablecoin, uint256 tokenAmount, uint256 lsdTokenAmount);
    event Unstake(
        address staker,
        address poolAddress,
        address stablecoin,
        uint256 tokenAmount,
        uint256 lsdTokenAmount,
        uint256 unstakeIndex
    );
    event Withdraw(address staker, address poolAddress, uint256 tokenAmount, int256[] unstakeIndexList);
    event ExecuteNewEra(uint256 indexed era, uint256 rate);
    event NewReward(address poolAddress, uint256 newReward);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _lsdToken,
        address _poolAddress,
        address _stablecoin,
        address _owner,
        address _factoryAddress
    ) external virtual initializer {
        _transferOwnership(_owner);
        stablecoin = _stablecoin;
        _initManagerParams(_lsdToken, _poolAddress, _factoryAddress, 4, 0);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ------------ getter ------------

    function version() external view returns (uint64) {
        return _getInitializedVersion();
    }

    // ----- staker operation

    function stake(uint256 _stakeAmount) external {
        stakeWithPool(bondedPools.at(0), _stakeAmount);
    }

    function unstake(uint256 _lsdTokenAmount) external {
        unstakeWithPool(bondedPools.at(0), _lsdTokenAmount);
    }

    function withdraw() external {
        withdrawWithPool(bondedPools.at(0));
    }

    function stakeWithPool(address _poolAddress, uint256 _stakeAmount) public {
        if (_stakeAmount < minStakeAmount) revert NotEnoughStakeAmount();
        if (!bondedPools.contains(_poolAddress)) revert PoolNotExist(_poolAddress);

        uint256 lsdTokenAmount = (_stakeAmount * 1e18) / rate;

        // update pool
        PoolInfo storage poolInfo = poolInfoOf[_poolAddress];
        poolInfo.bond = poolInfo.bond + _stakeAmount;

        // transfer stablecoin
        IERC20(stablecoin).safeTransferFrom(msg.sender, _poolAddress, _stakeAmount);

        // mint lsdToken
        ILsdToken(lsdToken).mint(msg.sender, lsdTokenAmount);

        emit Stake(msg.sender, _poolAddress, stablecoin, _stakeAmount, lsdTokenAmount);
    }

    function unstakeWithPool(address _poolAddress, uint256 _lsdTokenAmount) public {
        if (_lsdTokenAmount == 0) revert ZeroUnstakeAmount();
        if (!bondedPools.contains(_poolAddress)) revert PoolNotExist(_poolAddress);
        if (unstakesOfUser[msg.sender].length() >= UNSTAKE_TIMES_LIMIT) revert UnstakeTimesExceedLimit();

        uint256 tokenAmount = (_lsdTokenAmount * rate) / 1e18;

        // update pool
        PoolInfo storage poolInfo = poolInfoOf[_poolAddress];
        poolInfo.unbond = poolInfo.unbond + tokenAmount;

        // burn lsdToken
        ERC20Burnable(lsdToken).burnFrom(msg.sender, _lsdTokenAmount);

        // unstake info
        uint256 willUseUnstakeIndex = nextUnstakeIndex;
        nextUnstakeIndex = willUseUnstakeIndex + 1;

        unstakeAtIndex[willUseUnstakeIndex] = UnstakeInfo({
            era: currentEra(),
            pool: _poolAddress,
            stablecoin: stablecoin,
            receiver: msg.sender,
            amount: tokenAmount
        });
        unstakesOfUser[msg.sender].add(willUseUnstakeIndex);

        emit Unstake(msg.sender, _poolAddress, stablecoin, tokenAmount, _lsdTokenAmount, willUseUnstakeIndex);
    }

    function withdrawWithPool(address _poolAddress) public {
        uint256 totalWithdrawAmount;
        uint256[] memory unstakeIndexList = getUnstakeIndexListOf(msg.sender);
        uint256 length = unstakesOfUser[msg.sender].length();
        int256[] memory emitUnstakeIndexList = new int256[](length);

        uint256 curEra = currentEra();
        for (uint256 i = 0; i < length; ++i) {
            uint256 unstakeIndex = unstakeIndexList[i];
            UnstakeInfo memory unstakeInfo = unstakeAtIndex[unstakeIndex];
            if (unstakeInfo.era + unbondingDuration > curEra || unstakeInfo.pool != _poolAddress) {
                emitUnstakeIndexList[i] = -1;
                continue;
            }

            if (!unstakesOfUser[msg.sender].remove(unstakeIndex)) revert AlreadyWithdrawed();

            totalWithdrawAmount = totalWithdrawAmount + unstakeInfo.amount;
            emitUnstakeIndexList[i] = int256(unstakeIndex);
        }

        if (totalWithdrawAmount <= 0) revert ZeroWithdrawAmount();
        IStakePool(_poolAddress).withdrawForStaker(stablecoin, msg.sender, totalWithdrawAmount);

        emit Withdraw(msg.sender, _poolAddress, totalWithdrawAmount, emitUnstakeIndexList);
    }

    // ----- permissionless

    function newEra() external {
        uint256 _era = latestEra + 1;
        if (currentEra() < _era) revert EraNotMatch();

        // update era
        latestEra = _era;

        uint256 totalNewReward;
        uint256 newTotalActive;
        address[] memory poolList = getBondedPools();
        for (uint256 i = 0; i < poolList.length; ++i) {
            address poolAddress = poolList[i];
            PoolInfo memory poolInfo = poolInfoOf[poolAddress];

            // newReward
            uint256 poolNewReward = IStakePool(poolAddress).getDelegated(stablecoin) - poolInfo.active;
            emit NewReward(poolAddress, poolNewReward);
            totalNewReward = totalNewReward + poolNewReward;

            // bond or unbond
            if (poolInfo.bond > poolInfo.unbond) {
                uint256 needDelegate = poolInfo.bond - poolInfo.unbond;
                IStakePool(poolAddress).delegate(stablecoin, needDelegate);
            } else if (poolInfo.bond < poolInfo.unbond) {
                uint256 needUndelegate = poolInfo.unbond - poolInfo.bond;
                IStakePool(poolAddress).undelegate(stablecoin, needUndelegate);
            }

            // cal total active
            uint256 newPoolActive = IStakePool(poolAddress).getDelegated(stablecoin);
            newTotalActive = newTotalActive + newPoolActive;

            // update pool state
            poolInfo.active = newPoolActive;
            poolInfo.era = latestEra;
            poolInfo.bond = 0;
            poolInfo.unbond = 0;

            poolInfoOf[poolAddress] = poolInfo;
        }

        // ditribute protocol fee
        _distributeReward(totalNewReward, rate);

        // update rate
        uint256 newRate = _calRate(newTotalActive, ERC20(lsdToken).totalSupply());
        _setEraRate(_era, newRate);

        emit ExecuteNewEra(_era, newRate);
    }
}
