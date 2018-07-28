pragma solidity 0.4.24;
//pragma experimental ABIEncoderV2;


import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "cryptofin-solidity/contracts/array-utils/UIntArrayUtils.sol";
import "cryptofin-solidity/contracts/rationals/Rational.sol";
import "cryptofin-solidity/contracts/rationals/RationalMath.sol";
import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
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
  Pausable,
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
  enum State {
    OPT_OUT,  // After snapshotting the delta, give investors some time to opt-out if they don't agree with the rebalance. I want a better name though
    AUCTIONS_OPEN,  // Bids being accepted
    // Rebalance
    OPEN,
  }

  enum FN {
    ISSUE,
    REDEEM,
    BID,
    REBALANCE
  }

  address[] public tokens;
  uint256[] public quantities;  // is this needed? Could read balances from token contracts directly, though a potential risk

  // Snapshot of the delta of tokens needed to rebalance
  // These are set by commitDelta
  address[] public deltaTokens;
  uint256[] public deltaQuantities;

  BsktRegistry public registry;
  Escrow public escrow;

  uint256 public xInterval;
  uint256 public xOffset;
  uint256 public auctionOffset;
  uint256 public auctionDuration;
  uint256 public optOutDuration;
  uint256 public rebalancingDuration;


  // Maybe just decompose
  Bid public bestBid;

  // === EVENTS ===

  event Issue(address indexed creator, uint256 amount);
  event Redeem(address indexed redeemer, uint256 amount, address[] skippedTokens);
  event RebalanceStart(address caller);
  event RebalanceEnd();
  event Rebalance(address caller);
  event BidAccepted(address bidder, address[] tokens, int256[] quantities, uint256 totalUnits);  // tense is inconsistent
  event EscrowDeployed();

  // tests
  event OK();
  event LogAddresses(address[] a);
  event LogQuantities(uint256[] a);
  event LogInt256s(int256[] a);
  event LogUInt256(uint256 n);

  // === MODIFIERS ===

  modifier requireSortedRational256(Rational.Rational256[] memory A) {
    for (uint256 i = 1; i < A.length; i++) {
      require(A[i - 1].lte(A[i]));
    }
    _;
  }

  // |,_ commitDelta  |<- auctionIntervalStart  |<- auctionIntervalEnd
  // |------------------------------------------|--------------------------------|----------- ...
  // |                |        Auction          |            Rebalance           |    Open    ...
  // |     Opt-out    |                         |                                |
  // |------------------------------------------|--------------------------------|----------- ...

  // intervals should always be [)
  modifier onlyDuringValidInterval(FN fn) {
    uint256 xIntervalStart = now.div(xInterval).mul(xInterval).add(xOffset);

    uint256 optOutIntervalStart = xIntervalStart;
    uint256 optOutIntervalEnd = xIntervalStart.add(auctionOffset);

    uint256 auctionIntervalStart = xIntervalStart.add(auctionOffset);
    uint256 auctionIntervalEnd = auctionIntervalStart.add(auctionDuration);

    uint256 rebalanceIntervalStart = auctionIntervalEnd;
    uint256 rebalanceIntervalEnd = rebalanceIntervalStart.add(rebalanceDuration);

    uint256 openIntervalStart = rebalanceIntervalEnd;
    // openIntervalEnd is whatever time is left

    if (fn == FN.ISSUE || fn == FN.REDEEM) {
      require(state == State.OPT_OUT);
      require(optOutIntervalStart <= now && now < optOutIntervalEnd || openIntervalStart <= now);
    } else if (fn == FN.BID) {
      require(state == State.OPT_OUT || state == State.AUCTIONS_OPEN);
      require(auctionIntervalStart <= now && now < auctionIntervalEnd);
      if (state == State.OPT_OUT && auctionIntervalStart <= now) {
        state = State.AUCTIONS_OPEN;
      }
    } else if (fn == FN.REBALANCE) {
      // require(state == State.AUCTIONS_OPEN);  // What if no bids were made, so the state never transitioned from OPT_OUT to AUCTIONS_OPEN?
      require(rebalanceIntervalStart <= now && now < rebalanceIntervalEnd);
    } else
      revert();
    }
    _;
  }

  // === CONSTRUCTOR ===

  constructor(
    // should we remove these in favour of just specifying registry and setting to that initially?
    // read from registry here
    address[] _tokens,
    uint256[] _quantities,
    address _registry,
    string _name,
    string _symbol
  ) DetailedERC20(_name, _symbol, 18)
    public
  {
    //require(_tokens.length > 0);  // Will need this to prevent attack - can mint infinite tokens
    require(_tokens.length == _quantities.length);
    //require(auctionOffset.add(auctionDuration).add(rebalanceDuration) <= xInterval);
    tokens = _tokens;
    quantities = _quantities;
    registry = BsktRegistry(_registry);

    escrow = new Escrow(address(this));
    emit EscrowDeployed();

    ERC20 feeToken = registry.feeToken();
    feeToken.approve(registry, MAX_UINT256());
  }

  // === EXTERNAL FUNCTIONS ===

  function issue(uint256 amount)
    external
    onlyOpenPeriod()
    whenNotPaused()
  {
    require(amount > 0);
    require((totalSupply_ + amount) > totalSupply_);
    uint256 _creationSize = creationSize();
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
    onlyOpenPeriod()
  {
    require(amount > 0);
    require(amount <= totalSupply_);
    require(amount <= balances[msg.sender]);
    uint256 _creationSize = creationSize();
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
        // quantity
        uint256 amount = uint256(-_bestBid.quantities[i]).mul(_totalUnits);
        ERC20(_bestBid.tokens[i]).transfer(bestBid.bidder, amount);
      }
    }
  }

  // List of tokens in bestBid should be the union of tokens in registry and fund
  // TODO needs to be modified for more than just one creationUnit
  // TODO need to prune tokens with balance 0
  function updateBalances() internal {
    Bid memory _bestBid = bestBid;
    uint256[] memory updatedQuantities = new uint256[](_bestBid.tokens.length);
    for (uint256 i = 0; i < _bestBid.tokens.length; i++) {
      ERC20 erc20 = ERC20(_bestBid.tokens[i]);
      // Must query balance to deal with airdrops
      updatedQuantities[i] = erc20.balanceOf(address(this)).div(totalUnits());
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

  // TODO: maybe add some options to not rebalance if bestBid is atrocious (< threshold%)
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

  // Assumes tokens and quantities are sorted
  // Returns true if A is better, false if B is better
  // If equal, favors A
  // Should probably rename to something like "isBidBetter"
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
    (address[] memory _deltaTokens, int256[] memory _deltaQuantities) = getRebalanceDeltas();
    Rational.Rational256[] memory fillProportionA = new Rational.Rational256[](_deltaTokens.length);
    Rational.Rational256[] memory fillProportionB = new Rational.Rational256[](_deltaTokens.length);
    for (uint256 i = 0; i < _deltaTokens.length; i++) {
      if (_deltaQuantities[i] > 0) {
        require(quantitiesA[i] >= 0);
        require(quantitiesB[i] >= 0);
        fillProportionA[i] = Rational.Rational256({ n: uint256(quantitiesA[i]), d: uint256(_deltaQuantities[i]) });
        fillProportionB[i] = Rational.Rational256({ n: uint256(quantitiesB[i]), d: uint256(_deltaQuantities[i]) });
       } else {
         // If tokens are being sold (negative delta), it's not relevant to comparison
         // Entry will be 0
         // It's assumed bidders act in their own economic interest, so they
         // wouldn't leave any tokens on the table
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

  function bid(address[] _tokens, int256[] _quantities)
    external
    onlyAuctionPeriod()
  {
    Bid memory _bestBid = bestBid;
    if (_bestBid.bidder == address(0)) {
      bestBid = Bid({
        bidder: msg.sender,
        tokens: _tokens,
        quantities: _quantities
      });
      uint256 _totalUnits = totalUnits();
      escrow.escrowBid(_tokens, msg.sender, _quantities, _totalUnits);
      emit BidAccepted(msg.sender, _tokens, _quantities, _totalUnits);
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

  // snapshot the registry
  function commitDelta() {
    (deltaTokens, deltaQuantities) = getRebalanceDeltas();
    state = State.OPT_OUT;
  }

  // naming of target vs all vs registry?
  // TODO: handle invalid data
  // deltas required. + means this contract needs to buy, - means sell
  // costs fees for the fund
  function getRebalanceDeltas() public returns (address[] memory, int256[] memory) {
    address[] memory registryTokens = registry.getTokens();
    address[] memory targetTokens = registryTokens.union(tokens);
    emit LogAddresses(targetTokens);
    uint256[] memory targetQuantities = registry.getQuantities(targetTokens);
    emit LogQuantities(targetQuantities);
    uint256 length = targetTokens.length;
    int256[] memory deltas = new int256[](length);
    for (uint256 i = 0; i < length; i++) {
      ERC20 erc20 = ERC20(targetTokens[i]);
      // assert that balance is >= quantity recorded for that token
      uint256 balance = erc20.balanceOf(address(this));
      emit LogUInt256(balance);
      // TODO: ensure no overflow
      // TODO: add safemath
      deltas[i] = int256(targetQuantities[i]) - (int256(balance));
    }
    emit LogInt256s(deltas);
    return (targetTokens, deltas);
  }

  function creationUnit() public view returns (address[] memory, uint256[] memory) {
    uint256 numTokens = tokens.length;
    address[] memory _tokens = new address[](numTokens);
    uint256[] memory _quantities = new uint256[](numTokens);
    for (uint256 i = 0; i < numTokens; i += 1) {
      _quantities[i] = quantities[i].div(totalSupply_);
    }
    return (_tokens, _quantities);
  }

  // TODO: Make stored and only update on rebalance. Should be cheaper on gas
  function creationSize() public view returns (uint256) {
    uint256 optimal = quantities.map(logFloor).reduce(min);
    return pow(10, max(uint256(decimals).sub(optimal), 1));
  }

  function totalUnits() public view returns (uint256) {
    return totalSupply_.div(creationSize());
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



  // === MATH ===

  // pure was removed to work with solidity-coverage

  // `map` doesn't work if these are in a library
  function logFloor(uint256 n) public pure returns (uint256) {
    uint256 _n = n;
    uint256 i = 0;
    while(true) {
      if (_n < 10) {
        break;
      }
      _n /= 10;
      i += 1; }
    return i;
  }

  function max(uint256 a, uint256 b) public pure returns (uint256) {
    return a >= b ? a : b;
  }

  function min(uint256 a, uint256 b) public pure returns (uint256) {
    return a < b ? a : b;
  }

  function pow(uint256 a, uint256 b) public pure returns (uint256) {
    uint256 product = 1;
    for (uint256 i = 0; i < b; i++) {
      product = product.mul(a);
    }
    return product;
  }

  function MAX_UINT256() internal pure returns (uint256) {
    return 2 ** 256 - 1;
  }

}
