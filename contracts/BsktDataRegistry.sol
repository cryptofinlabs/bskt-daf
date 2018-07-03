pragma solidity 0.4.24;


import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

import "./IDataRegistry.sol";


contract BsktDataRegistry is IDataRegistry, Ownable {

  using SafeMath for uint256;

  ERC20 public feeToken;
  uint256 public readFeeAmount;
  mapping(bytes32 => bytes) public entries;

  constructor(address _feeToken) public {
    feeToken = ERC20(_feeToken);
  }

  function add(bytes32 _id, bytes _data) public onlyOwner {
    entries[_id] = _data;
  }

  function remove(bytes32 _id) public onlyOwner {
    delete entries[_id];
  }

  function get(bytes32 _id) public returns(bytes memory) {
    // should fee go straight to owner?
    require(feeToken.transfer(address(this), readFeeAmount));
    bytes memory data = entries[_id];
    return data;
  }

  // should feeToken be variable?
  function setReadFee(address _token, uint256 _amount) external onlyOwner {
    feeToken = ERC20(_token);
    readFeeAmount = _amount;
  }

  function withdraw(address _token, uint256 _amount)
    external
    onlyOwner
  {
    require(ERC20(_token).transfer(owner, _amount));
  }

}
