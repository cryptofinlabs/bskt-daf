pragma solidity 0.4.24;


contract IBsktDataRegistry {

  function get(address _id) public returns(uint256);

  function getTokens() public returns(address[] memory);

  function getQuantities() public returns(uint256[] memory);

}
