pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./OnlyCore.sol";
import "./lib/dYdX/TokenProxy.sol";
import "./lib/dYdX/TokenInteract.sol";


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

  /**
   * Escrows quantities specified by bid. Only callable by the fund contract.
   * @param tokens Addresses of tokens
   * @param from Bidder address to transfer from
   * @param quantities Quantities for one creation unit
   * @param totalUnits Total number of creation units
   */
  function escrowBid(
    address[] memory tokens,
    address from,
    int256[] memory quantities,
    uint256 totalUnits
  )
    public
    onlyCore
  {
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

  /**
   * Releases escrowed tokens. Only callable by fund.
   * @param tokens Addresses of tokens
   * @param to Bidder address to transfer to
   * @param quantities Quantities for one creation unit
   * @param totalUnits Total number of creation units
   */
  function releaseBid(
    address[] memory tokens,
    address to,
    int256[] memory quantities,
    uint256 totalUnits
  )
    public
    onlyCore
  {
    uint256[] memory amounts = new uint256[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      if (quantities[i] > 0) {
        uint256 amount = uint256(quantities[i]).mul(totalUnits);
        TokenInteract.transfer(tokens[i], to, amount);
        amounts[i] = amount;
      }
    }
    emit ReleaseBid(tokens, to, amounts);
  }

}
