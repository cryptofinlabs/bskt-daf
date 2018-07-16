pragma solidity 0.4.24;


import "cryptofin-solidity/contracts/array-utils/UIntArrayUtils.sol";
import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol"; 

import "./IBsktToken.sol";
import "./Math.sol";


contract RebalancingBsktToken is
  DetailedERC20,
  Pausable,
  StandardToken
{

  using AddressArrayUtils for address[];
  using SafeMath for uint256;
  using UIntArrayUtils for uint256[];

  // creation Size? => log min quantities?
  address[] public addresses;
  uint256[] public quantities;

  // === EVENTS ===

  event Create(address indexed creator, uint256 amount);
  event Redeem(address indexed redeemer, uint256 amount, address[] skippedTokens);

  // === MODIFIERS ===

  /// @notice Requires value to be divisible by creationUnit
  /// @param value Number to be checked
  modifier requireMultiple(uint256 value) {
    // TODO: inefficient since creationSize is used later in the functions that use this modifier
    uint256 _creationSize = creationSize();
    require((value % _creationSize) == 0);
    _;
  }

  // === CONSTRUCTOR ===

  constructor(
    address[] _addresses,
    uint256[] _quantities,
    string _name,
    string _symbol
  ) DetailedERC20(_name, _symbol, 18)
    public
  {
    require(_addresses.length > 0);
    require(_addresses.length == _quantities.length);
    addresses = _addresses;
    quantities = _quantities;
  }

  // === EXTERNAL FUNCTIONS ===

  function issue(uint256 amount)
    external
    whenNotPaused()
    requireMultiple(amount)
  {
    require(amount > 0);
    require((totalSupply_ + amount) > totalSupply_);

    uint256 _creationSize = creationSize();
    uint256 tokensLength = addresses.length;
    for (uint256 i = 0; i < tokensLength; i++) {
      ERC20 erc20 = ERC20(addresses[i]);
      uint256 amountTokens = amount.div(_creationSize).mul(quantities[i]);
      require(erc20.transferFrom(msg.sender, address(this), amountTokens));
    }

    mint(msg.sender, amount);
    emit Create(msg.sender, amount);
  }

  function redeem(uint256 amount, address[] tokensToSkip)
    external
    requireMultiple(amount)
  {
    require(amount > 0);
    require(amount <= totalSupply_);
    require(amount <= balances[msg.sender]);
    uint256 tokensLength = addresses.length;
    require(tokensToSkip.length <= tokensLength);

    // Burn before to prevent re-entrancy
    burn(msg.sender, amount);

    uint256 _creationSize = creationSize();
    for (uint256 i = 0; i < tokensLength; i++) {
      address tokenAddress = addresses[i];
      ERC20 erc20 = ERC20(tokenAddress);
      bool isIn = tokensToSkip.contains(tokenAddress);
      if (isIn) {
        continue;
      }
      uint256 amountTokens = amount.div(_creationSize).mul(quantities[i]);
      require(erc20.transfer(msg.sender, amountTokens));
    }
    emit Redeem(msg.sender, amount, tokensToSkip);
  }

  function redeem() public {
  }

  function rebalance() public {
  }

  function creationUnit() view public returns(address[], uint256[]) {
    uint256 numTokens = addresses.length;
    address[] memory _addresses = new address[](numTokens);
    uint256[] memory _quantities = new uint256[](numTokens);
    for(uint256 i = 0; i < numTokens; i += 1) {
      _quantities[i] = quantities[i].div(totalSupply_);
    }
    return (_addresses, _quantities);

  }

  // `map` doesn't work if these are in a library
  function logFloor(uint256 n) public pure returns(uint256) {
    uint256 i = 0;
    while(true) {
      if (n < 10) {
        break;
      }
      n /= 10;
      i += 1;
    }
    return i;
  }

  function min(uint256 a, uint256 b) public pure returns(uint256) {
    if (a < b) {
      return a;
    } else {
      return b;
    }
  }

  // TODO: Make stored and only update on rebalance. Should be cheaper on gas
  function creationSize() view public returns(uint256) {
    uint256 optimal = quantities.map(logFloor).reduce(min);
    return Math.max(uint256(decimals).sub(optimal), 1);
  }

  // @dev Mints new tokens
  // @param to Address to mint to
  // @param amount Amount to mint
  // @return isOk Whether the operation was successful
  function mint(address to, uint256 amount) internal returns (bool) {
      totalSupply_ = totalSupply_.add(amount);
      balances[to] = balances[to].add(amount);
      emit Transfer(address(0), to, amount);
      return true;
  }

  // @dev Burns tokens
  // @param from Address to burn from
  // @param amount Amount to burn
  // @return isOk Whether the operation was successful
  function burn(address from, uint256 amount) internal returns (bool) {
      totalSupply_ = totalSupply_.sub(amount);
      balances[from] = balances[from].sub(amount);
      emit Transfer(from, address(0), amount);
      return true;
  }

}
