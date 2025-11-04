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
    error AlreadyWithdrawed();
    error EraNotMatch();
    error NotEnoughAmountToUndelegate();
    error StablecoinDuplicated(address stablecoin);
    error StablecoinNotExist(address stablecoin);
    error UnstakePausedError();
    error UnbondingFailed(uint256 needUndelegate);

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    EnumerableSet.AddressSet private stablecoins;
    bool public isUnstakePaused;

    // events
    event Stake(address staker, address poolAddress, address stablecoin, uint256 tokenAmount, uint256 lsdTokenAmount);
    event Unstake(address staker, address poolAddress, address stablecoin, uint256 tokenAmount, uint256 lsdTokenAmount);
    event ExecuteNewEra(uint256 indexed era, uint256 rate);
    event NewReward(address poolAddress, uint256 newReward);
    event GovRedeemFee(address pool, address stablecoin, uint256 amount);
    event UnstakePaused(address account);
    event UnstakeUnpaused(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _lsdToken,
        address _poolAddress,
        address _owner,
        address[] memory _stablecoins,
        address _factoryAddress
    ) external virtual initializer {
        isUnstakePaused = true;
        _transferOwnership(_owner);
        _initManagerParams(_lsdToken, _poolAddress, _factoryAddress, 0);
        for (uint256 i = 0; i < _stablecoins.length; ++i) {
            if (!stablecoins.add(_stablecoins[i])) revert StablecoinDuplicated(_stablecoins[i]);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier whenUnstakeNotPaused() {
        _whenUnstakeNotPaused();
        _;
    }

    function _whenUnstakeNotPaused() internal view {
        if (isUnstakePaused) revert UnstakePausedError();
    }

    // ------------ getter ------------

    function version() external view returns (uint64) {
        return _getInitializedVersion();
    }

    function getStablecoins() public view returns (address[] memory) {
        return stablecoins.values();
    }

    function addStablecoin(address _stablecoin) external onlyOwner {
        if (!stablecoins.add(_stablecoin)) revert StablecoinDuplicated(_stablecoin);
    }

    function rmStablecoin(address _stablecoin) external onlyOwner {
        if (!stablecoins.remove(_stablecoin)) revert StablecoinNotExist(_stablecoin);
    }

    function setIsUnstakePaused(bool _isUnstakePaused) external onlyOwner {
        isUnstakePaused = _isUnstakePaused;
        if (_isUnstakePaused) {
            emit UnstakePaused(msg.sender);
        } else {
            emit UnstakeUnpaused(msg.sender);
        }
    }

    // ----- staker operation

    function stake(address _stablecoin, uint256 _stakeAmount) external {
        stakeWithPool(bondedPools.at(0), _stablecoin, _stakeAmount);
    }

    function unstake(address _stablecoin, uint256 _lsdTokenAmount) external {
        unstakeWithPool(bondedPools.at(0), _stablecoin, _lsdTokenAmount);
    }

    function stakeWithPool(address _poolAddress, address _stablecoin, uint256 _stakeAmount) public {
        if (_stakeAmount < minStakeAmount) revert NotEnoughStakeAmount();
        if (!bondedPools.contains(_poolAddress)) revert PoolNotExist(_poolAddress);

        uint256 lsdTokenAmount = (_stakeAmount * 1e18) / rate;

        // update pool
        PoolInfo storage poolInfo = poolInfoOf[_poolAddress];
        poolInfo.bondOf[_stablecoin] = poolInfo.bondOf[_stablecoin] + _stakeAmount;

        // transfer stablecoin
        IERC20(_stablecoin).safeTransferFrom(msg.sender, _poolAddress, _stakeAmount);

        // mint lsdToken
        ILsdToken(lsdToken).mint(msg.sender, lsdTokenAmount);

        emit Stake(msg.sender, _poolAddress, _stablecoin, _stakeAmount, lsdTokenAmount);
    }

    function unstakeWithPool(address _poolAddress, address _stablecoin, uint256 _lsdTokenAmount)
        public
        whenUnstakeNotPaused
    {
        if (IStakePool(_poolAddress).undelegatePaused(_stablecoin)) revert UnstakePausedError();
        if (_lsdTokenAmount == 0) revert ZeroUnstakeAmount();
        if (!bondedPools.contains(_poolAddress)) revert PoolNotExist(_poolAddress);

        uint256 tokenAmount = (_lsdTokenAmount * rate) / 1e18;

        // update pool
        PoolInfo storage poolInfo = poolInfoOf[_poolAddress];

        // burn lsdToken
        ERC20Burnable(lsdToken).burnFrom(msg.sender, _lsdTokenAmount);

        if (tokenAmount <= poolInfo.bondOf[_stablecoin]) {
            poolInfo.bondOf[_stablecoin] = poolInfo.bondOf[_stablecoin] - tokenAmount;
        } else {
            uint256 needUndelegate = tokenAmount - poolInfo.bondOf[_stablecoin];
            uint256 pre = IStakePool(_poolAddress).getDelegated(stablecoins.at(0));
            uint256 undelegated = IStakePool(_poolAddress).undelegate(_stablecoin, needUndelegate);
            if (undelegated == 0) {
                revert UnbondingFailed(needUndelegate);
            } else {
                uint256 unstakeValue = pre - IStakePool(_poolAddress).getDelegated(stablecoins.at(0));
                poolInfo.active = poolInfo.active - unstakeValue;
                poolInfo.bondOf[_stablecoin] = 0;

                uint256 redeemFee = 0;
                if (needUndelegate > undelegated) {
                    redeemFee = needUndelegate - undelegated;
                }
                tokenAmount = tokenAmount - redeemFee;
                emit GovRedeemFee(_poolAddress, _stablecoin, redeemFee);
            }
        }

        IStakePool(_poolAddress).withdrawForStaker(_stablecoin, msg.sender, tokenAmount);

        emit Unstake(msg.sender, _poolAddress, _stablecoin, tokenAmount, _lsdTokenAmount);
    }

    // ----- permissionless

    function newEra() external {
        uint256 _era = latestEra + 1;
        if (currentEra() < _era) revert EraNotMatch();

        // update era
        latestEra = _era;

        uint256 newTotalReward;
        uint256 newTotalActive;
        address[] memory poolList = getBondedPools();
        for (uint256 i = 0; i < poolList.length; ++i) {
            IStakePool pool = IStakePool(poolList[i]);
            PoolInfo storage poolInfo = poolInfoOf[address(pool)];

            uint256 totalBond = 0;

            for (uint256 j = 0; j < stablecoins.length(); ++j) {
                address stablecoin = stablecoins.at(j);

                uint256 needBond = poolInfo.bondOf[stablecoin];
                uint256 delegated = 0;
                if (needBond > 0) {
                    uint256 pre = pool.getDelegated(stablecoins.at(0));
                    delegated = pool.delegate(stablecoin, needBond);
                    totalBond = totalBond + (pool.getDelegated(stablecoins.at(0)) - pre);
                    if (delegated > 0) {
                        poolInfo.bondOf[stablecoin] = 0;
                    }
                }
            }

            poolInfo.era = latestEra;
            // newReward
            uint256 newPoolActive = pool.getDelegated(stablecoins.at(0));
            uint256 poolNewReward = newPoolActive - totalBond - poolInfo.active;
            emit NewReward(address(pool), poolNewReward);
            newTotalReward = newTotalReward + poolNewReward;

            // cal total active
            newTotalActive = newTotalActive + newPoolActive;
            poolInfo.active = newPoolActive;
        }

        // ditribute protocol fee
        _distributeReward(newTotalReward, rate);

        // update rate
        uint256 newRate = _calRate(newTotalActive, ERC20(lsdToken).totalSupply());
        _setEraRate(_era, newRate);

        emit ExecuteNewEra(_era, newRate);
    }
}
