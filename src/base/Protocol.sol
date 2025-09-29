// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Ownable.sol";
import "../interfaces/ILsdToken.sol";

abstract contract Protocol is Ownable {
    // Custom errors to provide more descriptive revert messages.
    error GreaterThanMaxProtocolFeeCommission(uint256 protocolFeeCommission);
    error InvalidRate();

    using SafeERC20 for IERC20;

    uint256 public constant MAX_PROTOCOL_FEE_COMMISSION = 2 * 1e17;

    address public lsdToken;
    uint256 public protocolFeeCommission;
    uint256 public totalProtocolFee;

    address public factoryAddress;
    uint256 public factoryFeeCommission;

    uint256 public unbondingFee;

    function setUnbondingFee(uint256 _unbondingFee) external virtual onlyOwner {
        unbondingFee = _unbondingFee;
    }

    function withdrawProtocolFee(address _to) external virtual onlyOwner {
        IERC20(lsdToken).safeTransfer(_to, IERC20(lsdToken).balanceOf(address(this)));
    }

    function setProtocolFeeCommission(uint256 _protocolFeeCommission) external virtual onlyOwner {
        if (_protocolFeeCommission > MAX_PROTOCOL_FEE_COMMISSION) {
            revert GreaterThanMaxProtocolFeeCommission(_protocolFeeCommission);
        }

        protocolFeeCommission = _protocolFeeCommission;
    }

    function setFactoryFeeCommission(uint256 _factoryFeeCommission) external onlyOwner {
        if (_factoryFeeCommission > 1e18) {
            revert CommissionRateInvalid();
        }
        factoryFeeCommission = _factoryFeeCommission;
    }

    function _initProtocolParams(address _lsdToken, address _factoryAddress) internal virtual onlyInitializing {
        if (_lsdToken == address(0) || _factoryAddress == address(0)) revert AddressNotAllowed();

        lsdToken = _lsdToken;
        factoryAddress = _factoryAddress;
        protocolFeeCommission = 1e17;
        factoryFeeCommission = 1e17;
    }

    function _distributeReward(uint256 _totalNewReward, uint256 _rate) internal {
        if (_rate == 0) revert InvalidRate();
        if (_totalNewReward > 0) {
            uint256 lsdTokenProtocolFee = (_totalNewReward * protocolFeeCommission) / _rate;
            uint256 factoryFee = (lsdTokenProtocolFee * factoryFeeCommission) / 1e18;
            lsdTokenProtocolFee = lsdTokenProtocolFee - factoryFee;

            if (lsdTokenProtocolFee > 0) {
                totalProtocolFee = totalProtocolFee + lsdTokenProtocolFee;
                // mint lsdToken
                ILsdToken(lsdToken).mint(address(this), lsdTokenProtocolFee);
            }

            if (factoryFee > 0) {
                ILsdToken(lsdToken).mint(factoryAddress, factoryFee);
            }
        }
    }
}
