import "openzeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";


library Math {

  using SafeMath for uint256;

  event SomeEvent(uint256 value);

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

  function max(uint256 a, uint256 b) public pure returns (uint256) {
    return a >= b ? a : b;
  }

  function min(uint256 a, uint256 b) public pure returns (uint256) {
    return a < b ? a : b;
  }

  function MAX_UINT256() internal pure returns (uint256) {
    return 2 ** 256 - 1;
  }

}
