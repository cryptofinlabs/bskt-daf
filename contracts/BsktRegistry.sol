pragma solidity 0.4.24;
pragma experimental "v0.5.0";

import "cryptofin-solidity/contracts/array-utils/AddressArrayUtils.sol";
import "cryptofin-solidity/contracts/array-utils/UIntArrayUtils.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import "./IBsktRegistry.sol";
import "./lib/dYdX/TokenInteract.sol";


contract BsktRegistry is /* IBsktRegistry, */ Ownable {

  using AddressArrayUtils for address[];
  using SafeMath for uint256;
  using UIntArrayUtils for uint256[];

  address public beneficiary;
  IERC20 public feeToken;
  uint256 public readFeeAmount;

  // Internal to enforce fees
  address[] internal tokens;
  uint256[] internal quantities;

  // === EVENTS ===

  event Get(address from, uint256 feeAmount);
  event Set(uint256 index, address token, uint256 quantity);

  modifier checkInvariants() {
    require(tokens.length == quantities.length);
    _;
    assert(tokens.length == quantities.length);
  }

  // === CONSTRUCTOR ===

  /**
   * @param _beneficiary Address to payout fees to
   * @param _feeToken Token to charge fees in
   * @param _amount Amount of tokens charged per read
   */
  constructor(address _beneficiary, address _feeToken, uint256 _amount) public {
    beneficiary = _beneficiary;
    feeToken = IERC20(_feeToken);
    readFeeAmount = _amount;
  }

  // === PUBLIC FUNCTIONS ===

  /**
   * Updates all token and quantity entries in registry
   * @param _tokens Array of token addresses
   * @param _quantities Array of quantities
   */
  function batchSet(address[] memory _tokens, uint256[] memory _quantities) public onlyOwner checkInvariants {
    tokens = _tokens;
    quantities = _quantities;
  }

  /**
   * Updates a single entry in the registry
   * @param index Index of the entry to update
   * @param token Address of the token
   * @param quantity Amount
   */
  function set(uint256 index, address token, uint256 quantity) public onlyOwner checkInvariants {
    // only if it's greater than by one. otherwise it should fail or pad
    if (index >= tokens.length) {
      tokens.push(token);
      quantities.push(quantity);
    } else {
      tokens[index] = token;
      quantities[index] = quantity;
    }
    emit Set(index, token, quantity);
  }

  /**
   * Removes entry from registry, specified by token
   * @param token Address of token to remove
   */
  function remove(address token) public onlyOwner returns (bool) {
    (uint256 index, bool isIn) = tokens.indexOf(token);
    if (!isIn) {
      return false;
    } else {
      tokens.sPopCheap(index);
      quantities.sPopCheap(index);
      return true;
    }
  }

  /**
   * Returns quantity of entry associated with specified token
   * @param token Token to get
   */
  function get(address token) public returns (uint256) {
    // token interact
    require(feeToken.transferFrom(msg.sender, beneficiary, readFeeAmount), "fee could not be collected");
    (uint256 index, bool isIn) = tokens.indexOf(token);
    emit Get(msg.sender, readFeeAmount);
    if (!isIn) {
      return 0;
    } else {
      return quantities[index];
    }
  }

  /**
   * Gets array of quantities in order specified by _tokens. This is required since the registry's data is stored in two separate arrays
   * Costs a fee to call on chain
   * Careful, runs O(n^2)
   * @param _tokens Array of tokens to fetch quantities of
   */
  function getQuantities(address[] memory _tokens) public returns (uint256[] memory) {
    require(feeToken.transferFrom(msg.sender, beneficiary, readFeeAmount), "fee could not be collected");
    uint256 length = _tokens.length;
    uint256[] memory _quantities = new uint256[](length);
    for (uint256 i = 0; i < length; i++) {
      (uint256 index, bool isIn) = tokens.indexOf(_tokens[i]);
      if (isIn) {
        _quantities[i] = quantities[index];
      } else {
        _quantities[i] = 0;  // Assume anything not in registry is 0
      }
    }
    emit Get(msg.sender, readFeeAmount);
    return _quantities;
  }

  /**
   * Returns all quantity entries in the order they're stored internally. Costs a fee to call on-chain.
   */
  function getAllQuantities() public returns (uint256[] memory) {
    require(feeToken.transferFrom(msg.sender, beneficiary, readFeeAmount));
    emit Get(msg.sender, readFeeAmount);
    return quantities;
  }

  // === VIEW FUNCTIONS ===

  /**
   * Returns all tokens in the order they're stored internally.
   */
  function getTokens() public view returns (address[] memory) {
    return tokens;
  }

  // === ONLY OWNER ===

  function withdrawTokens(address _token, uint256 _amount)
    external
    onlyOwner
  {
    TokenInteract.transfer(_token, owner(), _amount);
  }

}
