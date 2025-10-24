// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./interfaces/ILsdToken.sol";
import "./interfaces/IRateProvider.sol";

contract LsdToken is ERC20Burnable, ILsdToken, IRateProvider {
    // Custom errors to provide more descriptive revert messages.
    error AmountZero();
    error AlreadyInitialized();
    error CallerNotAllowed();
    error AddressNotAllowed();

    event MinterChanged(address oldMinter, address newMinter);

    address public minter;

    modifier onlyMinter() {
        _onlyMinter();
        _;
    }

    function _onlyMinter() internal view {
        if (msg.sender != minter) {
            revert CallerNotAllowed();
        }
    }

    // Construct
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function getRate() public view override returns (uint256) {
        return IRateProvider(minter).getRate();
    }

    function initMinter(address _minter) external override {
        if (minter != address(0)) {
            revert AlreadyInitialized();
        }

        minter = _minter;
    }

    // Mint lsdToken
    function mint(address _to, uint256 _amount) public override onlyMinter {
        // Check lsdToken amount
        if (_amount == 0) revert AmountZero();
        // Update balance & supply
        _mint(_to, _amount);
    }

    function updateMinter(address _newMinter) external override onlyMinter {
        if (_newMinter == address(0)) revert AddressNotAllowed();
        emit MinterChanged(minter, _newMinter);
        minter = _newMinter;
    }
}
