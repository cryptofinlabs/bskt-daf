import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

import "./OnlyCore.sol";


contract Escrow is OnlyCore {

  constructor(address core) OnlyCore(core) public {
  }

  // TODO: consider negative deltas! make uint256
  // only transfer if > 0

  function escrowBid(address[] memory tokens, address from, uint256[] memory quantities) public onlyCore {
    // TODO: use token interact which asserts that delta is exactly amount
    for (uint256 i = 0; i < tokens.length; i++) {
      ERC20(tokens[i]).transferFrom(from, address(this), quantities[i]);
    }
  }

  function releaseBid(address[] memory tokens, address to, uint256[] memory quantities) public onlyCore {
    for (uint256 i = 0; i < tokens.length; i++) {
      ERC20(tokens[i]).transferFrom(address(this), to, quantities[i]);
    }
  }

}
