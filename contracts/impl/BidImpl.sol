pragma solidity 0.4.24;
//pragma experimental ABIEncoderV2;

import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "cryptofin-solidity/contracts/rationals/Rational.sol";
import "cryptofin-solidity/contracts/rationals/RationalMath.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import "../BsktRegistry.sol";
import "../Escrow.sol";
import "../lib/dYdX/TokenInteract.sol";
import "../lib/Bid.sol";


library BidImpl {

  using AddressArrayUtils for address[];
  using RationalMath for Rational.Rational256;
  using SafeMath for uint256;

  // naming of target vs all vs registry?
  // TODO: handle invalid data
  // deltas required. + means this contract needs to buy, - means sell
  // costs fees for the fund
  function getProposedCreationUnit(BsktRegistry registry, address[] tokens)
    public
    returns (address[] memory, uint256[] memory)
  {
    address[] memory registryTokens = registry.getTokens();
    address[] memory targetTokens = registryTokens.union(tokens);
    // Charges tokens for reading on-chain
    uint256[] memory targetQuantities = registry.getQuantities(targetTokens);
    return (targetTokens, targetQuantities);
  }

  // Transfers tokens from escrow to fund and fund to bidder
  function settleBid(Bid.Bid memory _bestBid, Escrow escrow, uint256 _totalUnits) internal {
    escrow.releaseBid(_bestBid.tokens, address(this), _bestBid.quantities, _totalUnits);
    for (uint256 i = 0; i < _bestBid.tokens.length; i++) {
      if (_bestBid.quantities[i] < 0) {
        uint256 amount = uint256(-_bestBid.quantities[i]).mul(_totalUnits);
        TokenInteract.transfer(_bestBid.tokens[i], _bestBid.bidder, amount);
      }
    }
  }

  function computeBidQuantities(
    uint256 numerator,
    uint256 denominator,
    uint256[] currentQuantities,
    uint256[] targetQuantities
  )
    public
    pure
    returns (int256[] memory)
  {
    Rational.Rational256 memory bidPercentage = Rational.Rational256({ n: numerator, d: denominator });
    int256[] memory bidQuantities = new int256[](targetQuantities.length);
    for (uint256 i = 0; i < targetQuantities.length; i++) {
      uint256 resultQuantity = bidPercentage.scalarMul(targetQuantities[i]);
      // Ensure no overflow
      bidQuantities[i] = int256(resultQuantity) - int256(currentQuantities[i]);
    }
    return bidQuantities;
  }

}
