pragma solidity 0.4.24;

import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "cryptofin-solidity/contracts/array-utils/UIntArrayUtils.sol";
import "cryptofin-solidity/contracts/rationals/Rational.sol";
import "cryptofin-solidity/contracts/rationals/RationalMath.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";

import "./BsktRegistry.sol";
import "./Escrow.sol";
import "./IBsktToken.sol";
import "./impl/BidImpl.sol";
import "./lib/Bid.sol";
import "./lib/dYdX/TokenInteract.sol";
import "./lib/dYdX/TokenProxy.sol";


contract RebalancingBsktToken is ERC20Detailed, ERC20 {

  using AddressArrayUtils for address[];
  using RationalMath for Rational.Rational256;
  using SafeMath for uint256;
  using UIntArrayUtils for uint256[];

  enum Status {
    OPT_OUT,  // After snapshotting the delta, give investors some time to opt-out if they don't agree with the rebalance. I want a better name though
    AUCTIONS_OPEN,  // Bids being accepted
    OPEN
  }

  enum FN {
    PROPOSE,
    ISSUE,
    REDEEM,
    BID,
    REBALANCE
  }

  address[] public tokens;
  uint256[] public quantities;
  uint256 public creationSize;

  address[] public deltaTokens;
  uint256[] public currentQuantities;
  uint256[] public targetQuantities;
  address[] public tokensToSkip;

  BsktRegistry public registry;
  Escrow public escrow;
  TokenProxy public tokenProxy;
  Status public status;

  uint256 public rebalancePeriod;
  uint256 public periodOffset;
  uint256 public auctionOffset;
  uint256 public auctionDuration;
  uint256 public optOutDuration;
  uint256 public settleDuration;

  Bid.Bid public bestBid;

  // === EVENTS ===

  event Issue(address indexed creator, uint256 amount);
  event Redeem(address indexed redeemer, uint256 amount, address[] skippedTokens);
  event Rebalance(address caller);
  event ProposeRebalance(address[] tokens, uint256[] targetQuantities);

  // === MODIFIERS ===

  // Periods should always satisfy range [)
  modifier onlyDuringValidPeriod(FN fn) {
    checkValidPeriod(fn);
    _;
  }

  function checkValidPeriod(FN fn) internal {
    uint256 rebalancePeriodStart = now.div(rebalancePeriod).mul(rebalancePeriod).add(periodOffset);

    uint256 optOutPeriodStart = now;
    uint256 optOutPeriodEnd = now.add(optOutDuration);

    uint256 auctionPeriodStart = rebalancePeriodStart.add(auctionOffset);
    uint256 auctionPeriodEnd = auctionPeriodStart.add(auctionDuration);

    uint256 settlePeriodStart = auctionPeriodEnd;
    uint256 settlePeriodEnd = settlePeriodStart.add(settleDuration);

    uint256 openPeriodStart = settlePeriodEnd;

    if (fn == FN.PROPOSE) {
      require(status == Status.OPEN ||
              status == Status.OPT_OUT,
              "Error: Invalid status");
      require(optOutPeriodEnd <= auctionPeriodStart);
      if (status == Status.OPEN) {
        status = Status.OPT_OUT;
      }
    } else if (fn == FN.ISSUE || fn == FN.REDEEM) {
      require(status == Status.OPT_OUT ||
              status == Status.OPEN,
              "Error: Invalid status");
      require(optOutPeriodStart <= now &&
              now < optOutPeriodEnd ||
              openPeriodStart <= now,
              "Error: not within opt out period");
    } else if (fn == FN.BID) {
      // The first bid will transition status from opt out to auction
      require(status == Status.OPT_OUT ||
              status == Status.AUCTIONS_OPEN,
              "Error: Invalid status");
      require(auctionPeriodStart <= now &&
              now < auctionPeriodEnd,
              "Error; not within opt out period");
      if (status == Status.OPT_OUT && auctionPeriodStart <= now) {
        status = Status.AUCTIONS_OPEN;
      }
    } else if (fn == FN.REBALANCE) {
       require(status == Status.AUCTIONS_OPEN);
      // If no bids were made, so the status never transitioned from OPT_OUT to
      // AUCTIONS_OPEN, then bestBid.bidder is 0, which will trigger a require later
      require(settlePeriodStart <= now &&
              now < settlePeriodEnd,
              "Error: not within rebalancing period");
      status = Status.OPEN;
    } else {
      revert("Error: Period not recognized");
    }
  }

  // === CONSTRUCTOR ===

  /**
   * Constructor for RebalancingBsktToken
   *
   * @param _tokens Tokens in the initial creation unit
   * @param _quantities Quantities in the initial creation unit
   * @param _creationSize Amount (in base units) for one creation unit
   * @param _registry Address of registry contract
   * @param _rebalancePeriod Duration in seconds of the rebalancing period
   * @param _periodOffset Duration in seconds of the offset to start of rebalancing period
   * @param _auctionOffset Duration in seconds of the offset to the start of the auction period
   * @param _auctionDuration Duration in seconds of the auction period
   * @param _optOutDuration Duration in seconds of the opt out period
   * @param _settleDuration Duration in seconds of the settle period
   * @param _name Name of the token
   * @param _symbol Ticker symbol of the token
   */
  constructor(
    // should we remove these in favour of just specifying registry and setting to that initially?
    // read from registry here
    // what to do about fees initially?
    address[] _tokens,
    uint256[] _quantities,
    uint256 _creationSize,
    address _registry,
    uint256 _rebalancePeriod,
    uint256 _periodOffset,
    uint256 _auctionOffset,
    uint256 _auctionDuration,
    uint256 _optOutDuration,
    uint256 _settleDuration,
    string _name,
    string _symbol
  ) ERC20Detailed (_name, _symbol, 18)
    public
  {
    // Prevent the creation unit from being empty, which would allow issuing unlimited tokens
    require(_tokens.length > 0);
    require(_quantities.argFilter(isNonZero).length > 0);

    require(_tokens.length == _quantities.length);
    require(_optOutDuration < _auctionOffset);
    require(_auctionOffset.add(_auctionDuration).add(_settleDuration) <= _rebalancePeriod);

    tokens = _tokens;
    quantities = _quantities;
    creationSize = _creationSize;
    registry = BsktRegistry(_registry);

    escrow = new Escrow(address(this));
    address[] memory authorizedAddresses = new address[](2);
    authorizedAddresses[0] = address(this);
    authorizedAddresses[1] = address(escrow);
    tokenProxy = new TokenProxy(authorizedAddresses);
    escrow.setTokenProxy(address(tokenProxy));

    rebalancePeriod = _rebalancePeriod;
    periodOffset = _periodOffset;
    auctionOffset = _auctionOffset;
    auctionDuration = _auctionDuration;
    optOutDuration = _optOutDuration;
    settleDuration = _settleDuration;

    // Set up allowance so fees can be paid to registry
    address feeToken = registry.feeToken();
    TokenInteract.approve(feeToken, registry, MAX_UINT256());

    status = Status.OPT_OUT;
  }

  // === EXTERNAL FUNCTIONS ===

  /**
   * Creates Bskt tokens in exchange for underlying tokens. Before calling,
   * underlying tokens must be approved to be moved by the Bskt contract.
   *
   * @param amount Number of Bskt tokens to create, in base units. Must be a
   * multiple of the creationSize.
   */
  function issue(uint256 amount)
    external
    onlyDuringValidPeriod(FN.ISSUE)
  {
    require(amount > 0);
    require((totalSupply() + amount) > totalSupply());
    uint256 _creationSize = creationSize;
    require((amount % _creationSize) == 0);

    uint256 tokensLength = tokens.length;
    for (uint256 i = 0; i < tokensLength; i++) {
      address tokenAddress = tokens[i];
      bool isIn = tokensToSkip.contains(tokenAddress);
      if (isIn) {
        continue;
      }
      uint256 amountTokens = amount.div(_creationSize).mul(quantities[i]);
      tokenProxy.transferTokens(tokenAddress, msg.sender, address(this), amountTokens);
    }

    _mint(msg.sender, amount);
    emit Issue(msg.sender, amount);
  }

  /**
   * Destroys Bskt tokens in exchange for underlying tokens.
   *
   * @param amount Number of Bskt tokens to redeem, in base units. Must be a
   * multiple of the creationSize.
   * @param tokensToSkipOverride List of tokens to skip. Overrides the default
   * tokensToSkip
   */
  function redeem(uint256 amount, address[] tokensToSkipOverride)
    external
    onlyDuringValidPeriod(FN.REDEEM)
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
      bool isIn = _tokensToSkip.contains(tokenAddress);
      if (isIn) {
        continue;
      }
      uint256 amountTokens = amount.div(_creationSize).mul(quantities[i]);
      TokenInteract.transfer(tokenAddress, msg.sender, amountTokens);
    }
    emit Redeem(msg.sender, amount, _tokensToSkip);
  }

  /**
   * Transfers tokens between escrow, fund, and bidder to settle bid
   */
  function settleBid() internal {
    BidImpl.settleBid(bestBid, escrow, totalUnits());
  }

  /**
   * Updates creation unit tokens and quantities
   */
  function updateBalances() internal {
    Bid.Bid memory _bestBid = bestBid;
    uint256[] memory updatedQuantities = new uint256[](_bestBid.tokens.length);
    for (uint256 i = 0; i < _bestBid.tokens.length; i++) {
      // Must query balance to deal with airdrops
      updatedQuantities[i] = TokenInteract.balanceOf(_bestBid.tokens[i], address(this));
    }
    uint256 _totalUnits = totalUnits();
    for (i = 0; i < _bestBid.tokens.length; i++) {
      updatedQuantities[i] = updatedQuantities[i].div(_totalUnits);
    }

    // Filter out tokens with quantity 0
    uint256[] memory indexArray = updatedQuantities.argFilter(isNonZero);
    if (indexArray.length != _bestBid.tokens.length) {
      // Mismatch because some were zero, so filter them out
      tokens = _bestBid.tokens.argGet(indexArray);
      quantities = updatedQuantities.argGet(indexArray);
    } else {
      // If they're the same, just use _bestBid.tokens
      tokens = _bestBid.tokens;
      quantities = updatedQuantities;
    }
  }

  /**
   * Settles the best bid and updates creation unit
   * Only callable during the settlement period
   */
  function rebalance()
    external
    onlyDuringValidPeriod(FN.REBALANCE)
  {
    // This case should be caught by onlyDuringValidPeriod since the state would've never transitioned to the required one
    assert(bestBid.bidder != address(0));
    settleBid();
    updateBalances();
    // set some didRebalance flag
    delete bestBid;
    emit Rebalance(msg.sender);
  }

  /**
   * Offers a bid. Escrows the tokens specified by the bid. Releases escrowed tokens if a bid is beaten.
   *
   * @param numerator Numerator of rational representing percentage to fill
   * @param denominator Denominator of rational representing percentage to fill
   */
  function bid(uint256 numerator, uint256 denominator)
    external
    onlyDuringValidPeriod(FN.BID)
  {
    return BidImpl.bid(
      numerator,
      denominator,
      deltaTokens,
      targetQBid struct containing info about the best biduantities,
      currentQuantities,
      totalUnits(),
      escrow,
      bestBid
    );
  }

  /**
   * Takes a snapshot of the registry for use when rebalancing
   * proposeRebalance is callable multiple times, as long as there's enough time left
   */
  function proposeRebalance() public
    onlyDuringValidPeriod(FN.PROPOSE)
  {
    require(totalUnits() > 0);
    (deltaTokens, targetQuantities) = BidImpl.getProposedCreationUnit(registry, tokens);
    uint256[] memory indexArray = targetQuantities.argFilter(isNonZero);
    // Prevent creation unit from being nothing, which would allow unlimited issuance
    require(indexArray.length != 0);
    currentQuantities = BidImpl.getCurrentQuantities(deltaTokens, totalUnits());
    emit ProposeRebalance(deltaTokens, targetQuantities);
  }

  /**
   * Returns array of quantities in specified order
   *
   * @param _tokens Tokens to get current creation unit quantities 
   */
  function getCurrentQuantities(address[] memory _tokens)
    public
    view
    returns (uint256[] memory)
  {
    return BidImpl.getCurrentQuantities(_tokens, totalUnits());
  }

  /**
   * Reports a token as frozen if it can be verified that they can't be transferred.
   * If a token is successfully reported, it's removed from the creation unit
   * for creation and redemption. Note that redemption can ability to override it.
   * It should not be possible to falsely report a frozen token, as doing so
   * could enable exploits.
   *
   * @param token Token address to report as frozen
   */
  function reportFrozenToken(address token) public {
    BidImpl.reportFrozenToken(token, tokens, tokensToSkip, tokenProxy);
  }

  function computeBidQuantities(
    uint256 numerator,
    uint256 denominator,
    uint256[] _currentQuantities,
    uint256[] _targetQuantities
  )
    public
    pure
    returns (int256[] memory)
  {
    return BidImpl.computeBidQuantities(numerator, denominator, _currentQuantities, _targetQuantities);
  }

  /**
   * Returns creation unit
   * @return (tokens, quantities)
   */
  function creationUnit() public view returns (address[] memory, uint256[] memory) {
    return (tokens, quantities);
  }

  /**
   * Returns total number of creation units
   * @return _totalUnits
   */
  function totalUnits() public view returns (uint256) {
    return totalSupply().div(creationSize);
  }

  /**
   * Returns the tokens of the creation unit
   * @return tokens
   */
  function getTokens() external view returns (address[] memory) {
    return tokens;
  }

  /**
   * Returns the quantities of the creation unit
   * @return quantities
   */
  function getQuantities() external view returns (uint256[] memory) {
    return quantities;
  }

  /**
   * Returns tokens being considered for rebalancing
   * This is the union of the tokens in the current creation unit and tokens in
   * the target creation unit
   */
  function getDeltaTokens() external view returns (address[] memory) {
    return deltaTokens;
  }

  /**
   * Get default list of tokens to skip for issuance and redemption due to being
   * frozen
   */
  function getTokensToSkip() external view returns (address[] memory) {
    return tokensToSkip;
  }

  /**
   * Returns the quantities of the target creation unit
   */
  function getTargetQuantities() external view returns (uint256[] memory) {
    return targetQuantities;
  }

  // === MATH ===

  // TODO: use the one from library once a fix to solidity-coverage linking issue is found
  /**
   * Returns the max uint256
   */
  function MAX_UINT256() internal pure returns (uint256) {
    return 2 ** 256 - 1;
  }

  /**
   * Predicate returning whether input is non-zero
   */
  function isNonZero(uint256 n) internal pure returns (bool) {
    return n != 0;
  }

}
