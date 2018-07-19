pragma solidity 0.4.24;


contract IDataRegistry {

  function get(bytes32 _id) public returns(bytes memory);

  function getKeys() public returns(bytes32[] memory);

}
