pragma solidity 0.4.24;


contract IDataRegistry {

  function add(bytes32 _id, bytes _data) public;

  function remove(bytes32 _id) public;

  function get(bytes32 _id) public returns(bytes memory);

}
