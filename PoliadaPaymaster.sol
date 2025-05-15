// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./abstracts/BasePaymaster.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract PoliadaPaymaster is OwnableUpgradeable, BasePaymaster, ReentrancyGuardUpgradeable {
    using UserOperationLib for PackedUserOperation;
    using SafeERC20 for IERC20;

    error PaymasterValidationFailed(string reason);

    event RequiredTokens(uint256 tokens);
    event PostOpSuccess(bool success, uint256 amount);
    event PostOpFailure(string reason);
    event TokenPricePerGasUpdated(uint256 newPrice);
    event TokensWithdrawn(address indexed to, uint256 amount);

    bytes4 private constant EXECUTE_SELECTOR = bytes4(keccak256("execute(address,uint256,bytes)"));
    bytes4 private constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));

    IERC20 public token;

    uint256 public tokenPricePerGas;

    function initializePaymaster(
        address initialOwner,
        IEntryPoint entryPointArg,
        IERC20 tokenArg,
        uint256 tokenPricePerGasArg
    ) public initializer {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        BasePaymaster.initialize(initialOwner, entryPointArg);
        token = tokenArg;
        tokenPricePerGas = tokenPricePerGasArg;
    }

    function setTokenPricePerGas(uint256 tokenPricePerGasArg)
    external
    onlyOwner
    {
        tokenPricePerGas = tokenPricePerGasArg;
        emit TokenPricePerGasUpdated(tokenPricePerGasArg);
    }

    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal override returns (bytes memory context, uint256 validationData) {
        address sender = userOp.getSender();
        bytes memory callData = userOp.callData;

        require(callData.length >= 4, "callData is too short");

        bytes4 outerFunctionSelector = bytes4(callData);

        if (outerFunctionSelector == EXECUTE_SELECTOR) {
            bytes memory params = new bytes(callData.length - 4);
            for (uint256 i = 0; i < params.length; i++) {
                params[i] = callData[i + 4];
            }

            (address to, uint256 value, bytes memory innerCallData) = abi.decode(params, (address, uint256, bytes));

            require(to != address(0), "Invalid 'to' address");

            if (to == address(token)) {
                require(innerCallData.length >= 4, "Inner callData is too short");

                bytes4 innerFunctionSelector = bytes4(innerCallData);

                if (innerFunctionSelector == APPROVE_SELECTOR) {
                    bytes memory innerParams = new bytes(innerCallData.length - 4);
                    for (uint256 i = 0; i < innerParams.length; i++) {
                        innerParams[i] = innerCallData[i + 4];
                    }

                    (address spender, uint256 amount) = abi.decode(innerParams, (address, uint256));

                    if (spender == address(this)) {
                        context = abi.encode(sender, 0);
                        validationData = 0;
                        emit RequiredTokens(0);
                        return (context, validationData);
                    }
                }
            }
        }

        uint256 requiredTokens = maxCost * tokenPricePerGas;

        uint256 allowance = token.allowance(sender, address(this));
        require(allowance >= requiredTokens, "Insufficient token allowance");

        uint256 balance = token.balanceOf(sender);
        require(balance >= requiredTokens, "Insufficient token balance");

        context = abi.encode(sender, requiredTokens);
        validationData = 0;

        emit RequiredTokens(requiredTokens);

        return (context, validationData);
    }

    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override nonReentrant {
        (address sender, uint256 requiredTokens) = abi.decode(context, (address, uint256));

        if (mode == PostOpMode.opSucceeded) {
            token.safeTransferFrom(sender, address(this), requiredTokens);
            emit PostOpSuccess(true, requiredTokens);
        } else {
            emit PostOpFailure("User operation failed; no fee deducted");
        }
    }

    function withdrawTokens(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Cannot withdraw to zero address");
        uint256 contractBalance = token.balanceOf(address(this));
        require(amount <= contractBalance, "Insufficient contract balance");

        token.safeTransfer(to, amount);
        emit TokensWithdrawn(to, amount);
    }
}
