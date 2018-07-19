pragma solidity 0.4.24;
pragma experimental ABIEncoderV2;


import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "cryptofin-solidity/contracts/array-utils/UIntArrayUtils.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

import "./IBsktDataRegistry.sol";


contract BsktRegistry is /* IBsktDataRegistry, */ Ownable {

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
    _;
    assert(tokens.length == quantities.length);
  }

  // TODO: pull out into library contract
  modifier chargeFee() {
    if (readFeeAmount > 0) {
      require(feeToken.transfer(beneficiary, readFeeAmount));
    }
    _;
  }

  // should feeToken be variable?
  function setReadFee(address _token, uint256 _amount) external onlyOwner {
    feeToken = ERC20(_token);
    readFeeAmount = _amount;
  }


  constructor(address _beneficiary, address _feeToken) public {
    beneficiary = _beneficiary;
    feeToken = ERC20(_feeToken);
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

  function remove(address token) public onlyOwner {
    (uint256 index, bool isIn) = tokens.indexOf(token);
    if (!isIn) {
      return;
    }
    tokens.sRemoveIndex(index);
    quantities.sRemoveIndex(index);
  }

  function get(address token) public view returns(uint256) {
    // token interact
    require(feeToken.transfer(beneficiary, readFeeAmount));
    (uint256 index,) = tokens.indexOf(token);
    return index;
  }

  function getTokens() public view returns(address[] memory) {
    return tokens;
  }

  // Careful, O(n^2)
  function getQuantities(address[] memory _tokens) public view returns(uint256[] memory) {
    require(feeToken.transfer(beneficiary, readFeeAmount));
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

  function getAllQuantities() public view returns(uint256[] memory) {
    require(feeToken.transfer(beneficiary, readFeeAmount));
    emit Read(msg.sender, readFeeAmount);
    return quantities;
  }

  // === ONLY OWNER ===

  function withdraw(address _token, uint256 _amount)
    external
    onlyOwner
  {
    require(ERC20(_token).transfer(owner, _amount));
  }

}
