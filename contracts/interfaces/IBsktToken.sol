pragma solidity 0.4.24;


import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


contract IBsktToken is IERC20 {

  function issue(uint256 amount) external;

  function redeem(uint256 amount, address[] tokensToSkipOverride) external;

}
