const BsktRegistry = artifacts.require('BsktRegistry');
const ERC20Token = artifacts.require('ERC20Token');
const Escrow = artifacts.require('Escrow');
const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');

const BigNumber = require('bignumber.js');
const _ = require('underscore');
const tempo = require('@digix/tempo')(web3);

const assertRevert = require('./helpers/assertRevert.js');
const checkEntries = require('./helpers/checkEntries.js');


const STATE = Object.freeze({
  'OPT_OUT': 0,
  'AUCTIONS_OPEN': 1,
  'OPEN': 2,
});
const NATURAL_UNIT = 10**18;
const HOUR = 60 * 60;
const DAY = 24 * HOUR;


// === HELPER FUNCTIONS ===

async function queryBalances(account, tokens) {
  return Promise.all(
    _.map(tokens, (token) => {
      return token.balanceOf.call(account);
    })
  );
}

function computeBalancesDiff(balancesStart, balancesEnd) {
  return _.map(balancesEnd, (balanceEnd, i) => {
    return balanceEnd.minus(balancesStart[i]);
  });
}

function currentTime() {
  let latestBlock = web3.eth.getBlock('latest');
  return latestBlock.timestamp;
}

// Moves within current interval
async function moveToPeriod(
  period,
  lifecycle
) {
  let xIntervalStart = Math.floor(currentTime() / lifecycle.xInterval) * lifecycle.xInterval + lifecycle.xOffset;

  // Actual opt out interval uses `now`, but this is the earliest interval start possible
  let optOutIntervalStart = xIntervalStart;
  let optOutIntervalEnd = xIntervalStart + lifecycle.optOutDuration;

  let auctionIntervalStart = xIntervalStart + lifecycle.auctionOffset;
  let auctionIntervalEnd = auctionIntervalStart + lifecycle.auctionDuration;

  let rebalanceIntervalStart = auctionIntervalEnd;
  let rebalanceIntervalEnd = rebalanceIntervalStart + lifecycle.rebalanceDuration;

  let openIntervalStart = rebalanceIntervalEnd;

  let delta;
  switch (period) {
    case 'OPT_OUT':
      delta = optOutIntervalStart - currentTime();
      if (delta > 0) {
        await tempo.wait(delta);
      }
      break;
    case 'AUCTION':
      delta = auctionIntervalStart - currentTime();
      if (delta > 0) {
        await tempo.wait(delta);
      }
      break;
    case 'REBALANCE':
      delta = rebalanceIntervalStart - currentTime();
      if (delta > 0) {
        await tempo.wait(delta);
      }
      break;
  }
}

// Moves to start of next period
async function waitForStartNextPeriod(lifecycle) {
  const xIntervalNextStart = (Math.floor(currentTime() / lifecycle.xInterval) + 1) * lifecycle.xInterval;
  const delta = xIntervalNextStart - currentTime();
  if (delta > 0) {
    await tempo.wait(delta);
  }
}

// balances decorator?

// === TESTS ===

