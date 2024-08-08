// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Abstract contract providing utility functions for accessing the message sender, data, and value
abstract contract Context {
    // Function to get the current blockchain chain ID
    function _chainId() internal view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    // Function to get the address of the message sender
    function _msgSender() internal view returns (address sender) {
        if (msg.sender == address(this)) {
            bytes memory array = msg.data;
            uint256 index = msg.data.length;
            assembly {
                sender := and(mload(add(array, index)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
        } else {
            sender = msg.sender;
        }
    }

    // Function to get the message data
    function _msgData() internal pure returns (bytes calldata) {
        return msg.data;
    }

    // Function to get the value of the message
    function _msgValue() internal view returns (uint256) {
        return msg.value;
    }
}

// Interface for ERC20 standard
interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// Contract for managing ownership of the contract
contract Ownable is Context {
    address private _owner;  // Address of the contract owner

    // Event for ownership transfer
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Constructor to set the initial owner of the contract
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    // Function to get the current owner
    function owner() public view returns (address) {
        return _owner;
    }

    // Modifier to restrict access to only the owner
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    // Function to renounce ownership
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    // Internal function to auto-renounce ownership
    function _autoRenounce() internal {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);        
    }
}

// Pausable contract for emergency pause functionality
abstract contract Pausable is Context {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    error EnforcedPause();
    error ExpectedPause();

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// Reentrancy guard to prevent reentrancy attacks
abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// Main contract for the Picto Token
contract PictoToken is Context, IERC20, Ownable, Pausable, ReentrancyGuard {
    // Addresses for different wallets
    address immutable private _owner;
    address public foundation_Wallet;  // Foundation wallet address (30%)

    // Mappings
    mapping(address => bool) public admins;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _blacklist;
    mapping(address => bool) private _frozenAccounts;    

    // Struct to store initial distribution details
    struct Distribution {
        address account;
        uint256 amount;
    }
    Distribution[] public distributions;

    // Token details
    uint8 private constant _decimals = 18;
    uint256 private _maxTransferAmount = 10000 * 10**18;
    uint256 private _totalSupply = 1200000000 * 10**_decimals;
    string private constant _name = "Picto Token";
    string private constant _symbol = "PICTO";
    string private _tokenMetadataURL;

    // Token distribution shares
    uint256 private constant foundation_Share = 360000000 * 10**_decimals;  // 30% for the foundation
    uint256 private constant team_Share = 120000000 * 10**_decimals;  // 10% for the team
    uint256 private constant allocated_For_LP_Share = 600000000 * 10**_decimals;  // 50% for LP allocation
    uint256 private constant marketing_Share = 120000000 * 10**_decimals;  // 10% for marketing   

    // Modifier to restrict access to authorized addresses
    modifier authorized() {
        if (_msgSender() != _owner && !admins[_msgSender()]) {
            revert UnAuthorizedAccess(_msgSender());
        }
        _;
    }

    // Error for unauthorized access
    error UnAuthorizedAccess(address sender);

    // Error for transfer amount exceeding balance
    error TransferAmountExceedsBalance(address sender, uint256 amount, uint256 balance);

    // Error for transfer amount exceeding allowance
    error TransferAmountExceedsAllowance(address sender, address spender, uint256 amount, uint256 allowance);

    // Constructor to initialize the contract with token metadata URL and mint initial supply
    constructor(string memory metadataURL, address team_Wallet, address allocated_For_LP_Wallet, address marketing_Wallet) payable {
        _tokenMetadataURL = metadataURL;
        _owner = _msgSender();
        foundation_Wallet = payable(_msgSender());
        _balances[address(this)] = _totalSupply;

        // Distribute tokens
        _distributeTokens(foundation_Wallet, foundation_Share);
        _distributeTokens(team_Wallet, team_Share);
        _distributeTokens(allocated_For_LP_Wallet, allocated_For_LP_Share);  // Send to contract for Unicrypt lock
        _distributeTokens(marketing_Wallet, marketing_Share);
    }

    // Function to distribute tokens and store distribution details
    function _distributeTokens(address account, uint256 amount) internal {
        _mint(account, amount);
        distributions.push(Distribution(account, amount));
    }

    // Fallback function to receive Ether
    receive() external payable {}

    // ERC20 functions
    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address receiver, uint256 amount) public override nonReentrant whenNotPaused returns (bool) {
        if (receiver == address(0)) revert InvalidAddress(receiver);
        if (amount == 0) revert InvalidAmount(amount);
        if (_balances[_msgSender()] < amount) revert TransferAmountExceedsBalance(_msgSender(), amount, _balances[_msgSender()]);

        _balances[_msgSender()] -= amount;
        _balances[receiver] += amount;
        emit Transfer(_msgSender(), receiver, amount);
        return true;
    }

    function transferFrom(address owner, address receiver, uint256 amount) public override nonReentrant whenNotPaused returns (bool) {
        if (owner == address(0)) revert InvalidAddress(owner);
        if (receiver == address(0)) revert InvalidAddress(receiver);
        if (amount == 0) revert InvalidAmount(amount);
        if (_balances[owner] < amount) revert TransferAmountExceedsBalance(owner, amount, _balances[owner]);
        if (_allowances[owner][_msgSender()] < amount) revert TransferAmountExceedsAllowance(owner, _msgSender(), amount, _allowances[owner][_msgSender()]);

        _balances[owner] -= amount;
        _allowances[owner][_msgSender()] -= amount;
        _balances[receiver] += amount;
        emit Transfer(owner, receiver, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _allowances[_msgSender()][spender] += addedValue;
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _allowances[_msgSender()][spender] -= subtractedValue;
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender]);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (owner == address(0)) revert InvalidAddress(owner);
        if (spender == address(0)) revert InvalidAddress(spender);

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // Error for invalid address
    error InvalidAddress(address addr);

    // Error for invalid amount
    error InvalidAmount(uint256 amount);

    // Function to burn tokens
    function burn(address account, uint256 value) external virtual authorized {
        _burn(account, value);
    }

    // Internal function to burn tokens
    function _burn(address account, uint256 amount) internal virtual {
        if (account == address(0)) revert InvalidAddress(account);

        _beforeTokenTransfer(account, address(0), amount);
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    // Internal function to mint tokens
    function _mint(address account, uint256 amount) internal virtual {
        if (account == address(0)) revert InvalidAddress(account);

        _beforeTokenTransfer(address(0), account, amount);
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    // Hook function to be called before any token transfer
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {
        if (_blacklist[from]) revert BlacklistedAddress(from);
        if (_blacklist[to]) revert BlacklistedAddress(to);
        if (_frozenAccounts[from]) revert FrozenAccount(from);
        if (_frozenAccounts[to]) revert FrozenAccount(to);

        // Minting and burning bypass the max transfer amount check
        if (from != address(0) && to != address(0)) {
            if (amount > _maxTransferAmount) revert TransferAmountExceedsMaxAmount(amount, _maxTransferAmount);
        }
    }

    // Error for blacklisted address
    error BlacklistedAddress(address addr);

    // Error for frozen account
    error FrozenAccount(address addr);

    // Error for transfer amount exceeding max amount
    error TransferAmountExceedsMaxAmount(uint256 amount, uint256 maxAmount);

    // Function to toggle admin status
    function toggleAdmin(address account) external onlyOwner {
        bool val = admins[account];
        admins[account] = !val;
    }

    // Function to pause transfer
    function pause() external onlyOwner {
        _pause();
    }

    // Function to unpause transfer
    function unpause() external onlyOwner {
        _unpause();
    }

    // Function to get token metadata URL
    function tokenMetadataURL() external view returns (string memory) {
        return _tokenMetadataURL;
    }

    // Function to set token metadata URL
    function setTokenMetadataURL(string memory metadataURL) external authorized {
        _tokenMetadataURL = metadataURL;
    }

    // Function to set blacklist status for an account
    function setBlacklist(address account, bool value) external authorized {
        _blacklist[account] = value;
    }

    // Function to set frozen account status
    function setFrozenAccount(address account, bool value) external authorized {
        _frozenAccounts[account] = value;
    }

    // Function to set the maximum transfer amount
    function setMaxTransferAmount(uint256 amount) external authorized {
        _maxTransferAmount = amount;
    }

    // Function to get the distribution details
    function getDistributionDetails() external view returns (Distribution[] memory) {
        return distributions;
    }
}
