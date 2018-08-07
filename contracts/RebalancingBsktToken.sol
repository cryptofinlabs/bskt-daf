pragma solidity 0.4.24;
//pragma experimental ABIEncoderV2;


import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "cryptofin-solidity/contracts/array-utils/UIntArrayUtils.sol";
import "cryptofin-solidity/contracts/rationals/Rational.sol";
import "cryptofin-solidity/contracts/rationals/RationalMath.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol"; 

import "./BsktRegistry.sol";
import "./Escrow.sol";
import "./IBsktToken.sol";
//import "./Math.sol";


contract RebalancingBsktToken is
  DetailedERC20,
  StandardToken
{

  using AddressArrayUtils for address[];
  using RationalMath for Rational.Rational256;
  using SafeMath for uint256;
  using UIntArrayUtils for uint256[];

  struct Bid {
    address bidder;
    address[] tokens;
    int256[] quantities;
  }

  // these need better names
  enum Status {
    OPT_OUT,  // After snapshotting the delta, give investors some time to opt-out if they don't agree with the rebalance. I want a better name though
    AUCTIONS_OPEN,  // Bids being accepted
    // Rebalance
    OPEN
  }

  enum FN {
    COMMIT_DELTA,
    ISSUE,
    REDEEM,
    BID,
    REBALANCE
  }

  address[] public tokens;
  uint256[] public quantities;  // is this needed? Could read balances from token contracts directly, though a potential risk
  uint256 public creationSize;

  // Snapshot of the delta of tokens needed to rebalance
  // These are set by commitDelta
  address[] public deltaTokens;
  int256[] public deltaQuantities;

  BsktRegistry public registry;
  Escrow public escrow;
  Status public status;

  uint256 public xInterval;
  uint256 public xOffset;
  uint256 public auctionOffset;
  uint256 public auctionDuration;
  uint256 public optOutDuration;
  uint256 public rebalanceDuration;

  Bid public bestBid;

  // === EVENTS ===

  event Issue(address indexed creator, uint256 amount);
  event Redeem(address indexed redeemer, uint256 amount, address[] skippedTokens);
  event Rebalance(address caller);
  event BidAccepted(address bidder, address[] tokens, int256[] deltas, uint256 totalUnits);
  event CommitDelta(address[] tokens, int256[] deltas);

  // === MODIFIERS ===

  modifier requireSortedRational256(Rational.Rational256[] memory A) {
    for (uint256 i = 1; i < A.length; i++) {
      require(A[i - 1].lte(A[i]));
    }
    _;
  }

  // intervals should always satisfy range [)
  modifier onlyDuringValidInterval(FN fn) {
    checkValidInterval(fn);
    _;
  }

  // add error messages
  // also handles status transitions
  function checkValidInterval(FN fn) internal {
    uint256 xIntervalStart = now.div(xInterval).mul(xInterval).add(xOffset);

    uint256 optOutIntervalStart = now;
    uint256 optOutIntervalEnd = now.add(optOutDuration);

    uint256 auctionIntervalStart = xIntervalStart.add(auctionOffset);
    uint256 auctionIntervalEnd = auctionIntervalStart.add(auctionDuration);

    uint256 rebalanceIntervalStart = auctionIntervalEnd;
    uint256 rebalanceIntervalEnd = rebalanceIntervalStart.add(rebalanceDuration);

    uint256 openIntervalStart = rebalanceIntervalEnd;
    //uint256 openIntervalEnd = now.div(xInterval).add(1).mul(xInterval).add(xOffset);

    if (fn == FN.COMMIT_DELTA) {
      require(status == Status.OPEN || status == Status.OPT_OUT, "Error: Invalid status");
      require(optOutIntervalEnd <= auctionIntervalStart);
      if (status == Status.OPEN) {
        status = Status.OPT_OUT;
      }
    } else if (fn == FN.ISSUE || fn == FN.REDEEM) {
      require(status == Status.OPT_OUT, "Error: Invalid status");
      require(optOutIntervalStart <= now && now < optOutIntervalEnd || openIntervalStart <= now, "Error: not within opt out period");
    } else if (fn == FN.BID) {
      // The first bid will transition status from opt out to auction
      require(status == Status.OPT_OUT || status == Status.AUCTIONS_OPEN, "Error: Invalid status");
      require(auctionIntervalStart <= now && now < auctionIntervalEnd, "Error; not within opt out period");
      if (status == Status.OPT_OUT && auctionIntervalStart <= now) {
        status = Status.AUCTIONS_OPEN;
      }
    } else if (fn == FN.REBALANCE) {
      // require(status == Status.AUCTIONS_OPEN);
      // If no bids were made, so the status never transitioned from OPT_OUT to
      // AUCTIONS_OPEN, then bestBid.bidder is 0, which will trigger a require later
      require(rebalanceIntervalStart <= now && now < rebalanceIntervalEnd, "Error: not within rebalancing period");
      status = Status.OPEN;
    } else {
      revert("Error: Period not recognized");
    }
  }

  // === CONSTRUCTOR ===

  constructor(
    // should we remove these in favour of just specifying registry and setting to that initially?
    // read from registry here
    // what to do about fees initially?
    address[] _tokens,
    uint256[] _quantities,
    uint256 _creationSize,
    address _registry,
    uint256 _xInterval,
    uint256 _xOffset,
    uint256 _auctionOffset,
    uint256 _auctionDuration,
    uint256 _optOutDuration,
    uint256 _rebalanceDuration,
    string _name,
    string _symbol
  ) DetailedERC20(_name, _symbol, 18)
    public
  {
    // If the creation unit is empty, users will be able to issue unlimited tokens
    require(_tokens.length > 0);  // Will need this to prevent attack - can mint infinite tokens
    require(_tokens.length == _quantities.length);
    require(_optOutDuration < _auctionOffset);
    require(_auctionOffset.add(_auctionDuration).add(_rebalanceDuration) <= _xInterval);
    tokens = _tokens;
    quantities = _quantities;
    creationSize = _creationSize;
    registry = BsktRegistry(_registry);

    escrow = new Escrow(address(this));

    xInterval = _xInterval;
    xOffset = _xOffset;
    auctionOffset = _auctionOffset;
    auctionDuration = _auctionDuration;
    optOutDuration = _optOutDuration;
    rebalanceDuration = _rebalanceDuration;

    ERC20 feeToken = registry.feeToken();
    feeToken.approve(registry, MAX_UINT256());

    status = Status.OPT_OUT;
  }

  // === EXTERNAL FUNCTIONS ===

  function issue(uint256 amount)
    external
    onlyDuringValidInterval(FN.ISSUE)
  {
    require(amount > 0);
    require((totalSupply_ + amount) > totalSupply_);
    uint256 _creationSize = creationSize;
    require((amount % _creationSize) == 0);

    uint256 tokensLength = tokens.length;
    for (uint256 i = 0; i < tokensLength; i++) {
      ERC20 erc20 = ERC20(tokens[i]);
      uint256 amountTokens = amount.div(_creationSize).mul(quantities[i]);
      require(erc20.transferFrom(msg.sender, address(this), amountTokens));
    }

    mint(msg.sender, amount);
    emit Issue(msg.sender, amount);
  }

  function redeem(uint256 amount, address[] tokensToSkip)
    external
    onlyDuringValidInterval(FN.REDEEM)
  {
    require(amount > 0);
    require(amount <= totalSupply_);
    require(amount <= balances[msg.sender]);
    uint256 _creationSize = creationSize;
    require((amount % _creationSize) == 0);
    uint256 tokensLength = tokens.length;
    require(tokensToSkip.length <= tokensLength);

    // Burn before to prevent re-entrancy
    burn(msg.sender, amount);

    for (uint256 i = 0; i < tokensLength; i++) {
      address tokenAddress = tokens[i];
      ERC20 erc20 = ERC20(tokenAddress);
      bool isIn = tokensToSkip.contains(tokenAddress);
      if (isIn) {
        continue;
      }
      uint256 amountTokens = amount.div(_creationSize).mul(quantities[i]);
      require(erc20.transfer(msg.sender, amountTokens));
    }
    emit Redeem(msg.sender, amount, tokensToSkip);
  }

  // Transfers tokens from escrow to fund and fund to bidder
  function settleBid() internal {
    Bid memory _bestBid = bestBid;
    uint256 _totalUnits = totalUnits();
    escrow.releaseBid(_bestBid.tokens, address(this), _bestBid.quantities, _totalUnits);
    for (uint256 i = 0; i < _bestBid.tokens.length; i++) {
      if (_bestBid.quantities[i] < 0) {
        uint256 amount = uint256(-_bestBid.quantities[i]).mul(_totalUnits);
        ERC20(_bestBid.tokens[i]).transfer(bestBid.bidder, amount);
      }
    }
  }

  // Updates creation unit tokens and quantities
  // List of tokens in bestBid should be the union of tokens in registry and fund
  // TODO need to prune tokens with balance 0
  function updateBalances() internal {
    Bid memory _bestBid = bestBid;
    uint256[] memory updatedQuantities = new uint256[](_bestBid.tokens.length);
    for (uint256 i = 0; i < _bestBid.tokens.length; i++) {
      ERC20 erc20 = ERC20(_bestBid.tokens[i]);
      // Must query balance to deal with airdrops
      updatedQuantities[i] = erc20.balanceOf(address(this));
    }
    uint256 _totalUnits = totalUnits();
    for (i = 0; i < _bestBid.tokens.length; i++) {
      updatedQuantities[i] = updatedQuantities[i].div(_totalUnits);
    }
    tokens = _bestBid.tokens;
    quantities = updatedQuantities;
  }

  //// handles AUM fee
  //function payFees() internal {
    //// rebalancingFeePct  // should read from registry
    //uint256 length = tokens.length;
    //for (uint256 i = 0; i < length; i++) {
      //uint256 amount = quantities[i] * rebalancingFeePct;  // use Rational
      //ERC20(tokens[i]).transfer(registry.beneficiary(), amount);
      //// update balances again
      //quantities[i] = quantities[i].sub(amount);
    //}
  //}

  // Settles the best bid and updates creation unit
  // ADDON: maybe add some options to not rebalance if bestBid is atrocious (< threshold%)
  // Anyone can call this
  function rebalance()
    external
    onlyDuringValidInterval(FN.REBALANCE)
  {
    Bid memory _bestBid = bestBid;
    require(_bestBid.bidder != address(0));
    settleBid();
    updateBalances();
    // set some didRebalance flag
    delete bestBid;
    emit Rebalance(msg.sender);
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
    int256[] memory quantitiesB
  )
  public
  returns (bool)
  {
    require(tokensA.length == quantitiesA.length);
    require(tokensA.length == tokensB.length);
    require(tokensA.length == quantitiesB.length);

    address[] memory _deltaTokens = deltaTokens;
    int256[] memory _deltaQuantities = deltaQuantities;
    Rational.Rational256[] memory fillProportionA = new Rational.Rational256[](_deltaTokens.length);
    Rational.Rational256[] memory fillProportionB = new Rational.Rational256[](_deltaTokens.length);
    for (uint256 i = 0; i < _deltaTokens.length; i++) {
      if (_deltaQuantities[i] > 0) {
        require(quantitiesA[i] >= 0);
        require(quantitiesB[i] >= 0);
        fillProportionA[i] = Rational.Rational256({ n: uint256(quantitiesA[i]), d: uint256(_deltaQuantities[i]) });
        fillProportionB[i] = Rational.Rational256({ n: uint256(quantitiesB[i]), d: uint256(_deltaQuantities[i]) });
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

  //function getBidFillProportion(
    //address[] bidTokens,
    //int256[] bidQuantities,
    //address[] deltaTokens,
    //int256[] deltaQuantities
  //)
    //external
    //pure
    //returns (Rational.Rational256[] memory)
  //{
    //Rational.Rational256[] memory fillProportion = new Rational.Rational256[](deltaTokens.length);
    //for (uint256 i = 0; i < deltaTokens.length; i++) {
      //// TODO: consider negative deltas!
      //if (deltaQuantities[i] > 0) {
        //require(bidQuantities[i] >= 0);
        //fillProportion[i] = Rational.Rational256({ n: uint256(bidQuantities[i]), d: uint256(deltaQuantities[i]) });
       //} else {
         //continue;  // Entry will be 0
       //}
    //}
  //}

  // Assumes fillProportions are sorted
  // Returns true if A is better, false if B is better
  // If equal, favors B
  function compareSortedRational256s(Rational.Rational256[] memory A, Rational.Rational256[] memory B)
    internal
    requireSortedRational256(A)
    requireSortedRational256(B)
    returns (bool)
  {
    for (uint256 i = 0; i < A.length; i++) {
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


  // Checks that the bid isn't trying to take more funds than it should
  function acceptableBid(address[] _tokens, int256[] _quantities) internal view returns (bool) {
    // todo; use the stored ones instead
    address[] memory _deltaTokens = deltaTokens;
    int256[] memory _deltaQuantities = deltaQuantities;
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

  function bid(address[] _tokens, int256[] _quantities)
    external
    onlyDuringValidInterval(FN.BID)
  {
    Bid memory _bestBid = bestBid;
    // First bid
    if (_bestBid.bidder == address(0)) {
      require(acceptableBid(_tokens, _quantities));
      bestBid = Bid({
        bidder: msg.sender,
        tokens: _tokens,
        quantities: _quantities
      });
      uint256 _totalUnits = totalUnits();
      escrow.escrowBid(_tokens, msg.sender, _quantities, _totalUnits);
      emit BidAccepted(msg.sender, _tokens, _quantities, _totalUnits);
      // TODO: still need to check bids to make sure it's not malicious
    } else {
      if (compareBids(_tokens, _quantities, _bestBid.tokens, _bestBid.quantities)) {
        escrow.releaseBid(_bestBid.tokens, _bestBid.bidder, _bestBid.quantities, _totalUnits);
        bestBid = Bid({
          bidder: msg.sender,
          tokens: _tokens,
          quantities: _quantities
        });
        escrow.escrowBid(_tokens, msg.sender, _quantities, _totalUnits);
        emit BidAccepted(msg.sender, _tokens, _quantities, _totalUnits);
      } else {
        // Revert if bid isn't better than bestBid
        revert();
      }
    }
  }

  // TODO: how to deal with no rebalance called, or something

  // commitDelta can be called multiple times, as long as there's enough time left
  // snapshot the registry
  function commitDelta()
    public
    onlyDuringValidInterval(FN.COMMIT_DELTA)
  {
    (deltaTokens, deltaQuantities) = getRebalanceDeltas();
    emit CommitDelta(deltaTokens, deltaQuantities);
  }

  function separatePositiveNegative(address[] memory _tokens, int256[] memory _quantities)
   internal
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

  // naming of target vs all vs registry?
  // TODO: handle invalid data
  // deltas required. + means this contract needs to buy, - means sell
  // costs fees for the fund
  function getRebalanceDeltas() public returns (address[] memory, int256[] memory) {
    uint256 _totalUnits = totalUnits();
    require(_totalUnits > 0);

    address[] memory registryTokens = registry.getTokens();
    address[] memory targetTokens = registryTokens.union(tokens);
    uint256[] memory targetQuantities = registry.getQuantities(targetTokens);
    uint256 length = targetTokens.length;
    int256[] memory deltas = new int256[](length);
    for (uint256 i = 0; i < length; i++) {
      ERC20 erc20 = ERC20(targetTokens[i]);
      // assert that quantity is >= quantity recorded for that token
      uint256 quantity = erc20.balanceOf(address(this)).div(_totalUnits);
      // TODO: ensure no overflow
      // TODO: add safemath
      deltas[i] = int256(targetQuantities[i]) - (int256(quantity));
    }
    return separatePositiveNegative(targetTokens, deltas);
  }

  function creationUnit() public view returns (address[] memory, uint256[] memory) {
    return (tokens, quantities);
  }

  function totalUnits() public view returns (uint256) {
    return totalSupply_.div(creationSize);
  }

  // @dev Mints new tokens
  // @param to Address to mint to
  // @param amount Amount to mint
  // @return isOk Whether the operation was successful
  function mint(address to, uint256 amount) internal returns (bool) {
    totalSupply_ = totalSupply_.add(amount);
    balances[to] = balances[to].add(amount);
    emit Transfer(address(0), to, amount);
    return true;
  }

  // @dev Burns tokens
  // @param from Address to burn from
  // @param amount Amount to burn
  // @return isOk Whether the operation was successful
  function burn(address from, uint256 amount) internal returns (bool) {
    totalSupply_ = totalSupply_.sub(amount);
    balances[from] = balances[from].sub(amount);
    emit Transfer(from, address(0), amount);
    return true;
  }

  function getTokens() external view returns (address[] memory) {
    return tokens;
  }

  function getQuantities() external view returns (uint256[] memory) {
    return quantities;
  }

  function getDeltaTokens() external view returns (address[] memory) {
    return deltaTokens;
  }

  function getDeltaQuantities() external view returns (int256[] memory) {
    return deltaQuantities;
  }

  // === MATH ===

  // TODO: use the one from library once a fix to solidity-coverage linking issue is found
  function MAX_UINT256() internal pure returns (uint256) {
    return 2 ** 256 - 1;
  }

}
