// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract PadaCoin is ERC20Upgradeable, OwnableUpgradeable, AccessControlUpgradeable {
    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');
    bytes32 public constant BURNER_ROLE = keccak256('BURNER_ROLE');
    uint256 constant MAX_TOTAL_SUPPLY = 10**27;
    uint256 private totalMinted;

    event SupplyIncreased(
        address indexed minter,
        uint256 amount,
        uint256 newSupply
    );

    event SupplyDecreased(
        address indexed burner,
        uint256 amount,
        uint256 newSupply
    );

    struct Statistic {
        uint256 totalSupply;
        uint256 amount;
    }

    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(MINTER_ROLE, initialOwner);
        _grantRole(BURNER_ROLE, initialOwner);
        __ERC20_init("Poliada Coin", "PADA");
        totalMinted = 0;
    }

    function mint(address to, uint256 amount) public onlyMinter {
        require((amount + totalMinted) <= MAX_TOTAL_SUPPLY, "Max supply reached");
        totalMinted = totalMinted + amount;
        _mint(to, amount);

        emit SupplyIncreased(msg.sender, amount, totalMinted);
    }

    function getBalance() public view returns(uint256){
        return address(this).balance;
    }

    function getStatistics() public view returns(Statistic memory){
        uint256 amount = IERC20(address(this)).balanceOf(address(this));

        return Statistic(
            totalMinted,
            amount
        );
    }

    function burn(address account, uint256 amount) public onlyBurner {
        totalMinted = totalMinted - amount;
        _burn(account, amount);

        emit SupplyDecreased(msg.sender, amount, totalMinted);
    }

    function isMinter(address account) public virtual view returns (bool)
    {
        return hasRole(MINTER_ROLE, account);
    }

    function isBurner(address account) public virtual view returns (bool)
    {
        return hasRole(BURNER_ROLE, account);
    }

    function addMinter(address account) public onlyOwner ()
    {
        return grantRole(MINTER_ROLE, account);
    }

    function addBurner(address account) public onlyOwner ()
    {
        return grantRole(BURNER_ROLE, account);
    }

    modifier onlyMinter()
    {
        require(isMinter(msg.sender), 'Restricted to users.');
        _;
    }

    modifier onlyBurner()
    {
        require(isBurner(msg.sender), 'Restricted to users.');
        _;
    }
}
