// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface ERC20 {
    function mint(
        address _to,
        uint256 _value
    ) external;
}

contract Treasury is OwnableUpgradeable, AccessControlUpgradeable {

    struct Struct {
        uint256 amount;
        uint256 time;
    }
    uint256[] private mintAmountBySeasons;
    uint256[] private seasonsStartTime;
    uint256 currentSeason;
    address _mintContract;

    function initialize(address initialOwner, address mintContract) external initializer {
         require(mintContract != address(0), "Mint contract address cannot be zero");

        __Ownable_init(initialOwner);
        _mintContract = mintContract;
        currentSeason = 0;
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
    }

    function getTreasurySeasons() public view returns (Struct[] memory) {
        uint len = mintAmountBySeasons.length;
        Struct[] memory result = new Struct[](mintAmountBySeasons.length);
        for (uint i = 0; i < len; i++) {
            result[i] = Struct(mintAmountBySeasons[i], seasonsStartTime[i]);
        }
        return result;
    }

    function checkForReleasing() onlyRole(DEFAULT_ADMIN_ROLE) public returns (bool){
        require(seasonsStartTime.length >= (currentSeason + 1), "No new seasons to start");
        require(seasonsStartTime[currentSeason] < block.timestamp, "New season not started");

        uint256 seasonToRelease = currentSeason;
        currentSeason = currentSeason + 1;

        ERC20 (_mintContract).mint(_mintContract, mintAmountBySeasons[seasonToRelease]);

        return true;
    }

    function createNewSeason(uint256 amount, uint256 startTime) onlyRole(DEFAULT_ADMIN_ROLE) public returns (uint){
        require(startTime > block.timestamp, "Start time should be in the future");
        require(amount > 0, "Amount should be not 0");

        mintAmountBySeasons.push(amount);
        seasonsStartTime.push(startTime);

        return seasonsStartTime.length - 1;
    }

    function addTreasuryToSeason(uint256 amount, uint256 season) public onlyRole(DEFAULT_ADMIN_ROLE) {
        mintAmountBySeasons[season] = mintAmountBySeasons[season] + amount;
    }
}