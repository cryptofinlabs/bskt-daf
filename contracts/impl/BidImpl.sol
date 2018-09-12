pragma solidity 0.4.24;


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

  event BidAccepted(address bidder, address[] tokens, int256[] deltas, uint256 totalUnits);

  // Assumes fillProportions are sorted
  // Returns true if A is better, false if B is better
  // If equal, favors B
  function compareSortedRational256s(Rational.Rational256[] memory A, Rational.Rational256[] memory B)
    internal
    pure
    returns (bool)
  {
    for (uint256 i = 1; i < A.length; i++) {
      require(A[i - 1].lte(A[i]));
    }
    for (i = 1; i < B.length; i++) {
      require(B[i - 1].lte(B[i]));
    }
    for (i = 0; i < A.length; i++) {
      if (A[i].gt(B[i])) {
        return true;
      } else if (A[i].lt(B[i])) {
        return false;
      } else {
        continue;
      }
    }
    return false;
  }

  // Compares two bids, returning true if the first bid is better, and breaking ties with the second bid
  // How it works:
  // * Maps each bid into an array of percentages representing the percentage of each token filled
  // * Requires that these percentages are sorted in increasing order, and that all positives are first
  //   (getRebalanceDeltas takes care of separating +/-, and the bidder must construct the call such that this requirement is satisfied)
  // * Compares the two percentage arrays by comparing the first element, and iterating
  function compareBids(
    address[] memory tokens,
    int256[] memory quantitiesA,
    int256[] memory quantitiesB,
    int256[] storage deltaQuantities,
    uint256 _totalUnits
  )
    public
    returns (bool)
  {
    Rational.Rational256[] memory fillProportionA = new Rational.Rational256[](tokens.length);
    Rational.Rational256[] memory fillProportionB = new Rational.Rational256[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      if (deltaQuantities[i] > 0) {
        require(quantitiesA[i] >= 0);
        require(quantitiesB[i] >= 0);
        uint256 tokenBalance = TokenInteract.balanceOf(tokens[i], this);
        // Balances this bid would provide
        uint256 targetBalance = tokenBalance.add(uint256(deltaQuantities[i]).mul(_totalUnits));

        fillProportionA[i] = Rational.Rational256({
          n: tokenBalance.add(uint256(quantitiesA[i]).mul(_totalUnits)),
          d: uint256(targetBalance)
        });
        fillProportionB[i] = Rational.Rational256({
          n: tokenBalance.add(uint256(quantitiesB[i]).mul(_totalUnits)),
          d: uint256(targetBalance)
        });
      } else {
        // If tokens are being sold (negative delta), entry is 100
        // It's assumed bidders act in their own economic interest, so they
        // wouldn't leave any tokens on the table
        // Also anything with deltaQuantity 0 is automatically 100%
        fillProportionA[i] = Rational.Rational256({ n: 1, d: 1 });
        fillProportionB[i] = Rational.Rational256({ n: 1, d: 1 });
        continue;
      }
    }
    return compareSortedRational256s(fillProportionA, fillProportionB);
  }

  // Checks that the bid isn't trying to take more funds than it should
  function acceptableBid(address[] memory _tokens, int256[] memory _quantities, address[] memory _deltaTokens, int256[] memory _deltaQuantities) internal pure returns (bool) {
    // todo; use the stored ones instead
    for (uint256 i = 0; i < _deltaTokens.length; i++) {
      if (_tokens[i] != _deltaTokens[i]) {
        return false;
      }
      if (_deltaQuantities[i] < 0 && _quantities[i] < _deltaQuantities[i]) {
        return false;
      }
    }
    return true;
  }

  // naming of target vs all vs registry?
  // TODO: handle invalid data
  // deltas required. + means this contract needs to buy, - means sell
  // costs fees for the fund
  function getRebalanceDeltas(BsktRegistry registry, address[] tokens, uint256 _totalUnits) public returns (address[] memory, int256[] memory) {
    require(_totalUnits > 0);

    address[] memory registryTokens = registry.getTokens();
    address[] memory targetTokens = registryTokens.union(tokens);
    // Charges tokens for reading on-chain
    uint256[] memory targetQuantities = registry.getQuantities(targetTokens);
    uint256 length = targetTokens.length;
    int256[] memory deltas = new int256[](length);
    for (uint256 i = 0; i < length; i++) {
      IERC20 erc20 = IERC20(targetTokens[i]);
      // assert that quantity is >= quantity recorded for that token
      uint256 quantity = erc20.balanceOf(address(this)).div(_totalUnits);
      // TODO: ensure no overflow
      // TODO: add safemath
      deltas[i] = int256(targetQuantities[i]) - (int256(quantity));
    }
    return separatePositiveNegative(targetTokens, deltas);
  }

  function separatePositiveNegative(address[] memory _tokens, int256[] memory _deltas)
    internal
    pure
    returns (address[] memory, int256[] memory)
  {
    address[] memory _separatedTokens = new address[](_tokens.length);
    int256[] memory _separatedDeltas = new int256[](_tokens.length);
    uint256 startPointer = 0;
    uint256 endPointer = _tokens.length - 1;
    for (uint256 i = 0; i < _tokens.length; i++) {
      if (_deltas[i] > 0) {
        _separatedTokens[startPointer] = _tokens[i];
        _separatedDeltas[startPointer] = _deltas[i];
        startPointer++;
      } else {
        _separatedTokens[endPointer] = _tokens[i];
        _separatedDeltas[endPointer] = _deltas[i];
        endPointer = endPointer.sub(1);
      }
    }
    return (_separatedTokens, _separatedDeltas);
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
    address[] _tokens,
    int256[] _quantities,
    Bid.Bid storage bestBid,
    Escrow escrow,
    address[] storage deltaTokens,
    int256[] storage deltaQuantities,
    uint256 _totalUnits
  )
    external
  {
    // First bid
    if (bestBid.bidder == address(0)) {
      require(acceptableBid(_tokens, _quantities, deltaTokens, deltaQuantities));
      bestBid.bidder = msg.sender;
      bestBid.tokens = _tokens;
      bestBid.quantities = _quantities;
      escrow.escrowBid(_tokens, msg.sender, _quantities, _totalUnits);
      emit BidAccepted(msg.sender, _tokens, _quantities, _totalUnits);
      // TODO: still need to check bids to make sure it's not malicious
    } else {
      // TODO: assert that tokens arrays are all same
      require(deltaTokens.isEqual(_tokens));
      require(deltaTokens.isEqual(bestBid.tokens));
      bool isBidBetter = compareBids(
        _tokens,
        _quantities,
        bestBid.quantities,
        deltaQuantities,
        _totalUnits);
      if (isBidBetter) {
        escrow.releaseBid(bestBid.tokens, bestBid.bidder, bestBid.quantities, _totalUnits);
        bestBid.bidder = msg.sender;
        // bestBid.tokens aleady set
        bestBid.quantities = _quantities;
        escrow.escrowBid(_tokens, msg.sender, _quantities, _totalUnits);
        emit BidAccepted(msg.sender, _tokens, _quantities, _totalUnits);
      } else {
        // Revert if bid isn't better than bestBid
        revert();
      }
    }
  }

}
