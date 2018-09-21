pragma solidity 0.4.24;


contract IBsktRegistry {

  function get(address token) public returns (uint256);

  function getTokens() public view returns (address[] memory);

  function getQuantities(address[] memory _tokens) public returns (uint256[] memory);

  function getAllQuantities() public returns (uint256[] memory);

}
