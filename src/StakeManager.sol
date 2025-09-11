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

    EnumerableSet.AddressSet private stablecoins;

    mapping(address => EnumerableSet.UintSet) validatorIdsOf;
    // pool => validator Id => max claimed nonce
    mapping(address => mapping(uint256 => uint256)) public maxClaimedNonceOf;

    // events
    event Stake(address staker, address poolAddress, address stablecoin, uint256 tokenAmount, uint256 lsdTokenAmount);
    event Unstake(
        address staker, address poolAddress, address stablecoin, uint256 tokenAmount, uint256 lsdTokenAmount, uint256 unstakeIndex
    );
    event Withdraw(address staker, address poolAddress, uint256 tokenAmount, int256[] unstakeIndexList);
    event ExecuteNewEra(uint256 indexed era, uint256 rate);
    event Delegate(address pool, uint256 validator, uint256 amount);
    event Undelegate(address pool, uint256 validator, uint256 amount);
    event NewReward(address pool, uint256 amount);
    event NewClaimedNonce(address pool, uint256 validator, uint256 nonce);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _lsdToken,
        address _poolAddress,
        address _owner,
        address _factoryAddress
    ) external virtual initializer {
        _transferOwnership(_owner);
        _initManagerParams(_lsdToken, _poolAddress, _factoryAddress, 4, 0);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ------------ getter ------------

    function version() external view returns (uint64) {
        return _getInitializedVersion();
    }

    function getstablecoins() public view returns (address[] memory) {
        return stablecoins.values();
    }
    function addStablecoin(address _stablecoin) external onlyOwner {
        if (!stablecoins.add(_stablecoin)) revert StablecoinDuplicated(_stablecoin);
    }
    function rmStablecoin(address _stablecoin) external onlyOwner {
        if (!stablecoins.remove(_stablecoin)) revert StablecoinNotExist(_stablecoin);
    }

    // ----- staker operation

    function stake(address _stablecoin, uint256 _stakeAmount) external {
        stakeWithPool(bondedPools.at(0), _stablecoin, _stakeAmount);
    }

    function unstake(address _stablecoin, uint256 _lsdTokenAmount) external {
        unstakeWithPool(bondedPools.at(0), _stablecoin, _lsdTokenAmount);
    }

    function withdraw(address _stablecoin) external {
        withdrawWithPool(bondedPools.at(0), _stablecoin);
    }

    function stakeWithPool(address _poolAddress, address _stablecoin, uint256 _stakeAmount) public {
        if (_stakeAmount < minStakeAmount) revert NotEnoughStakeAmount();
        if (!bondedPools.contains(_poolAddress)) revert PoolNotExist(_poolAddress);

        uint256 lsdTokenAmount = (_stakeAmount * 1e18) / rate;

        // update pool
        PoolInfo storage poolInfo = poolInfoOf[_poolAddress];
        poolInfo.bond = poolInfo.bond + _stakeAmount;
        poolInfo.active = poolInfo.active + _stakeAmount;

        // transfer stablecoin
        IERC20(_stablecoin).safeTransferFrom(msg.sender, _poolAddress, _stakeAmount);

        // mint lsdToken
        ILsdToken(lsdToken).mint(msg.sender, lsdTokenAmount);

        emit Stake(msg.sender, _poolAddress, _stablecoin, _stakeAmount, lsdTokenAmount);
    }

    function unstakeWithPool(address _poolAddress, address _stablecoin, uint256 _lsdTokenAmount) public {
        if (_lsdTokenAmount == 0) revert ZeroUnstakeAmount();
        if (!bondedPools.contains(_poolAddress)) revert PoolNotExist(_poolAddress);
        if (unstakesOfUser[msg.sender].length() >= UNSTAKE_TIMES_LIMIT) revert UnstakeTimesExceedLimit();

        uint256 tokenAmount = (_lsdTokenAmount * rate) / 1e18;

        // update pool
        PoolInfo storage poolInfo = poolInfoOf[_poolAddress];
        poolInfo.unbond = poolInfo.unbond + tokenAmount;
        poolInfo.active = poolInfo.active - tokenAmount;

        // burn lsdToken
        ERC20Burnable(lsdToken).burnFrom(msg.sender, _lsdTokenAmount);

        // unstake info
        uint256 willUseUnstakeIndex = nextUnstakeIndex;
        nextUnstakeIndex = willUseUnstakeIndex + 1;

        unstakeAtIndex[willUseUnstakeIndex] =
            UnstakeInfo({era: currentEra(), pool: _poolAddress, stablecoin: _stablecoin, receiver: msg.sender, amount: tokenAmount});
        unstakesOfUser[msg.sender].add(willUseUnstakeIndex);

        emit Unstake(msg.sender, _poolAddress, _stablecoin, tokenAmount, _lsdTokenAmount, willUseUnstakeIndex);
    }

    function withdrawWithPool(address _poolAddress, address _stablecoin) public {
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
        IStakePool(_poolAddress).withdrawForStaker(_stablecoin, msg.sender, totalWithdrawAmount);

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
            // address poolAddress = poolList[i];

            // uint256[] memory validators = getValidatorIdsOf(poolAddress);

            // // newReward
            // uint256 poolNewReward = IStakePool(poolAddress).checkAndWithdrawRewards(validators);
            // emit NewReward(poolAddress, poolNewReward);
            // totalNewReward = totalNewReward + poolNewReward;

            // // unstakeClaimTokens
            // for (uint256 j = 0; j < validators.length; ++j) {
            //     uint256 oldClaimedNonce = maxClaimedNonceOf[poolAddress][validators[j]];
            //     uint256 newClaimedNonce =
            //         IStakePool(poolAddress).unstakeClaimTokens(validators[j], oldClaimedNonce);
            //     if (newClaimedNonce > oldClaimedNonce) {
            //         maxClaimedNonceOf[poolAddress][validators[j]] = newClaimedNonce;

            //         emit NewClaimedNonce(poolAddress, validators[j], newClaimedNonce);
            //     }
            // }

            // // bond or unbond
            // PoolInfo memory poolInfo = poolInfoOf[poolAddress];
            // uint256 poolBondAndNewReward = poolInfo.bond + poolNewReward;
            // if (poolBondAndNewReward > poolInfo.unbond) {
            //     uint256 needDelegate = poolBondAndNewReward - poolInfo.unbond;
            //     IStakePool(poolAddress).delegate(validators[0], needDelegate);

            //     emit Delegate(poolAddress, validators[0], needDelegate);
            // } else if (poolBondAndNewReward < poolInfo.unbond) {
            //     uint256 needUndelegate = poolInfo.unbond - poolBondAndNewReward;

            //     for (uint256 j = 0; j < validators.length; ++j) {
            //         if (needUndelegate == 0) {
            //             break;
            //         }
            //         uint256 totalStaked = IStakePool(poolAddress).getDelegated(validators[j]);

            //         uint256 unbondAmount;
            //         if (needUndelegate < totalStaked) {
            //             unbondAmount = needUndelegate;
            //             needUndelegate = 0;
            //         } else {
            //             unbondAmount = totalStaked;
            //             needUndelegate = needUndelegate - totalStaked;
            //         }

            //         if (unbondAmount > 0) {
            //             IStakePool(poolAddress).undelegate(validators[j], unbondAmount);

            //             emit Undelegate(poolAddress, validators[j], unbondAmount);
            //         }
            //     }
            //     if (needUndelegate != 0) revert NotEnoughAmountToUndelegate();
            // }

            // // cal total active
            // uint256 newPoolActive = IStakePool(poolAddress).getTotalDelegated(validators);
            // newTotalActive = newTotalActive + newPoolActive;

            // // update pool state
            // poolInfo.era = latestEra;
            // poolInfo.active = newPoolActive;
            // poolInfo.bond = 0;
            // poolInfo.unbond = 0;

            // poolInfoOf[poolAddress] = poolInfo;
        }

        // ditribute protocol fee
        _distributeReward(totalNewReward, rate);

        // update rate
        uint256 newRate = _calRate(newTotalActive, ERC20(lsdToken).totalSupply());
        _setEraRate(_era, newRate);

        emit ExecuteNewEra(_era, newRate);
    }
}
