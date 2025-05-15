// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Underground.sol";
import "./Burner.sol";

contract Vault is OwnableUpgradeable, ReentrancyGuardUpgradeable {

    enum PoolType { Standard, Underground, Burner }

    struct Pool {
        bytes poolName;
        uint256 percents;
        address contractAddress;
        PoolType poolType;
        uint256 balance;
    }
    IERC20 public token;
    mapping(uint256 => Pool) private pools;
    uint public poolCount;

    event PoolConfigured(bytes poolName, uint256 percents, address contractAddress, PoolType poolType);
    event TokensDistributed(uint256 poolId, address contractAddress, uint256 amount);

    function initialize(address initialOwner, address tokenArg) external initializer {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        token = IERC20(tokenArg);
        poolCount = 0;
    }

    function setPoolConfig(
        bytes memory poolName,
        uint256 percents,
        address contractAddress,
        PoolType poolType
    ) public onlyOwner {
        require(poolName.length > 0, "Pool name should not be empty");
        require(percents > 0 && percents <= 100, "Percents should be in range 1-100");
        require(contractAddress != address(this), "Contract address should not be this address");
        require(contractAddress != address(0), "Invalid contract address");

        uint totalPercents = 0;
        uint poolIndex = 0;
        bool poolExists = false;

        for (uint id = 0; id < poolCount; id++) {
            Pool storage _pool = pools[id];
            if (keccak256(poolName) == keccak256(_pool.poolName)) {
                poolExists = true;
                poolIndex = id;
            } else {
                totalPercents += _pool.percents;
            }
        }

        require((totalPercents + percents) <= 100, "Overall percentage above 100");

        if (poolExists) {
            pools[poolIndex].percents = percents;
            pools[poolIndex].contractAddress = contractAddress;
            pools[poolIndex].poolType = poolType;
        } else {
            pools[poolCount] = Pool(
                poolName,
                percents,
                contractAddress,
                poolType,
                0
            );
            poolCount++;
        }

        emit PoolConfigured(poolName, percents, contractAddress, poolType);
    }

    function calculatePools() public view onlyOwner returns (Pool[] memory) {
        uint256 balance = token.balanceOf(address(this));

        Pool[] memory lPools = new Pool[](poolCount);
        for (uint i = 0; i < poolCount; i++) {
            Pool storage lPool = pools[i];
            lPools[i] = Pool(
                lPool.poolName,
                lPool.percents,
                lPool.contractAddress,
                lPool.poolType,
                (balance * lPool.percents) / 100
            );
        }
        return lPools;
    }

    function sendToPools() public onlyOwner nonReentrant {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to distribute");

        for (uint id = 0; id < poolCount; id++) {
            Pool storage _pool = pools[id];
            uint256 amount = (balance * _pool.percents) / 100;
            require(amount > 0, "Amount must be greater than zero");

            if (_pool.poolType == PoolType.Underground) {
                require(IERC20(token).transfer(_pool.contractAddress, amount), "Transfer failed");
                Underground(_pool.contractAddress).sendRewards(amount);
            } else if (_pool.poolType == PoolType.Burner) {
                require(IERC20(token).transfer(_pool.contractAddress, amount), "Transfer failed");
                Burner(_pool.contractAddress).burnTokens();
            } else {
                require(IERC20(token).transfer(_pool.contractAddress, amount), "Transfer failed");
            }

            emit TokensDistributed(id, _pool.contractAddress, amount);
        }
    }
}
