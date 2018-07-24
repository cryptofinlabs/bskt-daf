pragma solidity 0.4.24;
pragma experimental "v0.5.0";
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
import "./Math.sol";


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

  address[] public tokens;
  uint256[] public quantities;  // is this needed? Could read balances from token contracts directly, though a potential risk
  BsktRegistry public registry;
  Escrow public escrow;
  uint256 public rebalancingPeriodOffset;
  uint256 public rebalancingInterval;
  uint256 public rebalancingDuration;

  // Maybe just decompose
  Bid public bestBid;

  // === EVENTS ===

  event Create(address indexed creator, uint256 amount);
  event Redeem(address indexed redeemer, uint256 amount, address[] skippedTokens);
  event RebalanceStart(address caller);
  event RebalanceEnd();

  event EscrowDeployed();
  event OK();
  event LogAddresses(address[] a);

  // === MODIFIERS ===

  /// @notice Requires value to be divisible by creationUnit
  /// @param value Number to be checked
  modifier requireMultiple(uint256 value) {
    // TODO: inefficient since creationSize is used later in the functions that use this modifier
    uint256 _creationSize = creationSize();
    require((value % _creationSize) == 0);
    _;
  }

  modifier requireSortedRational256(Rational.Rational256[] memory A) {
    for (uint256 i = 1; i < A.length; i++) {
      require(A[i - 1].lte(A[i]));
    }
    _;
  }

  modifier rebalancingPeriod() {
    // TODO: use rebalancingPeriodOffset
    uint256 startInterval = now.div(rebalancingInterval).mul(rebalancingInterval);
    uint256 endInterval = startInterval.add(rebalancingDuration);
    require(startInterval <= now);
    require(now <= endInterval);
    _;
  }

  // === CONSTRUCTOR ===

  constructor(
    // should we remove these in favour of just specifying registry and setting to that initially?
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
    tokens = _tokens;
    quantities = _quantities;
    registry = BsktRegistry(_registry);

    escrow = new Escrow(address(this));
    emit EscrowDeployed();
  }

  // === EXTERNAL FUNCTIONS ===

  function issue(uint256 amount)
    external
    whenNotPaused()
    requireMultiple(amount)
  {
    require(amount > 0);
    require((totalSupply_ + amount) > totalSupply_);

    uint256 _creationSize = creationSize();
    uint256 tokensLength = tokens.length;
    for (uint256 i = 0; i < tokensLength; i++) {
      ERC20 erc20 = ERC20(tokens[i]);
      uint256 amountTokens = amount.div(_creationSize).mul(quantities[i]);
      require(erc20.transferFrom(msg.sender, address(this), amountTokens));
    }

    mint(msg.sender, amount);
    emit Create(msg.sender, amount);
  }

  function redeem(uint256 amount, address[] tokensToSkip)
    external
    requireMultiple(amount)
  {
    require(amount > 0);
    require(amount <= totalSupply_);
    require(amount <= balances[msg.sender]);
    uint256 tokensLength = tokens.length;
    require(tokensToSkip.length <= tokensLength);

    // Burn before to prevent re-entrancy
    burn(msg.sender, amount);

    uint256 _creationSize = creationSize();
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

  function rebalance(address _token) external {
    //getRebalanceDeltas();
    //// set up auctions
    //uint256 targetAmount = getTargetAmount(_token);
    //// do we account balances in BsktToken, or let each token implement it?
    //// what if token's balanceOf is malicious?
     //uint256 tokenBalance = ERC20(token).balanceOf(address(this));
     //if (targetAmount > tokenBalance) {
       //// dutch auction (ask, offer)
     //} else if (targetAmount < tokenBalance) {
       //// dutch auction (ask, offer)
     //} else {
       //return;
     //}
  }

  // Assumes tokens and quantities are sorted
  // Returns true if A is better, false if B is better
  // If equal, favors A
  function compareBids(
    address[] memory tokensA,
    int256[] memory quantitiesA,
    address[] memory tokensB,
    int256[] memory quantitiesB
  )
    public
    //view
    returns (bool)
  {
    require(tokensA.length == quantitiesA.length);
    require(tokensA.length == tokensB.length);
    require(tokensA.length == quantitiesB.length);
    (address[] memory deltaTokens, int256[] memory deltaQuantities) = getRebalanceDeltas();
    Rational.Rational256[] memory fillProportionA = new Rational.Rational256[](deltaTokens.length);
    Rational.Rational256[] memory fillProportionB = new Rational.Rational256[](deltaTokens.length);
    for (uint256 i = 0; i < deltaTokens.length; i++) {
      if (deltaQuantities[i] > 0) {
        require(quantitiesA[i] >= 0);
        require(quantitiesB[i] >= 0);
        fillProportionA[i] = Rational.Rational256({ n: uint256(quantitiesA[i]), d: uint256(deltaQuantities[i]) });
        fillProportionB[i] = Rational.Rational256({ n: uint256(quantitiesB[i]), d: uint256(deltaQuantities[i]) });
       } else {
         // If tokens are being sold (negative delta), it's not relevant to comparison
         // Entry will be 0
         // It's assumed bidders act in their own economic interest, so they
         // wouldn't leave any tokens on the table
         continue;
       }
    }
    return true;
    //return compareSortedRational256s(fillProportionA, fillProportionB);
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

  //// Assumes fillProportions are sorted
  //// Returns true if A is better, false if B is better
  //// If equal, favors B
  //function compareSortedRational256s(Rational.Rational256[] memory A, Rational.Rational256[] memory B)
    //public
    //requireSortedRational256(A)
    //requireSortedRational256(B)
    //returns (bool)
  //{
    //for (uint256 i = 0; i < A.length; i++) {
      //if (A[i].gt(B[i])) {
        //return true;
      //} else if (A[i].lt(B[i])) {
        //return false;
      //} else {
        //continue;
      //}
    //}
    //return false;
  //}

  function bid(address[] _tokens, int256[] _quantities) external {
    Bid memory _bestBid = bestBid;
    if (
      _bestBid.bidder == address(0) ||  // No bid yet
      compareBids(_tokens, _quantities, _bestBid.tokens, _bestBid.quantities)
    ) {
      if (_bestBid.bidder != address(0)) {
        escrow.releaseBid(_bestBid.tokens, _bestBid.bidder, _bestBid.quantities);
      }
      bestBid = Bid({
        bidder: msg.sender,
        tokens: _tokens,
        quantities: _quantities
      });
      escrow.escrowBid(_tokens, msg.sender, _quantities);
    }
  }

  // naming of target vs all vs registry?
  // TODO: handle invalid data
  // deltas required. + means this contract needs to buy, - means sell
  function getRebalanceDeltas()
    public
    //view
    returns(address[] memory, int256[] memory)
  {
    address[] memory registryTokens = registry.getTokens();
    address[] memory targetTokens = registryTokens.union(tokens);
    emit LogAddresses(targetTokens);
    uint256[] memory targetQuantities = registry.getQuantities(targetTokens);
    uint256 length = targetTokens.length;
    int256[] memory deltas = new int256[](length);
    for (uint256 i = 0; i < length; i++) {
      ERC20 erc20 = ERC20(targetTokens[i]);
      // assert that balance is >= quantity recorded for that token
      uint256 balance = erc20.balanceOf(address(this));
      // TODO: ensure no overflow
      // TODO: add safemath
      deltas[i] = int256(targetQuantities[i]) - (int256(balance));
    }
    return (targetTokens, deltas);
  }

  function creationUnit() view public returns(address[] memory, uint256[] memory) {
    uint256 numTokens = tokens.length;
    address[] memory _tokens = new address[](numTokens);
    uint256[] memory _quantities = new uint256[](numTokens);
    for (uint256 i = 0; i < numTokens; i += 1) {
      _quantities[i] = quantities[i].div(totalSupply_);
    }
    return (_tokens, _quantities);

  }

  // `map` doesn't work if these are in a library
  function logFloor(uint256 n) public pure returns(uint256) {
    uint256 _n = n;
    uint256 i = 0;
    while(true) {
      if (_n < 10) {
        break;
      }
      _n /= 10;
      i += 1;
    }
    return i;
  }

  function min(uint256 a, uint256 b) public pure returns(uint256) {
    return a < b ? a : b;
  }

  // TODO: Make stored and only update on rebalance. Should be cheaper on gas
  function creationSize() view public returns(uint256) {
    uint256 optimal = quantities.map(logFloor).reduce(min);
    return Math.max(uint256(decimals).sub(optimal), 1);
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

}
