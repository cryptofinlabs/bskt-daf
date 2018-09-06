pragma solidity 0.4.24;
//pragma experimental ABIEncoderV2;


import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "cryptofin-solidity/contracts/array-utils/UIntArrayUtils.sol";
import "cryptofin-solidity/contracts/rationals/Rational.sol";
import "cryptofin-solidity/contracts/token-utils/ERC20TokenUtils.sol";
import "cryptofin-solidity/contracts/rationals/RationalMath.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

import "./BsktRegistry.sol";
import "./Escrow.sol";
import "./IBsktToken.sol";
import "./impl/BidImpl.sol";
import "./Math.sol";


contract RebalancingBsktToken is
  ERC20Detailed,
  ERC20
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
  address[] public tokensToSkip;

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
       require(status == Status.AUCTIONS_OPEN);
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
  ) ERC20Detailed (_name, _symbol, 18)
    public
  {
    // If the creation unit is empty, users will be able to issue unlimited tokens
    require(_tokens.length > 0);  // Will need this to prevent attack - can mint infinite tokens
    require(_tokens.length == _quantities.length);
    require(_optOutDuration < _auctionOffset);
    require(_auctionOffset.add(_auctionDuration).add(_rebalanceDuration) <= _xInterval);

    // require not all zero

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

    IERC20 feeToken = registry.feeToken();
    feeToken.approve(registry, MAX_UINT256());

    status = Status.OPT_OUT;
  }

  // === EXTERNAL FUNCTIONS ===

  function issue(uint256 amount)
    external
    onlyDuringValidInterval(FN.ISSUE)
  {
    require(amount > 0);
    require((totalSupply() + amount) > totalSupply());
    uint256 _creationSize = creationSize;
    require((amount % _creationSize) == 0);

    uint256 tokensLength = tokens.length;
    for (uint256 i = 0; i < tokensLength; i++) {
      address tokenAddress = tokens[i];
      IERC20 erc20 = IERC20(tokenAddress);
      bool isIn = tokensToSkip.contains(tokenAddress);
      if (isIn) {
        continue;
      }
      uint256 amountTokens = amount.div(_creationSize).mul(quantities[i]);
      require(erc20.transferFrom(msg.sender, address(this), amountTokens));
    }

    _mint(msg.sender, amount);
    emit Issue(msg.sender, amount);
  }

  function redeem(uint256 amount, address[] tokensToSkipOverride)
    external
    onlyDuringValidInterval(FN.REDEEM)
  {
    require(amount > 0);
    require(amount <= totalSupply());
    require(amount <= balanceOf(msg.sender));
    uint256 _creationSize = creationSize;
    require((amount % _creationSize) == 0);
    uint256 tokensLength = tokens.length;
    require(tokensToSkipOverride.length <= tokensLength);

    address[] memory _tokensToSkip;
    // Use override if it's non-empty
    if (tokensToSkipOverride.length != 0) {
      _tokensToSkip = tokensToSkipOverride;
    } else {
      _tokensToSkip = tokensToSkip;
    }

    // Burn before to prevent re-entrancy
    _burn(msg.sender, amount);

    for (uint256 i = 0; i < tokensLength; i++) {
      address tokenAddress = tokens[i];
      IERC20 erc20 = IERC20(tokenAddress);
      bool isIn = _tokensToSkip.contains(tokenAddress);
      if (isIn) {
        continue;
      }
      uint256 amountTokens = amount.div(_creationSize).mul(quantities[i]);
      require(erc20.transfer(msg.sender, amountTokens));
    }
    emit Redeem(msg.sender, amount, _tokensToSkip);
  }

  // Transfers tokens from escrow to fund and fund to bidder
  function settleBid() internal {
    Bid memory _bestBid = bestBid;
    uint256 _totalUnits = totalUnits();
    escrow.releaseBid(_bestBid.tokens, address(this), _bestBid.quantities, _totalUnits);
    for (uint256 i = 0; i < _bestBid.tokens.length; i++) {
      if (_bestBid.quantities[i] < 0) {
        uint256 amount = uint256(-_bestBid.quantities[i]).mul(_totalUnits);
        IERC20(_bestBid.tokens[i]).transfer(bestBid.bidder, amount);
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
      IERC20 erc20 = IERC20(_bestBid.tokens[i]);
      // Must query balance to deal with airdrops
      updatedQuantities[i] = erc20.balanceOf(address(this));
    }
    uint256 _totalUnits = totalUnits();
    for (i = 0; i < _bestBid.tokens.length; i++) {
      updatedQuantities[i] = updatedQuantities[i].div(_totalUnits);
    }

    // Filter out tokens with quantity 0
    uint256[] memory indexArray = updatedQuantities.argFilter(isNonZero);
    if (indexArray.length != _bestBid.tokens.length) {
      tokens = _bestBid.tokens.argGet(indexArray);
      quantities = updatedQuantities.argGet(indexArray);
    } else {
      tokens = _bestBid.tokens;
      quantities = updatedQuantities;
    }
  }

  //// handles AUM fee
  //function payFees() internal {
    //// rebalancingFeePct  // should read from registry
    //uint256 length = tokens.length;
    //for (uint256 i = 0; i < length; i++) {
      //uint256 amount = quantities[i] * rebalancingFeePct;  // use Rational
      //IERC20(tokens[i]).transfer(registry.beneficiary(), amount);
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
    // commented out for out of gas error 770429428644264
    // same functionality is being provided by checkValidInterval
    //Bid memory _bestBid = bestBid;
    //require(_bestBid.bidder != address(0));
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
  view
  returns (bool)
  {
    return BidImpl.compareBids(
      tokensA,
      quantitiesA,
      tokensB,
      quantitiesB,
      deltaTokens,
      deltaQuantities
    );
  }

  function bid(address[] _tokens, int256[] _quantities)
    external
    onlyDuringValidInterval(FN.BID)
  {
    Bid memory _bestBid = bestBid;
    // First bid
    if (_bestBid.bidder == address(0)) {
      require(BidImpl.acceptableBid(_tokens, _quantities, deltaTokens, deltaQuantities));
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

  function getRebalanceDeltas() public view returns (address[] memory, int256[] memory) {
    return BidImpl.getRebalanceDeltas(registry, tokens, totalUnits());
  }

  function reportFrozenToken(address token) public {
    (uint256 index, bool isIn) = tokensToSkip.indexOf(token);
    if (ERC20TokenUtils.checkFrozen(token)) {
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

  function creationUnit() public view returns (address[] memory, uint256[] memory) {
    return (tokens, quantities);
  }

  function totalUnits() public view returns (uint256) {
    return totalSupply().div(creationSize);
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

  function isNonZero(uint256 n) internal pure returns (bool) {
    return n != 0;
  }

}
