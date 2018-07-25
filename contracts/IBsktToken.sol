pragma solidity 0.4.24;


import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";


contract IBsktToken is ERC20 {

  function issue() external;

  function redeem() external;

}
