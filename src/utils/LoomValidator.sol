// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./CreatorTokenTransferValidator.sol";

uint8 constant LIST_TYPE_TARGET_WHITELIST = 3;

/**
 * @title  LoomValidator
 * @author Abraxas
 * @notice The LoomValidator contract extends CreatorTokenTransferValidator to provide an additional
 *         "to whitelist" feature that allows certain addresses to bypass transfer validation entirely.
 *         This is useful for scenarios where specific addresses (like protocol contracts or bridges)
 *         should be able to receive tokens without any transfer restrictions.
 *
 * @dev    <h4>Additional Features</h4>
 *         - ToWhitelist: Allows collections to whitelist specific addresses that can receive tokens
 *           without any transfer validation being applied.
 *         - Bypass validation: When the 'to' address is on the toWhitelist, the _validateTransfer
 *           function is completely skipped, allowing unrestricted transfers to those addresses.
 *
 * @dev    <h4>Benefits</h4>
 *         - Protocol integration: Enables seamless integration with other protocols and bridges
 *           that may need to receive tokens without transfer restrictions.
 *         - Flexible security: Maintains all existing security features while providing escape hatches
 *           for trusted addresses.
 *         - Gas optimization: Bypasses validation entirely for whitelisted receivers, saving gas.
 *
 * @dev    <h4>Use Cases</h4>
 *         - Cross-chain bridges that need to receive tokens for bridging
 *         - Protocol contracts that manage token staking or lending
 *         - Marketplace contracts that need to hold tokens during sales
 *         - Emergency rescue contracts for token recovery
 */

