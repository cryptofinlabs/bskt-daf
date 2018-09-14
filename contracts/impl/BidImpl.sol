pragma solidity 0.4.24;
//pragma experimental ABIEncoderV2;

import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "cryptofin-solidity/contracts/rationals/Rational.sol";
import "cryptofin-solidity/contracts/rationals/RationalMath.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import "../BsktRegistry.sol";
import "../Escrow.sol";
import "../lib/Bid.sol";
import "../lib/ERC20TokenUtils.sol";
import "../lib/dYdX/TokenInteract.sol";
import "../lib/dYdX/TokenProxy.sol";


library BidImpl {

  using AddressArrayUtils for address[];
  using RationalMath for Rational.Rational256;
  using SafeMath for uint256;

  // === EVENTS ===

  event BidAccepted(address bidder, address[] tokens, int256[] bidQuantities, uint256 totalUnits);

  // === FUNCTIONS ===

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

  function bid(
    uint256 numerator,
    uint256 denominator,
    address[] _deltaTokens,
    uint256[] targetQuantities,
    uint256[] currentQuantities,
    uint256 _totalUnits,
    Escrow escrow,
    Bid.Bid storage bestBid
  )
    external
  {
    Rational.Rational256 memory bidPercentage = Rational.Rational256({ n: numerator, d: denominator });
    int256[] memory bidQuantities = computeBidQuantities(numerator, denominator, currentQuantities, targetQuantities);
    if (bestBid.bidder == address(0)) {
      // No previous bid, so accept this one
      bestBid.bidder = msg.sender;
      bestBid.bidPercentage = bidPercentage;
      bestBid.tokens = _deltaTokens;
      bestBid.quantities = bidQuantities;
      escrow.escrowBid(_deltaTokens, msg.sender, bidQuantities, _totalUnits);
      emit BidAccepted(msg.sender, _deltaTokens, bidQuantities, _totalUnits);
    } else {
      bool isBidBetter = bidPercentage.gt(bestBid.bidPercentage);
      if (isBidBetter) {
        escrow.releaseBid(bestBid.tokens, bestBid.bidder, bestBid.quantities, _totalUnits);
        bestBid.bidder = msg.sender;
        bestBid.bidPercentage = bidPercentage;
        // bestBid.tokens aleady set
        bestBid.quantities = bidQuantities;
        escrow.escrowBid(_deltaTokens, msg.sender, bidQuantities, _totalUnits);
        emit BidAccepted(msg.sender, _deltaTokens, bidQuantities, _totalUnits);
      } else {
        // Revert if bid isn't better than bestBid
        revert();
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

  /**
   * Returns array of quantities in specified order
   */
  function getCurrentQuantities(address[] memory _tokens, uint256 _totalUnits)
    public
    view
    returns (uint256[] memory)
  {
    uint256[] memory _currentQuantities = new uint256[](_tokens.length);
    for (uint256 i = 0; i < _tokens.length; i++) {
      _currentQuantities[i] = TokenInteract.balanceOf(_tokens[i], address(this)).div(_totalUnits);
    }
    return _currentQuantities;
  }

  // It should not be possible to falsely report a frozen token
  // If it's possible, it could result in stolen funds
  function reportFrozenToken(address token, address[] memory tokens, address[] storage tokensToSkip, TokenProxy tokenProxy) public {
    (uint256 index, bool isIn) = tokensToSkip.indexOf(token);
    if (ERC20TokenUtils.checkFrozen(token, address(tokenProxy))) {
      // Limit tracking frozen tokens to the creation unit to prevent spam
      bool isInCreationUnit = tokens.contains(token);
      require(isInCreationUnit);
      if (!isIn) {
        tokensToSkip.push(token);
      }
    } else {
      if (isIn) {
        tokensToSkip.sPopCheap(index);
      }
    }
  }

}
