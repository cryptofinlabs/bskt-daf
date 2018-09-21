pragma solidity 0.4.24;


contract OnlyCore {

  address public CORE;

  constructor(address core) public {
    CORE = core;
  }

  modifier onlyCore() {
    require(msg.sender == CORE, "Only Core can call");
    _;
  }

}
