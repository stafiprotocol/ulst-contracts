// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// add errors here for decoding revert messages in tests
interface ondoErrors {
    /// Error emitted when the token address is zero
    error TokenAddressCantBeZero();

    /// Error emitted when the token is not accepted for subscription
    error TokenNotAccepted();

    /// Error emitted when the deposit amount is too small
    error DepositAmountTooSmall();

    /// Error emitted when rwa amount is below the `minimumRwaReceived` in a subscription
    error RwaReceiveAmountTooSmall();

    /// Error emitted when the user is not registered with the ID registry
    error UserNotRegistered();

    /// Error emitted when the redemption amount is too small
    error RedemptionAmountTooSmall();

    /// Error emitted when the receive amount is below the `minimumReceiveAmount` in a redemption
    error ReceiveAmountTooSmall();

    /// Error emitted when attempting to set the `OndoTokenRouter` address to zero
    error RouterAddressCantBeZero();

    /// Error emitted when attempting to set the `OndoOracle` address to zero
    error OracleAddressCantBeZero();

    /// Error emitted when attempting to set the `OndoCompliance` address to zero
    error ComplianceAddressCantBeZero();

    /// Error emitted when attempting to set the `OndoIDRegistry` address to zero
    error IDRegistryAddressCantBeZero();

    /// Error emitted when attempting to set the `OndoRateLimiter` address to zero
    error RateLimiterAddressCantBeZero();

    /// Error emitted when attempting to set the `OndoFees` address to zero
    error FeesAddressCantBeZero();

    /// Error emitted when attempting to set the `AdminSubscriptionChecker` address to zero
    error AdminSubscriptionCheckerAddressCantBeZero();

    /// Error emitted when the price of RWA token returned from the oracle is below the minimum price
    error RWAPriceTooLow();

    /// Error emitted when the subscription functionality is paused
    error SubscriptionsPaused();

    /// Error emitted when the redemption functionality is paused
    error RedemptionsPaused();

    /// Error emitted when the fee is greater than the redemption amount
    error FeeGreaterThanRedemption();

    /// Error emitted when the fee is greater than the subscription amount
    error FeeGreaterThanSubscription();

    // registry

    /// Error thrown when the RWA token address is 0x0
    error RWAAddressCannotBeZero();

    /// Error thrown when the user address is 0x0
    error AddressCannotBeZero();

    /// Error thrown when the user address is already associated with the user ID
    error AddressAlreadyAssociated();

    /// Error thrown when attempting to set a user ID to 0x0
    error InvalidUserId();

    /// Error thrown when the caller does not have the required role to set a user ID
    error MissingRWAOrMasterConfigurerRole();
}

interface IOndoTokenRouterErrors {
    /// Error thrown when attempting to set a recipient or source with a zero address for the RWA token.
    error RwaTokenCantBeZero();

    /// Error thrown when attempting to set a recipient with a zero address for the token.
    error DepositTokenCantBeZero();

    /// Error thrown when attempting to set a source with a zero address for the token.
    error WithdrawTokenCantBeZero();

    /// Error thrown when attempting to set the oracle or minimum price for a token with a zero address.
    error TokenAddressCantBeZero();

    /// Error thrown when calling `setMinimumTokenPriceAndOracle` with only some of the parameters set.
    error InconsistentMinimumTokenPriceParameters();

    /// Error thrown when the price pulled from a token's oracle is outdated.
    error OraclePriceOutdated();

    /// Error thrown a token's price is below the minimum.
    error TokenPriceBelowMinimum();

    /// Error thrown when a deposit token doesn't have a recipient set.
    error TokenRecipientNotSet();

    /// Error thrown when there aren't enough withdraw tokens available.
    error InsufficientWithdrawTokens();

    /// Error thrown when attempting to set a user ID to the zero bytes32 value.
    error UserIDCantBeZero();
}
