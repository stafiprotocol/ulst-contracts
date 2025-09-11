// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./Ownable.sol";

abstract contract DelegationBalancer is Ownable {
    address public delegationBalancer;

    modifier onlyDelegationBalancer() {
        if (delegationBalancer != msg.sender) revert CallerNotAllowed();
        _;
    }

    function transferDelegationBalancer(address _newDelegationBalancer) external virtual onlyOwner {
        if (_newDelegationBalancer == address(0)) revert AddressNotAllowed();
        delegationBalancer = _newDelegationBalancer;
    }

    function _initDelegationBalancer() internal virtual onlyInitializing {
        delegationBalancer = owner();
    }
}
