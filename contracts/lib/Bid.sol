pragma solidity 0.4.24;


library Bid {

  struct Bid {
    address bidder;
    address[] tokens;
    int256[] quantities;
  }

}
