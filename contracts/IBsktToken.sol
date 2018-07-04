pragma solidity 0.4.24;


import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";


contract IBsktToken {

  function issue() public;

  function redeem() public;

}
