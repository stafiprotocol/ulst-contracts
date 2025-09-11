// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

interface Errors {
    error NotInitialized();
    error AddressNotAllowed();
    error AlreadyInitialized();

    error CallerNotAllowed();
    error FailedToCall();
    error NotAuthorizedLsdToken();
    error ValidatorsLenExceedLimit();
    error ValidatorsEmpty();
    error CommissionRateInvalid();
}
