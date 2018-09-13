pragma solidity 0.4.24;

import "cryptofin-solidity/contracts/rationals/Rational.sol";


library Bid {

  struct Bid {
    address bidder;
    Rational.Rational256 bidPercentage;
    address[] tokens;
    int256[] quantities;
  }

}
