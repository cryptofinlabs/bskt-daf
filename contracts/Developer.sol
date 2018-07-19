pragma solidity ^0.4.24;

// Allows for beta features
// Better name: _-able
// Maybe can just use RBAC?
// but that has some overhead? would be nice to have thsi
contract Developer {

  address public developer;

  constructor() public {
    developer = msg.sender;
  }

  /**
   * @dev Throws if called by any account other than the developer.
   */
  modifier onlyDeveloper() {
    require(msg.sender == developer);
    _;
  }

}