contract LoomValidator is CreatorTokenTransferValidator {
    using EnumerableSet for EnumerableSet.AddressSet;
    uint16 private constant DEFAULT_TOKEN_TYPE = 0;

    /*************************************************************************/
    /*                             CUSTOM ERRORS                             */
    /*************************************************************************/

    /// @dev Thrown when attempting to call a function that requires owner or default admin role for a collection that the caller does not have.
    error LoomValidator__CallerMustHaveElevatedPermissionsForSpecifiedNFT();

    /// @dev Thrown when attempting to add a zero address to the to whitelist.
    error LoomValidator__CannotAddZeroAddressToToWhitelist();

    /*************************************************************************/
    /*                                EVENTS                                 */
    /*************************************************************************/

    /// @dev Emitted when an address is added to the to whitelist for a collection.
    event AddedToWhitelistForCollection(address indexed collection, address indexed toAddress);

    /// @dev Emitted when an address is removed from the to whitelist for a collection.
    event RemovedFromToWhitelistForCollection(address indexed collection, address indexed toAddress);

    /*************************************************************************/
    /*                                STORAGE                                */
    /*************************************************************************/

    /// @dev Mapping of collection addresses to their to whitelist settings
    mapping(uint120 => List) internal targetWhitelist;

    /*************************************************************************/
    /*                             CONSTRUCTOR                               */
    /*************************************************************************/

    constructor(
        address defaultOwner,
        address eoaRegistry_,
        string memory name,
        string memory version,
        address validatorConfiguration
    ) CreatorTokenTransferValidator(
        defaultOwner,
        eoaRegistry_,
        name,
        version,
        validatorConfiguration
    ) {}

    /**
     * @notice Adds one or more accounts to a targetWhitelist.
     *
     * @dev Throws when the caller does not own the specified list.
     * @dev Throws when the accounts array is empty.
     *
     * @dev <h4>Postconditions:</h4>
     *      1. Accounts not previously in the list are added.
     *      2. An `AddedAccountToList` event is emitted for each account that is newly added to the list.
     *
     * @param id       The id of the list.
     * @param accounts The addresses of the accounts to add.
     */
    function addAccountsToTargetWhitelist(uint120 id, address[] calldata accounts) external {
        _addAccountsToList(targetWhitelist[id], LIST_TYPE_TARGET_WHITELIST, id, accounts);
    }

        /**
     * @notice Removes one or more accounts from a whitelist.
     *
     * @dev Throws when the caller does not own the specified list.
     * @dev Throws when the accounts array is empty.
     *
     * @dev <h4>Postconditions:</h4>
     *      1. Accounts previously in the list are removed.
     *      2. A `RemovedAccountFromList` event is emitted for each account that is removed from the list.
     *
     * @param id       The id of the list.
     * @param accounts The addresses of the accounts to remove.
     */
    function removeAccountsToTargetWhitelist(
        uint120 id,
        address[] calldata accounts
    ) external {
        _removeAccountsFromList(targetWhitelist[id], LIST_TYPE_TARGET_WHITELIST, id, accounts);
    }

    /**
     * @notice Get whitelisted accounts by list id.
     * @param  id The id of the list.
     * @return An array of whitelisted accounts.
     */
    function getTargetWhitelistedAccounts(uint120 id) public view returns (address[] memory) {
        return targetWhitelist[id].enumerableAccounts.values();
    }

    /**
     * @notice Check if an account is whitelisted in a specified list.
     * @param id       The id of the list.
     * @param account  The address of the account to check.
     * @return         True if the account is whitelisted in the specified list, false otherwise.
     */
    function isAccountTargetWhitelisted(uint120 id, address account) public view returns (bool) {
        return targetWhitelist[id].nonEnumerableAccounts[account];
    }

    /*************************************************************************/
    /*                       OVERRIDDEN VALIDATION LOGIC                     */
    /*************************************************************************/
  /**
     * @notice Apply the collection transfer policy to a transfer operation of a creator token.
     *
     * @dev If the caller is self (Permit-C Processor) it means we have already applied operator validation in the
     *      _beforeTransferFrom callback.  In this case, the security policy was already applied and the operator
     *      that used the Permit-C processor passed the security policy check and transfer can be safely allowed.
     *
     * @dev The order of checking whitelisted accounts, authorized operator check and whitelisted codehashes
     *      is very deliberate.  The order of operations is determined by the most frequently used settings that are
     *      expected in the wild.
     *
     * @dev Throws when the collection has enabled account freezing mode and either the `from` or `to` addresses
     *      are on the list of frozen accounts for the collection.
     * @dev Throws when the collection is set to Level 9 - Soulbound Token.
     * @dev Throws when the receiver has deployed code and isn't whitelisted, if ReceiverConstraints.NoCode is set
     *      and the transfer is not approved by an authorizer for the collection.
     * @dev Throws when the receiver has never verified a signature to prove they are an EOA and the receiver
     *      isn't whitelisted, if the ReceiverConstraints.EOA is set and the transfer is not approved by an
     *      authorizer for the collection..
     * @dev Throws when `msg.sender` is blacklisted, if CallerConstraints.OperatorBlacklistEnableOTC is set, unless
     *      `msg.sender` is also the `from` address or the transfer is approved by an authorizer for the collection.
     * @dev Throws when `msg.sender` isn't whitelisted, if CallerConstraints.OperatorWhitelistEnableOTC is set, unless
     *      `msg.sender` is also the `from` address or the transfer is approved by an authorizer for the collection.
     * @dev Throws when neither `msg.sender` nor `from` are whitelisted, if
     *      CallerConstraints.OperatorWhitelistDisableOTC is set and the transfer
     *      is not approved by an authorizer for the collection.
     *
     * @dev <h4>Postconditions:</h4>
     *      1. Transfer is allowed or denied based on the applied transfer policy.
     *
     * @param collection  The collection address of the token being transferred.
     * @param caller      The address initiating the transfer.
     * @param from        The address of the token owner.
     * @param to          The address of the token receiver.
     * @param tokenId     The token id being transferred.
     *
     * @return The selector value for an error if the transfer is not allowed, `SELECTOR_NO_ERROR` if the transfer is allowed.
     */
    function _validateTransfer(
        function(address,address,uint256) internal view returns(bool) _callerAuthorizedParam,
        address collection,
        address caller,
        address from,
        address to,
        uint256 tokenId
    ) internal view override returns (bytes4,uint16) {


        CollectionSecurityPolicyV3 storage collectionSecurityPolicy = collectionSecurityPolicies[collection];
        uint120 listId = collectionSecurityPolicy.listId;
        List storage targetWhitelist = targetWhitelist[listId];
        // If the 'to' address is on the toWhitelist for this collection, bypass validation
        if (targetWhitelist.nonEnumerableAccounts[to]) {
            return (SELECTOR_NO_ERROR, DEFAULT_TOKEN_TYPE);
        }

        // Otherwise, use the parent contract's validation logic
        return super._validateTransfer(_callerAuthorizedParam, collection, caller, from, to, tokenId );
    }

}
