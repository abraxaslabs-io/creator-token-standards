// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TransferValidator.t.sol";
import {LoomValidator, LIST_TYPE_TARGET_WHITELIST} from "../src/utils/LoomValidator.sol";

contract LoomValidatorTest is TransferValidatorTest {
    LoomValidator public loomValidator;

    function setUp() public virtual override {
        super.setUp();

        // Deploy LoomValidator instead of the regular CreatorTokenTransferValidator
        loomValidator = new LoomValidator(
            address(this),
            address(eoaRegistry),
            "LoomValidator",
            "1.0.0",
            address(validatorConfiguration)
        );

        validator = loomValidator;
    }

    /*************************************************************************/
    /*                   TARGET WHITELIST MANAGEMENT TESTS                   */
    /*************************************************************************/
    function testAddAccountsToTargetWhitelist(address listOwner, uint256 numAccountsToWhitelist, address[10] memory accounts) public {
        _sanitizeAddress(listOwner);
        numAccountsToWhitelist = bound(numAccountsToWhitelist, 0, 10);

        vm.prank(listOwner);
        uint120 listId = validator.createList("test");

        uint256 expectedNumAccountsWhitelisted = 0;
        address[] memory accountsToWhitelist = new address[](numAccountsToWhitelist);
        for (uint256 i = 0; i < numAccountsToWhitelist; i++) {
            bool firstTimeAccount = true;
            for (uint256 j = 0; j < i; j++) {
                if (accountsToWhitelist[j] == accounts[i]) {
                    firstTimeAccount = false;
                    break;
                }
            }

            accountsToWhitelist[i] = accounts[i];

            if (firstTimeAccount) {
                expectedNumAccountsWhitelisted++;
                vm.expectEmit(true, true, true, true);
                emit AddedAccountToList(LIST_TYPE_TARGET_WHITELIST, listId, accounts[i]);
            }
        }

        vm.prank(listOwner);
        loomValidator.addAccountsToTargetWhitelist(listId, accountsToWhitelist);

        for (uint256 i = 0; i < numAccountsToWhitelist; i++) {
            assertTrue(loomValidator.isAccountTargetWhitelisted(listId, accountsToWhitelist[i]));
        }

        address[] memory whitelistedAccounts = loomValidator.getTargetWhitelistedAccounts(listId);
        assertEq(whitelistedAccounts.length, expectedNumAccountsWhitelisted);
    }

}
