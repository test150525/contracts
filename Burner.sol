// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface BurnToken is IERC20 {
    function burn(address account, uint256 amount) external;
}

contract Burner is OwnableUpgradeable, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    BurnToken public token;

    function initialize(
        address initialOwner,
        BurnToken tokenArg
    ) external initializer {
        __Ownable_init(initialOwner);
        __AccessControl_init();

        token = tokenArg;

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(ADMIN_ROLE, initialOwner);
    }

    function addAdmin(address account) external onlyOwner {
        grantRole(ADMIN_ROLE, account);
    }

    function removeAdmin(address account) external onlyOwner {
        revokeRole(ADMIN_ROLE, account);
    }

    function burnTokens() public onlyRole(ADMIN_ROLE) {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to burn");
        token.burn(address(this), balance);
    }
}
