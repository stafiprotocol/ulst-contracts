// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IStakePool.sol";
import "./interfaces/Ondo.sol";
import "./base/Ownable.sol";

contract StakePool is Initializable, UUPSUpgradeable, Ownable, IStakePool {
    // Custom errors to provide more descriptive revert messages.
    error FailedToWithdrawForStaker();

    event Delegate(address pool, address stablecoin, uint256 amount);
    event Undelegate(address pool, address rwaToken, uint256 amount);
    event WithdrawForStaker(address staker, address receivingToken, uint256 amount);
    event MissingUnbondingFee(address stablecoin, uint256 amount);
    event PayMissingUnbondingFee(address payer, address stablecoin, uint256 amount);

    using SafeERC20 for IERC20;

    address public stakeManagerAddress;
    IOndoInstantManager public ondoInstantManager;
    IOndoOracle public ondoOracle;
    mapping(address => uint256) public totalMissingUnbondingFee;

    modifier onlyStakeManager() {
        if (stakeManagerAddress != msg.sender) revert CallerNotAllowed();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _stakeManagerAddress,
        address _govInstantManagerAddress,
        address _govOracleAddress,
        address _owner
    ) external initializer {
        if (
            _stakeManagerAddress == address(0) || _govInstantManagerAddress == address(0)
                || _govOracleAddress == address(0) || _owner == address(0)
        ) {
            revert AddressNotAllowed();
        }

        stakeManagerAddress = _stakeManagerAddress;
        ondoInstantManager = IOndoInstantManager(_govInstantManagerAddress);
        ondoOracle = IOndoOracle(_govOracleAddress);

        _transferOwnership(_owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ------------ getter ------------

    function version() external view returns (uint64) {
        return _getInitializedVersion();
    }

    function getDelegated(address _stablecoin) external view override returns (uint256) {
        address rwaToken = ondoInstantManager.rwaToken();
        uint256 rwaTokenPrice = ondoOracle.getAssetPrice(rwaToken);

        uint256 rwaAmount = IERC20(rwaToken).balanceOf(address(this));
        uint256 usdValue = (rwaAmount * rwaTokenPrice) / ondoInstantManager.RWA_NORMALIZER();

        uint256 stablecoinPrice = ondoOracle.getAssetPrice(_stablecoin);
        uint256 stablecoinAmount = (usdValue * 10 ** IERC20Metadata(_stablecoin).decimals()) / stablecoinPrice;

        return stablecoinAmount;
    }

    // ------------ stakeManager ------------

    function delegate(address _depositToken, uint256 _amount) external override onlyStakeManager returns (uint256) {
        if (ondoInstantManager.subscribePaused()) return 0;

        uint256 depositUSDValue =
            (ondoOracle.getAssetPrice(_depositToken) * _amount) / 10 ** IERC20Metadata(_depositToken).decimals();
        if (depositUSDValue < ondoInstantManager.minimumDepositUSD()) return 0;

        IERC20(_depositToken).safeIncreaseAllowance(address(ondoInstantManager), _amount);
        return ondoInstantManager.subscribe(_depositToken, _amount, 0);
    }

    function undelegate(address _receivingToken, uint256 _undelegateAmount)
        external
        override
        onlyStakeManager
        returns (uint256)
    {
        if (ondoInstantManager.redeemPaused()) return 0;

        uint256 receivingTokenUSDValue = (ondoOracle.getAssetPrice(_receivingToken) * _undelegateAmount)
            / 10 ** IERC20Metadata(_receivingToken).decimals();
        if (receivingTokenUSDValue < ondoInstantManager.minimumRedemptionUSD()) return 0;

        address rwaToken = ondoInstantManager.rwaToken();
        uint256 receivingTokenPrice = ondoOracle.getAssetPrice(_receivingToken);
        uint256 rwaTokenPrice = ondoOracle.getAssetPrice(rwaToken);

        uint256 usdValue = (receivingTokenPrice * _undelegateAmount) / 10 ** IERC20Metadata(_receivingToken).decimals();
        uint256 rwaAmount = (usdValue * ondoInstantManager.RWA_NORMALIZER()) / rwaTokenPrice;

        IERC20(rwaToken).safeIncreaseAllowance(address(ondoInstantManager), rwaAmount);

        uint256 tokenAmountReceived = ondoInstantManager.redeem(rwaAmount, _receivingToken, 0);
        if (_undelegateAmount > tokenAmountReceived) {
            uint256 missingUnbondingFee = _undelegateAmount - tokenAmountReceived;
            totalMissingUnbondingFee[_receivingToken] += missingUnbondingFee;
            emit MissingUnbondingFee(_receivingToken, missingUnbondingFee);
        }
        return tokenAmountReceived;
    }

    function withdrawForStaker(address _receivingToken, address _staker, uint256 _amount)
        external
        override
        onlyStakeManager
    {
        if (_staker == address(0)) revert AddressNotAllowed();
        if (_amount > 0) {
            IERC20(_receivingToken).safeTransfer(_staker, _amount);
            emit WithdrawForStaker(_staker, _receivingToken, _amount);
        }
    }

    function payMissingUnbondingFee(address[] calldata _stablecoin, uint256[] calldata _amount) external {
        if (_stablecoin.length != _amount.length) revert LengthNotMatch();
        for (uint256 i = 0; i < _stablecoin.length; i++) {
            IERC20(_stablecoin[i]).safeTransferFrom(msg.sender, address(this), _amount[i]);
            totalMissingUnbondingFee[_stablecoin[i]] -= _amount[i];
            emit PayMissingUnbondingFee(msg.sender, _stablecoin[i], _amount[i]);
        }
    }
}
