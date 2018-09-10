pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

import "./OnlyCore.sol";
import "./lib/dYdX/TokenProxy.sol";


contract Escrow is OnlyCore {

  using SafeMath for uint256;

  TokenProxy tokenProxy;

  // === EVENTS ===

  // would be nice to log actual amounts, but not sure if worth the computation on-chain
  event EscrowBid(address[] tokens, address to, uint256[] amounts);
  event ReleaseBid(address[] tokens, address to, uint256[] amounts);

  constructor(address core) OnlyCore(core) public {
  }

  function setTokenProxy(address tokenProxyAddress)
    public
    onlyCore
  {
    tokenProxy = TokenProxy(tokenProxyAddress);
  }

  // TODO: consider negative deltas! make uint256
  // only transfer if > 0

  function escrowBid(
    address[] memory tokens,
    address from,
    int256[] memory quantities,
    uint256 totalUnits
  )
    public
    onlyCore
  {
    // TODO: use token interact which asserts that delta is exactly amount
    uint256[] memory amounts = new uint256[](tokens.length);  // For log
    for (uint256 i = 0; i < tokens.length; i++) {
      if (quantities[i] > 0) {
        uint256 amount = uint256(quantities[i]).mul(totalUnits);
        tokenProxy.transferTokens(tokens[i], from, address(this), amount);
        amounts[i] = amount;
      }
    }
    emit EscrowBid(tokens, from, amounts);
  }

  function releaseBid(
    address[] memory tokens,
    address to,
    int256[] memory quantities,
    uint256 totalUnits
  )
    public
    onlyCore
  {
    // maybe refactor into shim that constructs amounts and internal function with simpler interface
    uint256[] memory amounts = new uint256[](tokens.length);  // For log
    for (uint256 i = 0; i < tokens.length; i++) {
      if (quantities[i] > 0) {
        uint256 amount = uint256(quantities[i]).mul(totalUnits);
        // TODO: tokenInteract
        ERC20(tokens[i]).transfer(to, amount);
        amounts[i] = amount;
      }
    }
    emit ReleaseBid(tokens, to, amounts);
  }

}
