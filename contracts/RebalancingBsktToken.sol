pragma solidity 0.4.24;


import "cryptofin-solidity/contracts/array-utils/UIntArrayUtils.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol"; 
import "zeppelin-solidity/contracts/lifecycle/Pausable.sol";

import "./IBsktToken.sol";
import "./Math.sol";


contract RebalancingBsktToken is
  DetailedERC20
  IBsktToken,
  Pausable,
  StandardToken,
{

  using SafeMath for uint256;
  using UIntArrayUtils for uint256[];

  // creation Size? => log min quantities?
  address[] public addresses;
  uint256[] public quantities;

  constructor(
    address[] _addresses,
    uint256[] _quantities,
    string _name,
    string _symbol
  ) DetailedERC20(_name, _symbol, 18)
    public
  {
    addresses = _addresses;
    quantities = _quantities;
  }

  function issue(uint256 amount)
    external
    whenNotPaused()
    requireNonZero(amount)
    requireMultiple(amount)
  {
    // Check overflow
    require((totalSupply_ + amount) > totalSupply_);

    for (uint256 i = 0; i < tokens.length; i++) {
      TokenInfo memory token = tokens[i];
      ERC20 erc20 = ERC20(token.addr);
      uint256 amount = amount.div(creationUnit).mul(token.quantity);
      require(erc20.transferFrom(msg.sender, address(this), amount));
    }

    mint(msg.sender, amount);
    emit Create(msg.sender, amount);
  }

  function redeem(uint256 amount, address[] tokensToSkip)
    external
    requireNonZero(amount)
    requireMultiple(amount)
  {
    require(amount <= totalSupply_);
    require(amount <= balances[msg.sender]);
    require(tokensToSkip.length <= tokens.length);
    // Total supply check not required since a user would have to have
    // balance greater than the total supply

    // Burn before to prevent re-entrancy
    burn(msg.sender, amount);

    for (uint256 i = 0; i < tokens.length; i++) {
      TokenInfo memory token = tokens[i];
      ERC20 erc20 = ERC20(token.addr);
      uint256 index;
      bool ok;
      (index, ok) = tokensToSkip.index(token.addr);
      if (ok) {
        continue;
      }
      uint256 amount = amount.div(creationUnit).mul(token.quantity);
      require(erc20.transfer(msg.sender, amount));
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
