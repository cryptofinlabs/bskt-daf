pragma solidity 0.4.24;


import "truffle/Assert.sol";

import "../contracts/Math.sol";


contract TestMath {

  function testLogFloor() public {
    uint256 log10 = Math.logFloor(10);
    uint256 log100 = Math.logFloor(100);
    uint256 log1000 = Math.logFloor(1000);
    uint256 log10000 = Math.logFloor(10000);
    Assert.equal(log10, 1, "should be equal");
    Assert.equal(log100, 2, "should be equal");
    Assert.equal(log1000, 3, "should be equal");
    Assert.equal(log10000, 4, "should be equal");
  }

}
