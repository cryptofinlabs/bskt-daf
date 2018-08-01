pragma solidity 0.4.24;
pragma experimental "v0.5.0";


import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "cryptofin-solidity/contracts/array-utils/UIntArrayUtils.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

import "./IBsktRegistry.sol";


contract BsktRegistry is /* IBsktRegistry, */ Ownable {

  using AddressArrayUtils for address[];
  using SafeMath for uint256;
  using UIntArrayUtils for uint256[];

  address public beneficiary;
  ERC20 public feeToken;
  uint256 public readFeeAmount;
  // Internal to enforce fees
  address[] internal tokens;
  uint256[] internal quantities;

  // === EVENTS ===

  event Read(address from, uint256 feeAmount);

  modifier checkInvariants() {
    require(tokens.length == quantities.length);
    _;
    assert(tokens.length == quantities.length);
  }

  //// TODO: pull out into library contract
  //modifier chargeFee() {
    //if (readFeeAmount > 0) {
      //require(feeToken.transferFrom(msg.sender, beneficiary, readFeeAmount));
    //}
    //_;
  //}

  // === CONSTRUCTOR ===

  constructor(address _beneficiary, address _feeToken, uint256 _amount) public {
    beneficiary = _beneficiary;
    feeToken = ERC20(_feeToken);
    readFeeAmount = _amount;
  }

  // === PUBLIC FUNCTIONS ===

  function batchSet(address[] memory _tokens, uint256[] memory _quantities) public onlyOwner checkInvariants {
    tokens = _tokens;
    quantities = _quantities;
  }

  function set(uint256 index, address token, uint256 quantity) public onlyOwner checkInvariants {
    if (index >= tokens.length) {
      tokens.push(token);
      quantities.push(quantity);
    } else {
      tokens[index] = token;
      quantities[index] = quantity;
    }
  }

  function remove(address token) public onlyOwner returns (bool) {
    (uint256 index, bool isIn) = tokens.indexOf(token);
    if (!isIn) {
      return false;
    } else {
      tokens.sRemoveIndex(index);
      quantities.sRemoveIndex(index);
      return true;
    }
  }

  function get(address token) public returns (uint256) {
    // token interact
    require(feeToken.transferFrom(msg.sender, beneficiary, readFeeAmount), "fee could not be collected");
    (uint256 index, bool isIn) = tokens.indexOf(token);
    if (!isIn) {
      return 0;
    } else {
      return quantities[index];
    }
  }

  // Careful, O(n^2)
  function getQuantities(address[] memory _tokens) public returns (uint256[] memory) {
    require(feeToken.transferFrom(msg.sender, beneficiary, readFeeAmount), "fee could not be collected");
    uint256 length = _tokens.length;
    uint256[] memory _quantities = new uint256[](length);
    for (uint256 i = 0; i < length; i++) {
      (uint256 index, bool isIn) = tokens.indexOf(_tokens[i]);
      if (isIn) {
        _quantities[i] = quantities[index];
      } else {
        _quantities[i] = 0;  // Assume anything not in registry is 0
      }
    }
    emit Read(msg.sender, readFeeAmount);
    return _quantities;
  }

  function getAllQuantities() public returns (uint256[] memory) {
    // token interact, require this
    require(feeToken.transferFrom(msg.sender, beneficiary, readFeeAmount));
    emit Read(msg.sender, readFeeAmount);
    return quantities;
  }

  // === VIEW FUNCTIONS ===

  function getTokens() public view returns (address[] memory) {
    return tokens;
  }

  // === ONLY OWNER ===

  function withdrawTokens(address _token, uint256 _amount)
    external
    onlyOwner
  {
    require(ERC20(_token).transfer(owner, _amount));
  }

}