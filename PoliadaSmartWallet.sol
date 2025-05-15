// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@account-abstraction/contracts/core/BaseAccount.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract PoliadaSmartWallet is Initializable, BaseAccount, ERC1155HolderUpgradeable, ReentrancyGuardUpgradeable {
    using ECDSA for bytes32;

    address public owner;
    mapping(address => bool) private guardians;
    address[] public guardiansList;
    uint256 public recoveryThreshold;
    bool private initialized;

    IEntryPoint private _entryPoint;

    event WalletInitialized(address indexed owner, address[] guardians, uint256 recoveryThreshold);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event ExecuteFailed(bytes returnData);

    modifier onlyEntryPoint() {
        require(msg.sender == address(_entryPoint), "Caller is not EntryPoint");
        _;
    }

    function initialize(
        address ownerArg,
        address[] memory guardiansArg,
        uint256 recoveryThresholdArg,
        IEntryPoint entryPointAddress
    ) external initializer {
        __ERC1155Holder_init();
        __ReentrancyGuard_init();
        require(!initialized, "Already initialized");
        require(ownerArg != address(0), "Invalid owner address");
        require(guardiansArg.length >= recoveryThresholdArg, "Invalid recovery threshold");

        initialized = true;
        owner = ownerArg;
        recoveryThreshold = recoveryThresholdArg;
        _entryPoint = entryPointAddress;

        for (uint256 i = 0; i < guardiansArg.length; i++) {
            address guardian = guardiansArg[i];
            require(guardian != address(0), "Invalid guardian address");
            guardians[guardian] = true;
            guardiansList.push(guardian);
        }

        emit WalletInitialized(owner, guardiansList, recoveryThreshold);
    }

    function entryPoint() public view override returns (IEntryPoint) {
        return _entryPoint;
    }

    function _call(address dest, uint256 value, bytes memory func) internal nonReentrant {
        (bool success, bytes memory returnData) = dest.call{value: value}(func);
        if (!success) {
            emit ExecuteFailed(returnData);
            _revertWithMessage(returnData);
        }
    }

    function _revertWithMessage(bytes memory returnData) internal pure {
        if (returnData.length >= 4) {
            (bytes4 selector, string memory reason) = abi.decode(returnData, (bytes4, string));
            if (selector == bytes4(keccak256("Error(string)"))) {
                revert(reason);
            }
        }
        revert("Transaction failed without error message");
    }

    function execute(address dest, uint256 value, bytes calldata func) external {
        require(msg.sender == owner || msg.sender == address(_entryPoint), "Only owner or EntryPoint");
        _call(dest, value, func);
    }

    function executeBatch(
        address[] calldata dest,
        uint256[] calldata values,
        bytes[] calldata func
    ) external nonReentrant {
        require(msg.sender == owner || msg.sender == address(_entryPoint), "Only owner or EntryPoint");
        require(dest.length == func.length && dest.length == values.length, "Mismatched array lengths");
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], values[i], func[i]);
        }
    }

    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function isGuardian(address addr) internal view returns (bool) {
        return guardians[addr];
    }

    function _isAddressInArray(address addr, address[] memory addrArray, uint256 arrayLength) internal pure returns (bool) {
        for (uint256 i = 0; i < arrayLength; i++) {
            if (addrArray[i] == addr) {
                return true;
            }
        }
        return false;
    }

    receive() external payable {}

    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
    internal
    view
    override
    returns (uint256 validationData)
    {
        bytes memory signature = userOp.signature;
        bytes32 messageHash = toEthSignedMessageHash(userOpHash);

        uint256 sigLength = signature.length;
        require(sigLength >= 65, "Invalid signature length");

        if (sigLength == 65) {
            address signer = ECDSA.recover(messageHash, signature);
            require(signer == owner, "Invalid owner signature");
            return 0;
        } else {
            require(sigLength % 65 == 0, "Invalid signatures length");
            uint256 sigCount = sigLength / 65;
            require(sigCount >= recoveryThreshold, "Insufficient signatures");

            uint256 validSignatures = 0;
            address[] memory usedGuardians = new address[](sigCount);

            for (uint256 i = 0; i < sigCount; i++) {
                bytes memory singleSig = new bytes(65);
                for (uint256 j = 0; j < 65; j++) {
                    singleSig[j] = signature[i * 65 + j];
                }
                address signerAddress = ECDSA.recover(messageHash, singleSig);

                if (isGuardian(signerAddress) && !_isAddressInArray(signerAddress, usedGuardians, validSignatures)) {
                    usedGuardians[validSignatures] = signerAddress;
                    validSignatures += 1;

                    if (validSignatures >= recoveryThreshold) {
                        break;
                    }
                }
            }

            require(validSignatures >= recoveryThreshold, "Not enough valid guardian signatures");
            return 0;
        }
    }

    function changeOwner(address newOwner, bytes[] calldata guardianSignatures) external {
        require(newOwner != address(0), "Invalid new owner");
        bytes32 messageHash = keccak256(abi.encodePacked(address(this), "changeOwner", newOwner));

        uint256 validSignatures = 0;
        address[] memory usedGuardians = new address[](guardianSignatures.length);

        for (uint256 i = 0; i < guardianSignatures.length; i++) {
            address signer = ECDSA.recover(messageHash, guardianSignatures[i]);

            if (isGuardian(signer) && !_isAddressInArray(signer, usedGuardians, validSignatures)) {
                usedGuardians[validSignatures] = signer;
                validSignatures += 1;

                if (validSignatures >= recoveryThreshold) {
                    break;
                }
            }
        }

        require(validSignatures >= recoveryThreshold, "Not enough valid guardian signatures");

        address oldOwner = owner;
        owner = newOwner;
        emit OwnerChanged(oldOwner, newOwner);
    }
}
