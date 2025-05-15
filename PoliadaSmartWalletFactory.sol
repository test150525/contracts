// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./PoliadaSmartWallet.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract PoliadaSmartWalletFactory is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using Address for address;

    IEntryPoint private _entryPoint;
    address public implementation;

    event WalletCreated(address indexed owner, address walletAddress);

    function initialize(
        address initialOwner,
        IEntryPoint entryPoint,
        address implementationArg
    ) external initializer {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();

        require(implementationArg != address(0), "Zero implementation"); 

        _entryPoint = entryPoint;
        implementation = implementationArg;
    }

    function createWallet(
        address owner,
        address[] memory guardians,
        uint256 recoveryThreshold
    ) external nonReentrant returns (address) {
        address clone = Clones.clone(implementation);

        // Cast the clone address to payable before interacting with the contract
        PoliadaSmartWallet(payable(clone)).initialize(owner, guardians, recoveryThreshold, _entryPoint);

        emit WalletCreated(owner, clone);
        return clone;
    }
}
