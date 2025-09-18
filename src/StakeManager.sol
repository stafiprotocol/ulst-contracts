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

    EnumerableSet.AddressSet private stablecoins;

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
    event Withdraw(address staker, address poolAddress, int256[] unstakeIndexList);
    event ExecuteNewEra(uint256 indexed era, uint256 rate);
    event NewReward(address poolAddress, uint256 newReward);

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
        _transferOwnership(_owner);
        _initManagerParams(_lsdToken, _poolAddress, _factoryAddress, 4, 0);
        for (uint256 i = 0; i < _stablecoins.length; ++i) {
            if (!stablecoins.add(_stablecoins[i])) revert StablecoinDuplicated(_stablecoins[i]);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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

    // ----- staker operation

    function stake(address _stablecoin, uint256 _stakeAmount) external {
        stakeWithPool(bondedPools.at(0), _stablecoin, _stakeAmount);
    }

    function unstake(address _stablecoin, uint256 _lsdTokenAmount) external {
        unstakeWithPool(bondedPools.at(0), _stablecoin, _lsdTokenAmount);
    }

    function withdraw() external {
        withdrawWithPool(bondedPools.at(0));
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

    function unstakeWithPool(address _poolAddress, address _stablecoin, uint256 _lsdTokenAmount) public {
        if (_lsdTokenAmount == 0) revert ZeroUnstakeAmount();
        if (!bondedPools.contains(_poolAddress)) revert PoolNotExist(_poolAddress);
        if (unstakesOfUser[msg.sender].length() >= UNSTAKE_TIMES_LIMIT) revert UnstakeTimesExceedLimit();

        uint256 tokenAmount = (_lsdTokenAmount * rate) / 1e18;

        // update pool
        PoolInfo storage poolInfo = poolInfoOf[_poolAddress];
        poolInfo.unbondOf[_stablecoin] = poolInfo.unbondOf[_stablecoin] + tokenAmount;

        // burn lsdToken
        ERC20Burnable(lsdToken).burnFrom(msg.sender, _lsdTokenAmount);

        // unstake info
        uint256 willUseUnstakeIndex = nextUnstakeIndex;
        nextUnstakeIndex = willUseUnstakeIndex + 1;

        tokenAmount = tokenAmount / 100 * 100; // round down
        unstakeAtIndex[willUseUnstakeIndex] = UnstakeInfo({
            era: currentEra(),
            pool: _poolAddress,
            stablecoin: _stablecoin,
            receiver: msg.sender,
            amount: tokenAmount,
            targetFullfilledAmount: poolInfo.fullfilledWithdrawalAmountOf[_stablecoin] + tokenAmount
        });
        unstakesOfUser[msg.sender].add(willUseUnstakeIndex);

        emit Unstake(msg.sender, _poolAddress, _stablecoin, tokenAmount, _lsdTokenAmount, willUseUnstakeIndex);
    }

    mapping(address => uint256) private totalWithdrawAmountOf;

    function withdrawWithPool(address _poolAddress) public {
        uint256[] memory unstakeIndexList = getUnstakeIndexListOf(msg.sender);
        uint256 length = unstakesOfUser[msg.sender].length();
        int256[] memory emitUnstakeIndexList = new int256[](length);

        PoolInfo storage poolInfo = poolInfoOf[_poolAddress];

        uint256 totalWithdrawAmount;
        uint256 curEra = currentEra();
        for (uint256 i = 0; i < length; ++i) {
            uint256 unstakeIndex = unstakeIndexList[i];
            UnstakeInfo memory unstakeInfo = unstakeAtIndex[unstakeIndex];
            if (unstakeInfo.era + unbondingDuration > curEra || unstakeInfo.pool != _poolAddress) {
                emitUnstakeIndexList[i] = -1;
                continue;
            }
            if (unstakeInfo.targetFullfilledAmount < poolInfo.fullfilledWithdrawalAmountOf[unstakeInfo.stablecoin]) {
                emitUnstakeIndexList[i] = -1;
                continue;
            }

            if (!unstakesOfUser[msg.sender].remove(unstakeIndex)) revert AlreadyWithdrawed();

            totalWithdrawAmount = totalWithdrawAmount + unstakeInfo.amount;
            totalWithdrawAmountOf[unstakeInfo.stablecoin] = totalWithdrawAmountOf[unstakeInfo.stablecoin] + unstakeInfo.amount;
            emitUnstakeIndexList[i] = int256(unstakeIndex);
        }
        if (totalWithdrawAmount <= 0) revert ZeroWithdrawAmount();

        for (uint256 i = 0; i < stablecoins.length(); ++i) {
            address stablecoin = stablecoins.at(i);
            uint256 amount = totalWithdrawAmountOf[stablecoin];
            if (amount <= 0) continue;
            totalWithdrawAmountOf[stablecoin] = 0;

            IStakePool(_poolAddress).withdrawForStaker(stablecoin, msg.sender, amount);

            emit Withdraw(msg.sender, _poolAddress, emitUnstakeIndexList);
        }
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

            uint256 totalUnbond = 0;
            uint256 totalBond = 0;

            for (uint256 j = 0; j < stablecoins.length(); ++j) {
                address stablecoin = stablecoins.at(j);

                uint256 bond = poolInfo.bondOf[stablecoin];
                uint256 unbond = poolInfo.unbondOf[stablecoin];

                // bond or unbond
                if (bond > unbond) {
                    uint256 needDelegate = bond - unbond;
                    uint256 pre = pool.getDelegated(stablecoins.at(0));
                    pool.delegate(stablecoin, needDelegate);
                    totalBond = totalBond + (pool.getDelegated(stablecoins.at(0)) - pre);
                } else if (bond < unbond) {
                    uint256 needUndelegate = unbond - bond;
                    uint256 pre = pool.getDelegated(stablecoins.at(0));
                    pool.undelegate(stablecoin, needUndelegate);
                    totalUnbond = totalUnbond + (pre - pool.getDelegated(stablecoins.at(0)));
                }

                // update pool state
                poolInfo.bondOf[stablecoin] = 0;
                poolInfo.unbondOf[stablecoin] = 0;
            }

            poolInfo.era = latestEra;
            // newReward
            uint256 newPoolActive = pool.getDelegated(stablecoins.at(0));
            uint256 poolNewReward =  (newPoolActive - totalBond) - (poolInfo.active - totalUnbond);
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
