// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/Ondo.sol";
import "./base/Ownable.sol";
import "./interfaces/IStakePool.sol";
import {IAavePool} from "./interfaces/Aave.sol";

contract AaveStakePool is Initializable, UUPSUpgradeable, Ownable, IStakePool {
    // Custom errors to provide more descriptive revert messages.
    error FailedToWithdrawForStaker();

    event Delegate(address pool, address stablecoin, uint256 amount);
    event Undelegate(address pool, address rwaToken, uint256 amount);
    event WithdrawForStaker(address staker, address receivingToken, uint256 amount);
    event MissingUnbondingFee(address stablecoin, uint256 amount);
    event PayMissingUnbondingFee(address payer, address stablecoin, uint256 amount);

    using SafeERC20 for IERC20;

    address public stakeManagerAddress;
    IAavePool public aavePool;
    uint16 referralCode = 0;
    mapping(address => address) public stablecoinToAaveToken;

    modifier onlyStakeManager() {
        _onlyStakeManager();
        _;
    }

    function _onlyStakeManager() internal view {
        if (stakeManagerAddress != msg.sender) revert CallerNotAllowed();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _stakeManagerAddress, address _aavePoolAddress, address _owner) external initializer {
        if (_stakeManagerAddress == address(0) || _aavePoolAddress == address(0) || _owner == address(0)) {
            revert AddressNotAllowed();
        }

        stakeManagerAddress = _stakeManagerAddress;
        aavePool = IAavePool(_aavePoolAddress);
        _transferOwnership(_owner);
    }

    function setStablecoinToAaveToken(address _stablecoin, address _aaveToken) external onlyOwner {
        if (_stablecoin == address(0) || _aaveToken == address(0)) revert AddressNotAllowed();
        stablecoinToAaveToken[_stablecoin] = _aaveToken;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setAavePool(address _aavePoolAddress) external onlyOwner {
        if (_aavePoolAddress == address(0)) revert AddressNotAllowed();
        aavePool = IAavePool(_aavePoolAddress);
    }

    // ------------ getter ------------

    function version() external view returns (uint64) {
        return _getInitializedVersion();
    }

    function getDelegated(address _stablecoin) external view override returns (uint256) {
        return IERC20(stablecoinToAaveToken[_stablecoin]).balanceOf(address(this));
    }

    // ------------ stakeManager ------------

    function delegate(address _depositToken, uint256 _amount) external override onlyStakeManager returns (uint256) {
        IERC20(_depositToken).safeIncreaseAllowance(address(aavePool), _amount);
        aavePool.supply(_depositToken, _amount, address(this), referralCode);
        return _amount;
    }

    function undelegate(address _receivingToken, uint256 _undelegateAmount)
        external
        override
        onlyStakeManager
        returns (uint256)
    {
        IERC20(stablecoinToAaveToken[_receivingToken]).safeIncreaseAllowance(address(aavePool), _undelegateAmount);
        aavePool.withdraw(_receivingToken, _undelegateAmount, address(this));
        return _undelegateAmount;
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
}
