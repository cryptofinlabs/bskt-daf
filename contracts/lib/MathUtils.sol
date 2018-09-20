pragma solidity 0.4.24;

library MathUtils {

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
