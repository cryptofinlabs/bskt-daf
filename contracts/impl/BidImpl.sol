pragma solidity 0.4.24;


import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "cryptofin-solidity/contracts/rationals/Rational.sol";
import "cryptofin-solidity/contracts/rationals/RationalMath.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import "../BsktRegistry.sol";


library BidImpl {

  using AddressArrayUtils for address[];
  using RationalMath for Rational.Rational256;
  using SafeMath for uint256;

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
    address[] memory tokensA,
    int256[] memory quantitiesA,
    address[] memory tokensB,
    int256[] memory quantitiesB,
    address[] memory deltaTokens,
    int256[] memory deltaQuantities
  )
  public
  view
  returns (bool)
  {
    require(tokensA.length == quantitiesA.length);
    require(tokensA.length == tokensB.length);
    require(tokensA.length == quantitiesB.length);

    Rational.Rational256[] memory fillProportionA = new Rational.Rational256[](deltaTokens.length);
    Rational.Rational256[] memory fillProportionB = new Rational.Rational256[](deltaTokens.length);
    for (uint256 i = 0; i < deltaTokens.length; i++) {
      if (deltaQuantities[i] > 0) {
        require(quantitiesA[i] >= 0);
        require(quantitiesB[i] >= 0);
        fillProportionA[i] = Rational.Rational256({ n: uint256(quantitiesA[i]), d: uint256(deltaQuantities[i]) });
        fillProportionB[i] = Rational.Rational256({ n: uint256(quantitiesB[i]), d: uint256(deltaQuantities[i]) });
      } else {
        // If tokens are being sold (negative delta), entry is 100
        // It's assumed bidders act in their own economic interest, so they
        // wouldn't leave any tokens on the table
        // Also anything with deltaQuantity 0 is automatically 100%
        fillProportionA[i] = Rational.Rational256({ n: 100, d: 1 });
        fillProportionB[i] = Rational.Rational256({ n: 100, d: 1 });
        continue;
      }
    }
    return compareSortedRational256s(fillProportionA, fillProportionB);
  }

  // Checks that the bid isn't trying to take more funds than it should
  function acceptableBid(address[] memory _tokens, int256[] memory _quantities, address[] memory _deltaTokens, int256[] memory _deltaQuantities) internal view returns (bool) {
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
  function getRebalanceDeltas(BsktRegistry registry, address[] tokens, uint256 _totalUnits) public view returns (address[] memory, int256[] memory) {
    require(_totalUnits > 0);

    address[] memory registryTokens = registry.getTokens();
    address[] memory targetTokens = registryTokens.union(tokens);
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

  function separatePositiveNegative(address[] memory _tokens, int256[] memory _quantities)
    internal
    pure
    returns (address[] memory, int256[] memory)
  {
    address[] memory _separatedTokens = new address[](_tokens.length);
    int256[] memory _separatedQuantities = new int256[](_tokens.length);
    uint256 startPointer = 0;
    uint256 endPointer = _tokens.length - 1;
    for (uint256 i = 0; i < _tokens.length; i++) {
      if (_quantities[i] > 0) {
        _separatedTokens[startPointer] = _tokens[i];
        _separatedQuantities[startPointer] = _quantities[i];
        startPointer++;
      } else {
        _separatedTokens[endPointer] = _tokens[i];
        _separatedQuantities[endPointer] = _quantities[i];
        endPointer = endPointer.sub(1);
      }
    }
    return (_separatedTokens, _separatedQuantities);
  }

}
