
pragma solidity 0.4.24;


import "./IBsktToken.sol";


contract IRebalancingBsktToken is IBsktToken {

  function rebalance() external;

}
