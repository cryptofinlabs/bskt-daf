[![CircleCI](https://circleci.com/gh/cryptofinlabs/bskt-daf.svg?style=svg&circle-token=7995dda412f01e937103e630b5e8a021d5e29ba5)](https://circleci.com/gh/cryptofinlabs/bskt-daf)

<img src="./bskt-daf-logo.svg" alt="Bskt DAF Logo" width="150px">

# The Decentralized Autonomous Fund

tl;dr A trustless, self-rebalancing fund that holds one or more Ethereum ERC20 tokens


## Overview

The **Decentralized Autonomous Fund** (DAF) allows anyone to hold a cryptocurrency token that is
composed of underlying cryptocurrency tokens.

The key benefits of the DAF are that it:

- Represents many ERC20 tokens with a single ERC20 token
- Allows rebalacing, with easy entry and exit from the fund before rebalancing commences
- Connects to existing centralized and decentralized ERC20 exchanges

## How it Works

The DAF is divided into a *portfolio data component* and a *fund component*:

<img src="./images/bskt-overview-figure.png" alt="Bskt DAF overview" width="500px">

The *portfolio data component* allows one or more data managers to regularly select one or more
ERC20 tokens and their balances. In exchange for this oracle service, data managers receive fees to
read the oracle data on chain. Thie data manager can also be easily replaced by a community voting
mechanism, such as a [token curated registry](https://medium.com/@ilovebagels/token-curated-registries-1-0-61a232f8dac7) (TCR).

The *fund component* allows anyone to create/redeem fund tokens that reflect the portfolio data
component. To create means to exchange underlying tokens for the fund token. To redeem means to
exchange fund tokens for the underlying.

When changes are made to the composition in the *portfolio data component*, the *fund component*
will wait for a period of time ("opt out window") before beginning an auction to rebalance to the
new composition. During the opt out window, anyone holding fund tokens who disagrees can redeem to
exit the fund — or sell the fund tokens on exchanges.

For more details, see our [whitepaper](./whitepaper/Bskt%20Decentralized%20Autonomous%20Fund.pdf)

## Fund Lifecycle

The fund has three main stages:

1. **Idle**: In the idle state, anyone can create or redeem fund tokens for the underlying tokens
2. **Wait**: During the wait period, the *data component* is read — and the new composition is stored for the next rebalance; all fund token holders have the ability to redeem during this period if they disagree with the new composition
3. **Rebalance**: During the rebalance, an English auction is held to convert the existing collateral to the new collateral; at the end of the period, existing collateral is given to the auction winner, in exchange for the collateral that gets the fund closest to the new composition. During the rebalance, fund tokens cannot be created or redeemed. If no one submits a bid, the fund retains its existing tokens

## To Use

### Deployment


### Testing
```
npm install
npm run test
```

