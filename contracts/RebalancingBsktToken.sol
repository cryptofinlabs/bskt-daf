pragma solidity 0.4.24;


import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol"; 
import "cryptofin-solidity/contracts/array-utils/UIntArrayUtils.sol";

import "./IBsktToken.sol";
import "./Math.sol";


contract RebalancingBsktToken is IBsktToken, StandardToken, DetailedERC20 {

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

  function issue() public {
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

}