contract('RebalancingBsktToken', function(accounts) {

  // numTokens Number of tokens to deploy. This is different from
  // `quantities.length`, which are the token quantities to deploy with.
  async function setupRebalancingBsktToken(
    feeAmount,
    numTokens,
    quantities,
    xInterval = 7 * 24 * 60 * 60,  // Roughly weekly
    xOffset = 0,
    auctionOffset = 1 * 24 * 60 * 60,
    auctionDuration = 2 * 24 * 60 * 60,
    optOutDuration = 12 * 60 * 60,
    rebalanceDuration = 1 * 24 * 60 * 60,
  ) {
    let state = {};
    const isFee = feeAmount !== 0;

    state.feeAmount = feeAmount;
    state.quantities = quantities;
    state.lifecycle = {
      xInterval,
      xOffset,
      auctionOffset,
      auctionDuration,
      optOutDuration,
      rebalanceDuration
    };

    state.owner = accounts[0];
    state.dataManager = accounts[1];
    state.user1 = accounts[2];
    state.bidder1 = accounts[3];

    await waitForStartNextPeriod(state.lifecycle);

    state.feeToken = await ERC20Token.new({from: state.owner});
    state.bsktRegistry = await BsktRegistry.new(state.dataManager, state.feeToken.address, state.feeAmount, {from: state.dataManager});
    state.tokens = [];

    for (let i = 0; i < Math.max(5, numTokens); i++) {
      let token = await ERC20Token.new({ from: state.owner });
      state.tokens.push(token);
    }

    const tokenAddresses = _.pluck(state.tokens.slice(0, quantities.length), 'address');
    state.rebalancingBsktToken = await RebalancingBsktToken.new(
      isFee ? [state.feeToken.address].concat(tokenAddresses) : tokenAddresses,
      isFee ? [10**13].concat(quantities) : quantities,
      10**18,
      state.bsktRegistry.address,
      xInterval,
      xOffset,
      auctionOffset,
      auctionDuration,
      optOutDuration,
      rebalanceDuration,
      'RebalancingBsktToken',
      'RBT',
      { from: state.owner }
    );
    state.escrow = await state.rebalancingBsktToken.escrow.call();

    if (isFee) {
      await state.feeToken.mint(state.user1, 100 * 10**18, { from: state.owner });
      await state.feeToken.approve(state.rebalancingBsktToken.address, 100 * 10**18, { from: state.user1 });
      await state.feeToken.approve(state.escrow, 100 * 10**18, { from: state.bidder1 });
    }
    for (let i = 0; i < state.tokens.length; i++) {
      await state.tokens[i].mint(state.user1, 100 * 10**18, { from: state.owner });
      await state.tokens[i].mint(state.bidder1, 100 * 10**18, { from: state.owner });
      await state.tokens[i].approve(state.rebalancingBsktToken.address, 100 * 10**18, { from: state.user1 });
      await state.tokens[i].approve(state.escrow, 100 * 10**18, { from: state.bidder1 });
    }
    return state;
  }

  context('with fresh RebalancingBsktToken and zero fees', function() {
    let state;

    beforeEach(async function () {
      state = await setupRebalancingBsktToken(0, 2, [100, 100, 100, 100, 100]);
    });

    it('should get rebalance deltas', async function() {
      await state.rebalancingBsktToken.issue(10**18, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[1].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(2, state.tokens[2].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(3, state.tokens[3].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(4, state.tokens[4].address, 200, { from: state.dataManager });

      let [targetTokens, deltas] = await state.rebalancingBsktToken.getRebalanceDeltas.call();
      assert.equal(targetTokens[0], state.tokens[0].address);
      assert.equal(targetTokens[1], state.tokens[1].address);
      assert.equal(targetTokens[2], state.tokens[2].address);
      assert.equal(targetTokens[3], state.tokens[3].address);
      assert.isTrue(deltas[0].eq(new BigNumber(100)));
      assert.isTrue(deltas[1].eq(new BigNumber(100)));
      assert.isTrue(deltas[2].eq(new BigNumber(100)));
      assert.isTrue(deltas[3].eq(new BigNumber(100)));
    });

    it('should fail when getting rebalance deltas when total supply is 0', async function() {
      await state.bsktRegistry.set(0, state.tokens[0].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[1].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(2, state.tokens[2].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(3, state.tokens[3].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(4, state.tokens[4].address, 200, { from: state.dataManager });

      try {
        await state.rebalancingBsktToken.getRebalanceDeltas();
        assert.fail('should have reverted');
      } catch(e) {
        assertRevert(e);
      }
    });

  });

  context('bid comparison', function() {
    let state;

    beforeEach(async function () {
      state = await setupRebalancingBsktToken(0, 10, [100, 0, 100, 100, 100]);

      await state.rebalancingBsktToken.issue(NATURAL_UNIT, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[1].address, 0, { from: state.dataManager });
      await state.bsktRegistry.set(2, state.tokens[2].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(3, state.tokens[3].address, 200, { from: state.dataManager });
      await state.bsktRegistry.set(4, state.tokens[4].address, 200, { from: state.dataManager });

    });

    it('should compare bids correctly', async function() {
      const bid1 = {
        tokens: [
          state.tokens[0].address,
          state.tokens[2].address,
          state.tokens[3].address,
          state.tokens[4].address,
          state.tokens[1].address,
        ],
        deltas: [85, 85, 85, 85, 0]
      }
      const bid2 = {
        tokens: [
          state.tokens[0].address,
          state.tokens[2].address,
          state.tokens[3].address,
          state.tokens[4].address,
          state.tokens[1].address,
        ],
        deltas: [70, 70, 70, 70, 0]
      }
      await state.rebalancingBsktToken.commitDelta();

      const isBid1Better = await state.rebalancingBsktToken.compareBids.call(bid1.tokens, bid1.deltas, bid2.tokens, bid2.deltas);
      assert.equal(isBid1Better, true);
    });

    it('should compare bids correctly with slightly better bid', async function() {
      const bid1 = {
        tokens: [
          state.tokens[0].address,
          state.tokens[2].address,
          state.tokens[3].address,
          state.tokens[4].address,
          state.tokens[1].address,
        ],
        deltas: [70, 70, 70, 71, 0]
      }
      const bid2 = {
        tokens: [
          state.tokens[0].address,
          state.tokens[2].address,
          state.tokens[3].address,
          state.tokens[4].address,
          state.tokens[1].address,
        ],
        deltas: [70, 70, 70, 70, 0]
      }
      await state.rebalancingBsktToken.commitDelta();

      const isBid1Better = await state.rebalancingBsktToken.compareBids.call(bid1.tokens, bid1.deltas, bid2.tokens, bid2.deltas);
      assert.equal(isBid1Better, true);
    });

    it('should compare bids correctly with non-greedy bid', async function() {
      await state.bsktRegistry.set(2, state.tokens[2].address, 50, { from: state.dataManager });

      // Bid 1 is worse despite taking 30 rather than 30 of `state.token[2]`
      const bid1 = {
        tokens: [
          state.tokens[0].address,
          state.tokens[3].address,
          state.tokens[4].address,
          state.tokens[2].address,
          state.tokens[1].address,
        ],
        deltas: [69, 69, 69, -30, 0]
      }
      const bid2 = {
        tokens: [
          state.tokens[0].address,
          state.tokens[3].address,
          state.tokens[4].address,
          state.tokens[2].address,
          state.tokens[1].address,
        ],
        deltas: [70, 70, 70, -50, 0]
      }
      await state.rebalancingBsktToken.commitDelta();

      const isBid1Better = await state.rebalancingBsktToken.compareBids.call(bid1.tokens, bid1.deltas, bid2.tokens, bid2.deltas);
      assert.equal(isBid1Better, false);
    });

    it('should compare bids correctly with tie', async function() {
      const bid1 = {
        tokens: [
          state.tokens[0].address,
          state.tokens[2].address,
          state.tokens[3].address,
          state.tokens[4].address,
          state.tokens[1].address,
        ],
        deltas: [70, 70, 70, 70, 0]
      }
      const bid2 = {
        tokens: [
          state.tokens[0].address,
          state.tokens[2].address,
          state.tokens[3].address,
          state.tokens[4].address,
          state.tokens[1].address,
        ],
        deltas: [70, 70, 70, 70, 0]
      }
      await state.rebalancingBsktToken.commitDelta();

      const isBid1Better = await state.rebalancingBsktToken.compareBids.call(bid1.tokens, bid1.deltas, bid2.tokens, bid2.deltas);
      assert.equal(isBid1Better, false);
    });

  });

  context('with simple initial allocation and zero fees', function() {
    let state;

    beforeEach(async function () {
      state = await setupRebalancingBsktToken(0, 2, [100, 100]);
    });

    it('should bid successfully for first bid', async function() {
      let creationSize = await state.rebalancingBsktToken.creationSize.call();
      await state.rebalancingBsktToken.issue(creationSize, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 50, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[2].address, 150, { from: state.dataManager });

      await moveToPeriod('AUCTION', state.lifecycle);
      const bidTokens = [state.tokens[2].address, state.tokens[0].address, state.tokens[1].address];
      const bidQuantities = [150, -50, -100];
      await state.rebalancingBsktToken.bid(bidTokens, bidQuantities, { from: state.bidder1 });

      // Check state.escrow has correct amount
      let escrowBalanceA = await state.tokens[0].balanceOf.call(state.escrow);
      let escrowBalanceB = await state.tokens[1].balanceOf.call(state.escrow);
      let escrowBalanceC = await state.tokens[2].balanceOf.call(state.escrow);
      assert.equal(escrowBalanceA, 0, 'escrow state.tokens[0] balance should be 0');
      assert.equal(escrowBalanceB, 0, 'escrow state.tokens[1] balance should be 0');
      assert.equal(escrowBalanceC, 150, 'escrow state.tokens[2] balance should be 150');

      // Check state.bidder1 has correct amount
      let user1BalanceA = await state.tokens[0].balanceOf.call(state.bidder1);
      let user1BalanceB = await state.tokens[1].balanceOf.call(state.bidder1);
      let user1BalanceC = await state.tokens[2].balanceOf.call(state.bidder1);
      assert.equal(user1BalanceA, 100 * 10**18, 'user1 state.tokens[0] balance should be unchanged');
      assert.equal(user1BalanceB, 100 * 10**18, 'user1 state.tokens[1] balance should be unchanged');
      assert.equal(user1BalanceC, 100 * 10**18 - 150, 'user1 state.tokens[1] balance should be 150 less');

      const fundState = await state.rebalancingBsktToken.status.call();
      assert.equal(fundState, STATE.AUCTIONS_OPEN);
      // assert that bestBid is correct
    });

    it('should bid successfully for second bid', async function() {
    });

    it('should bid and rebalance correctly for perfect bid', async function() {
      // Starts at 100, 100
      let creationSize = await state.rebalancingBsktToken.creationSize.call();
      await state.rebalancingBsktToken.issue(creationSize, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 50, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[2].address, 150, { from: state.dataManager });

      const bidderBalancesStart = await queryBalances(state.bidder1, state.tokens);

      await moveToPeriod('AUCTION', state.lifecycle);
      const bidTokens = [state.tokens[2].address, state.tokens[0].address, state.tokens[1].address];
      const bidQuantities = [150, -50, -100];
      await state.rebalancingBsktToken.bid(bidTokens, bidQuantities, { from: state.bidder1 });

      await moveToPeriod('REBALANCE', state.lifecycle);
      await state.rebalancingBsktToken.rebalance({ from: state.bidder1 });

      const bidderBalancesEnd = await queryBalances(state.bidder1, state.tokens);

      const [updatedTokens, updatedQuantities] = await state.rebalancingBsktToken.creationUnit.call();

      // Order of tokens gets shuffled a bit
      assert.equal(updatedTokens[0], state.tokens[2].address);
      assert.equal(updatedTokens[1], state.tokens[0].address);
      assert.equal(updatedTokens[2], state.tokens[1].address);
      // TODO: helper to check arrays
      // helper to check arrays of BigNumber
      assert.equal(updatedQuantities[0].toNumber(), 150, 'rebalancingBsktToken quantities should be correct');
      assert.equal(updatedQuantities[1].toNumber(), 50, 'rebalancingBsktToken quantities should be correct');
      assert.equal(updatedQuantities[2].toNumber(), 0, 'rebalancingBsktToken quantities should be correct');

      const tokenABalance = await state.tokens[0].balanceOf.call(state.rebalancingBsktToken.address);
      const tokenBBalance = await state.tokens[1].balanceOf.call(state.rebalancingBsktToken.address);
      const tokenCBalance = await state.tokens[2].balanceOf.call(state.rebalancingBsktToken.address);
      assert.equal(tokenABalance, 50, 'rebalancingBsktToken state.tokens[0] balance should be correct');
      assert.equal(tokenBBalance, 0, 'rebalancingBsktToken state.tokens[1] balance should be correct');
      assert.equal(tokenCBalance, 150, 'rebalancingBsktToken state.tokens[2] balance should be correct');

      const bidderBalancesDiff = computeBalancesDiff(bidderBalancesStart, bidderBalancesEnd);
      assert.isTrue(bidderBalancesDiff[0].eq(50), 'bidderBalancesDiff[0] should be correct');
      assert.isTrue(bidderBalancesDiff[1].eq(100), 'bidderBalancesDiff[1] should be correct');
      assert.isTrue(bidderBalancesDiff[2].eq(-150), 'bidderBalancesDiff[2] should be correct');
    });

    // this test won't work anymore
    // need new bid comparison approach, preferrably doesn't involve sorting
    it('should bid and rebalance correctly for mediocre bid and multiple units', async function() {
      //// Starts at 100, 100
      //let creationSize = await state.rebalancingBsktToken.creationSize.call();
      //await state.rebalancingBsktToken.issue(3 * creationSize, { from: state.user1 });

      //await state.bsktRegistry.set(0, state.tokens[0].address, 50, { from: state.dataManager });
      //await state.bsktRegistry.set(1, state.tokens[2].address, 150, { from: state.dataManager });

      //const bidTokens = [state.tokens[0].address, state.tokens[2].address, state.tokens[1].address];
      //const bidQuantities = [-30, 75, -100];
      //await state.rebalancingBsktToken.bid(bidTokens, bidQuantities, { from: state.user1 });  // todo change to bidder1

      //await state.rebalancingBsktToken.rebalance({ from: state.user1 });

      //const updatedTokens = await state.rebalancingBsktToken.getTokens.call();
      //const updatedQuantities = await state.rebalancingBsktToken.getQuantities.call();
      //assert.equal(updatedTokens[0], state.tokens[0].address);
      //assert.equal(updatedTokens[1], state.tokens[1].address);
      //assert.equal(updatedTokens[2], state.tokens[2].address);
      //// TODO: helper to check arrays
      //// helper to check arrays of BigNumber
      //assert.equal(updatedQuantities[0].toNumber(), 70, 'rebalancingBsktToken quantities should be correct');
      //assert.equal(updatedQuantities[1].toNumber(), 0, 'rebalancingBsktToken quantities should be correct');
      //assert.equal(updatedQuantities[2].toNumber(), 75, 'rebalancingBsktToken quantities should be correct');

      //const tokenABalance = await state.tokens[0].balanceOf.call(state.rebalancingBsktToken.address);
      //const tokenBBalance = await state.tokens[1].balanceOf.call(state.rebalancingBsktToken.address);
      //const tokenCBalance = await state.tokens[2].balanceOf.call(state.rebalancingBsktToken.address);
      //assert.equal(tokenABalance.toNumber(), 3 * 70, 'rebalancingBsktToken state.tokens[0] balance should be correct');
      //assert.equal(tokenBBalance.toNumber(), 0, 'rebalancingBsktToken state.tokens[1] balance should be correct');
      //assert.equal(tokenCBalance.toNumber(), 3 * 75, 'rebalancingBsktToken state.tokens[2] balance should be correct');

      //// todo: add bidder account
      //// todo check that bidder's resulting balance is ok
    });

    // issue, register, bid, rebalance, redeem
    it('should', async function() {
    });

  });

  context('with initial allocation and zero fees', function() {
    let state;

    beforeEach(async function () {
      state = await setupRebalancingBsktToken(0, 5, [100, 5000, 31200, 123013]);
    });

    it('should correctly compute creationSize', async function() {
      //const creationSize = await state.rebalancingBsktToken.creationSize.call();
      //assert.equal(creationSize, 10**16, 'creationSize should be 1e16');
    });

    it('should issue', async function() {
      const userBalancesStart = await queryBalances(state.user1, state.tokens);
      const fundBalancesStart = await queryBalances(state.rebalancingBsktToken.address, state.tokens);

      await state.rebalancingBsktToken.issue(10**18, { from: state.user1 });

      const userBalancesEnd = await queryBalances(state.user1, state.tokens);
      const fundBalancesEnd = await queryBalances(state.rebalancingBsktToken.address, state.tokens);

      const userBalancesDiff = computeBalancesDiff(userBalancesStart, userBalancesEnd);
      const fundBalancesDiff = computeBalancesDiff(fundBalancesStart, fundBalancesEnd);

      assert.isTrue(userBalancesDiff[0].eq(-100));
      assert.isTrue(userBalancesDiff[1].eq(-5000));
      assert.isTrue(userBalancesDiff[2].eq(-31200));
      assert.isTrue(userBalancesDiff[3].eq(-123013));

      assert.isTrue(fundBalancesDiff[0].eq(100));
      assert.isTrue(fundBalancesDiff[1].eq(5000));
      assert.isTrue(fundBalancesDiff[2].eq(31200));
      assert.isTrue(fundBalancesDiff[3].eq(123013));

    });

    it('should get rebalance deltas', async function() {
      await state.rebalancingBsktToken.issue(10**18, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 100, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[1].address, 100, { from: state.dataManager });
      await state.bsktRegistry.set(2, state.tokens[2].address, 100, { from: state.dataManager });
      await state.bsktRegistry.set(3, state.tokens[3].address, 100, { from: state.dataManager });
      await state.bsktRegistry.set(4, state.tokens[4].address, 100, { from: state.dataManager });

      let [targetTokens, deltas] = await state.rebalancingBsktToken.getRebalanceDeltas.call();

      assert.equal(targetTokens[0], state.tokens[4].address);
      assert.equal(targetTokens[1], state.tokens[3].address);
      assert.equal(targetTokens[2], state.tokens[2].address);
      assert.equal(targetTokens[3], state.tokens[1].address);
      assert.equal(targetTokens[4], state.tokens[0].address);

      assert.isTrue(deltas[0].eq(100));
      assert.isTrue(deltas[1].eq(-122913));
      assert.isTrue(deltas[2].eq(-31100));
      assert.isTrue(deltas[3].eq(-4900));
      assert.isTrue(deltas[4].eq(0));
    });

    it('should get rebalance deltas for Bskt with more total supply', async function() {
      await state.rebalancingBsktToken.issue(10**20, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 100, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[1].address, 100, { from: state.dataManager });
      await state.bsktRegistry.set(2, state.tokens[2].address, 100, { from: state.dataManager });
      await state.bsktRegistry.set(3, state.tokens[3].address, 100, { from: state.dataManager });
      await state.bsktRegistry.set(4, state.tokens[4].address, 100, { from: state.dataManager });

      let [targetTokens, deltas] = await state.rebalancingBsktToken.getRebalanceDeltas.call();

      assert.equal(targetTokens[0], state.tokens[4].address);
      assert.equal(targetTokens[1], state.tokens[3].address);
      assert.equal(targetTokens[2], state.tokens[2].address);
      assert.equal(targetTokens[3], state.tokens[1].address);
      assert.equal(targetTokens[4], state.tokens[0].address);

      assert.isTrue(deltas[0].eq(100));
      assert.isTrue(deltas[1].eq(-122913));
      assert.isTrue(deltas[2].eq(-31100));
      assert.isTrue(deltas[3].eq(-4900));
      assert.isTrue(deltas[4].eq(0));
    });

    it('should bid', async function() {
    });

  });

  context('with initial allocation and fees', function() {
    let state;

    beforeEach(async function () {
      state = await setupRebalancingBsktToken(3141, 4, [1000, 5000, 31200, 123013]);
      await state.bsktRegistry.set(0, state.feeToken.address, 10**13, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[0].address, 1000, { from: state.dataManager });
      await state.bsktRegistry.set(2, state.tokens[1].address, 5000, { from: state.dataManager });
      await state.bsktRegistry.set(3, state.tokens[2].address, 31200, { from: state.dataManager });
      await state.bsktRegistry.set(4, state.tokens[3].address, 123013, { from: state.dataManager });
      let creationSize = await state.rebalancingBsktToken.creationSize.call();
      await state.rebalancingBsktToken.issue(creationSize, { from: state.user1 });
    });

    it('should get rebalance deltas', async function() {
    });

    it('should bid and rebalance correctly', async function() {
      await state.bsktRegistry.set(0, state.tokens[0].address, 10**13, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[0].address, 1500, { from: state.dataManager });
      await state.bsktRegistry.set(3, state.tokens[2].address, 30000, { from: state.dataManager });

      await moveToPeriod('AUCTION', state.lifecycle);
      const bidTokens = [state.tokens[0].address, state.tokens[2].address, state.feeToken.address, state.tokens[1].address, state.tokens[3].address, state.tokens[4].address];
      const bidQuantities = [500, -1200, 0, 0, 0, 0];
      await state.rebalancingBsktToken.bid(bidTokens, bidQuantities, { from: state.bidder1 });

      await moveToPeriod('REBALANCE', state.lifecycle);
      await state.rebalancingBsktToken.rebalance({ from: state.bidder1 });

      const tokenABalance = await state.tokens[0].balanceOf.call(state.rebalancingBsktToken.address);
      const tokenBBalance = await state.tokens[1].balanceOf.call(state.rebalancingBsktToken.address);
      const tokenCBalance = await state.tokens[2].balanceOf.call(state.rebalancingBsktToken.address);
      assert.equal(tokenABalance.toNumber(), 1500, 'rebalancingBsktToken state.tokens[0] balance should be correct');
      assert.equal(tokenCBalance.toNumber(), 30000, 'rebalancingBsktToken state.tokens[2] balance should be correct');

      // TODO: check bidder1 balances
    });

    // tries to withdraw 5000 when delta is only say, 500
    it('should fail if bid tries to take more than it should', async function() {
    });

    it('should commit delta', async function() {
      await state.bsktRegistry.set(0, state.feeToken.address, 10**13 - 3141, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[0].address, 100, { from: state.dataManager });
      await state.bsktRegistry.set(2, state.tokens[1].address, 6000, { from: state.dataManager });

      const dataManagerBalanceStart = await queryBalances(state.dataManager, [state.feeToken]);
      const fundBalanceStart = await queryBalances(state.rebalancingBsktToken.address, [state.feeToken]);

      await state.rebalancingBsktToken.commitDelta({ from: state.user1 });

      const dataManagerBalanceEnd = await queryBalances(state.dataManager, [state.feeToken]);
      const fundBalanceEnd = await queryBalances(state.rebalancingBsktToken.address, [state.feeToken]);
      const dataManagerBalanceDiff = computeBalancesDiff(dataManagerBalanceStart, dataManagerBalanceEnd);
      const fundBalanceDiff = computeBalancesDiff(fundBalanceStart, fundBalanceEnd);

      assert.isTrue(dataManagerBalanceDiff[0].eq(state.feeAmount), `balance diff should be ${state.feeAmount}`);
      assert.isTrue(fundBalanceDiff[0].eq(-state.feeAmount),  `balance diff should be ${-state.feeAmount}`);

      // Order is affected by union implementation and sepatatePositiveNegative
      const deltaTokens = await state.rebalancingBsktToken.getDeltaTokens.call();
      const deltaQuantities = await state.rebalancingBsktToken.getDeltaQuantities.call(); const expectedDeltaTokens = [
        state.tokens[1].address,
        state.tokens[3].address,
        state.tokens[3].address,
        state.tokens[0].address,
        state.feeToken.address,
      ];
      const expectedDeltaQuantities = [
        1000,
        0,
        0,
        -900,
        0
      ];
      checkEntries(deltaTokens, deltaQuantities, expectedDeltaTokens, expectedDeltaQuantities);

      const fundState = await state.rebalancingBsktToken.status.call();
      assert.equal(fundState, STATE.OPT_OUT);
    });

    it('should fail for commit delta with not enough time left in period', async function() {
      await moveToPeriod('OPT_OUT', state.lifecycle);
      await tempo.wait(18 * 60 * 60);  // Move to time with not enough opt out duration left until auction
      try {
        await state.rebalancingBsktToken.commitDelta();
        assert.fail('should have reverted')
      } catch(e) {
        assertRevert(e);
      }
    });

  });

  //context('with realistic mid-lifecycle', function() {

    //it('should bid and rebalance correctly for mediocre bid', async function() {
    //});

  //});

  context('helper functions', function() {
    let state;

    beforeEach(async function () {
      state = await setupRebalancingBsktToken(0, 2, [100, 100]);
    });

    it('should compute total units correctly', async function() {
      await state.rebalancingBsktToken.issue(10**21, { from: state.user1 });
      const totalUnits = await state.rebalancingBsktToken.totalUnits.call();
      assert.equal(totalUnits.toNumber(), 1000);
    });

  });

});
