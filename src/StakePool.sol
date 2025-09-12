// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IStakePool.sol";
import "./interfaces/IGovInstantManager.sol";
import "./base/Ownable.sol";

contract StakePool is Initializable, UUPSUpgradeable, Ownable, IStakePool {
    // Custom errors to provide more descriptive revert messages.
    error FailedToWithdrawForStaker();

    event WithdrawForStaker(address staker, address receivingToken, uint256 amount);

    using SafeERC20 for IERC20;

    address public stakeManagerAddress;
    address public govInstantManagerAddress;
    address public govOracleAddress;

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
        govInstantManagerAddress = _govInstantManagerAddress;
        govOracleAddress = _govOracleAddress;

        _transferOwnership(_owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ------------ getter ------------

    function version() external view returns (uint64) {
        return _getInitializedVersion();
    }

    function getDelegated() external view override returns (uint256) {
        address token = IGovInstantManager(govInstantManagerAddress).rwaToken();
        return IERC20(token).balanceOf(address(this));
    }

    // ------------ stakeManager ------------

    function delegate(address _depositToken, uint256 _amount) external override onlyStakeManager returns (uint256) {
        // TODO: calc minimumRwaReceived before delegate
        uint256 minimumRwaReceived = 0;
        IERC20(_depositToken).safeIncreaseAllowance(govInstantManagerAddress, _amount);
        return IGovInstantManager(govInstantManagerAddress).subscribe(_depositToken, _amount, minimumRwaReceived);
    }

    function undelegate(address _receivingToken, uint256 _claimAmount)
        external
        override
        onlyStakeManager
        returns (uint256)
    {
        // TODO: calc minimumTokenReceived before delegate
        uint256 minimumTokenReceived = 0;
        address rwaToken = IGovInstantManager(govInstantManagerAddress).rwaToken();
        IERC20(rwaToken).safeIncreaseAllowance(govInstantManagerAddress, _claimAmount);
        return IGovInstantManager(govInstantManagerAddress).redeem(_claimAmount, _receivingToken, minimumTokenReceived);
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
