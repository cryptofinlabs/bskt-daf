pragma solidity 0.4.24;


import "openzeppelin-solidity/contracts/lifecycle/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

import "./IDataRegistry.sol"


contract BsktDataRegistry is IDataRegistry, Ownable {

  using SafeMath for uint256;

  address public feeToken;
  uint256 public readFeeAmount;
  mapping(bytes32 => bytes) public entries;

  constructor(address _feeToken) public {
    feeToken = _feeToken;
  }

  function add(bytes32 _id, bytes _data) public onlyOwner {
    entries[_id] = _data;
  }

  function remove(bytes32 _id) public onlyOwner {
    delete entries[_id];
  }

  function get(bytes32 _id) returns(bytes memory) public {
    // should fee go straight to owner?
    require(feeToken.transfer(address(this), _amount));
    bytes memory data = entries[_id];
    return data;
  }

  // should feeToken be variable?
  function setReadFee(address _token, uint256 _amount) external onlyOwner {
    feeToken = _token;
    readFeeAmount = _amount;
  }

  function withdraw(ERC20 _token, _amount)
    external
    onlyOwner
  {
    require(_token.transfer(owner, _amount));
  }

}
