pragma solidity 0.4.24;


import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


contract IBsktToken is IERC20 {

  function issue() external;

  function redeem() external;

}
