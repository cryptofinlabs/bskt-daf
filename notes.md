
## Notes
- Since Escrow ("proxy") requires approval anyway, maybe approval for issue/redeem should be there too.
- No fee for getTokens

## Documentation
### Auction
When bidding, the calls must be carefully constructed to pass in tokens in the required order. It must match the order specified in `getRebalanceDeltas()`.

### Tests
need to write assert.equal for bignumbers
use new web3 for truffle
figure out why sometimes returns number, sometimes bignumber figure out why can't use bignumber as input sometimes

#### Coverage
Must use modified UIntArrayUtils because of this: https://github.com/sc-forks/solidity-coverage/issues/263
linking issues with Math for RebalancingBsktToken and TestMath. Workaround for now is to move Math functions into contract, and not test TestMath

### Naming
- UIntArrayUtils implied 256? Be consistent with Rational as well.
- RebalancingBsktToken -> FundToken? just BsktToken?

### Design
Fees - beneficiary?
Vault?

logging

ensure that duplicate tokens in BsktRegistry won't cause attack vectors


Map with external math library didn't work
A

Re: Extensible to support different auction mechanisms
English auction vs Dutch auction are pretty different, especially in terms of implementation.
But consider ways of making it generalizable

As long as the BsktToken has a clearly defined interface that's always backwards-compatible, should be fine.
Even if it isn't, `bskt.js` and a BsktToken interface shim contract can be maintained

ERC20 + issue, redeem

tense for event names

what happens if you rebalance when no tokens have been issued?
  It should fail because of div by 0 (totalUnits) when updating quantities

## Fees
currently fund pays every time someone bids
how to restructure so the fund pays?
maybe take a snapshot of the registry internally, costing money
all bidding stuff has to happen after this

gonna use a state machine to track everything


add proxy so only one contract has to be approved

## Bugs
- If tokens are being sold, but are scattered throughout, it's impossible to get a sorted list
  - May have to sort on chain?
  - The current implementation has been modified to treat sales as 100% so it can still work with perfect bids
    - commented out requireSorted, so it'll just compare left to right based on whatever order the union gives
      - any overall better bid should still beat lesser bids

## Testing
May have to restart ganache-cli every time to reset timestamp
