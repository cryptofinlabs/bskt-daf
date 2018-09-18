const BsktRegistry = artifacts.require('BsktRegistry');
const ERC20Token = artifacts.require('ERC20Token');
const Escrow = artifacts.require('Escrow');
const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');

const BigNumber = require('bignumber.js');
const _ = require('underscore');
const tempo = require('@digix/tempo')(web3);

const { assertBNEqual, assertArrayEqual, assertBNArrayEqual } = require('./helpers/assertHelpers.js');
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

// Helper to remove overhead in querying and checking balances
async function queryBalances(account, tokens) {
  return Promise.all(
    _.map(tokens, (token) => {
      return token.balanceOf.call(account);
    })
  );
}

// When using this to verify diffs, keep in mind that a decreasing token balance will be a negative value
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
  let rebalancePeriodStart = Math.floor(currentTime() / lifecycle.rebalancePeriod) * lifecycle.rebalancePeriod + lifecycle.periodOffset;

  // Actual opt out interval uses `now`, but this is the earliest interval start possible
  let optOutPeriodStart = rebalancePeriodStart;
  let optOutPeriodEnd = rebalancePeriodStart + lifecycle.optOutDuration;

  let auctionPeriodStart = rebalancePeriodStart + lifecycle.auctionOffset;
  let auctionPeriodEnd = auctionPeriodStart + lifecycle.auctionDuration;

  let settlePeriodStart = auctionPeriodEnd;
  let settlePeriodEnd = settlePeriodStart + lifecycle.settleDuration;

  let openPeriodStart = settlePeriodEnd;

  let delta;
  switch (period) {
    case 'OPT_OUT':
      delta = optOutPeriodStart - currentTime();
      if (delta > 0) {
        await tempo.wait(delta);
      }
      break;
    case 'AUCTION':
      delta = auctionPeriodStart - currentTime();
      if (delta > 0) {
        await tempo.wait(delta);
      }
      break;
    case 'REBALANCE':
      delta = settlePeriodStart - currentTime();
      if (delta > 0) {
        await tempo.wait(delta);
      }
      break;
    case 'OPEN':
      delta = openPeriodStart - currentTime();
      if (delta > 0) {
        await tempo.wait(delta);
      }
      break;
  }
}

// Moves to start of next period
async function waitForStartNextPeriod(lifecycle) {
  const rebalancePeriodNextStart = (Math.floor(currentTime() / lifecycle.rebalancePeriod) + 1) * lifecycle.rebalancePeriod;
  const delta = rebalancePeriodNextStart - currentTime();
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
    rebalancePeriod = 7 * 24 * 60 * 60,  // Roughly weekly
    periodOffset = 0,
    auctionOffset = 1 * 24 * 60 * 60,
    auctionDuration = 2 * 24 * 60 * 60,
    optOutDuration = 12 * 60 * 60,
    settleDuration = 1 * 24 * 60 * 60,
  ) {
    let state = {};
    const isFee = feeAmount !== 0;

    state.feeAmount = feeAmount;
    state.quantities = quantities;
    state.lifecycle = {
      rebalancePeriod,
      periodOffset,
      auctionOffset,
      auctionDuration,
      optOutDuration,
      settleDuration
    };

    state.owner = accounts[0];
    state.dataManager = accounts[1];
    state.user1 = accounts[2];  // user1 has tokens and approvals set up
    state.user2 = accounts[3];  // user2 has no tokens and no approvals set up
    state.bidder1 = accounts[4];  // bidder1 has tokens and approvals set up
    state.bidder2 = accounts[5];  // bidder2 has tokens and approvals set up

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
      rebalancePeriod,
      periodOffset,
      auctionOffset,
      auctionDuration,
      optOutDuration,
      settleDuration,
      'RebalancingBsktToken',
      'RBT',
      { from: state.owner }
    );
    state.escrow = await state.rebalancingBsktToken.escrow.call();
    state.tokenProxy = await state.rebalancingBsktToken.tokenProxy.call();

    if (isFee) {
      await state.feeToken.mint(state.user1, 100 * 10**18, { from: state.owner });
      await state.feeToken.mint(state.bidder1, 100 * 10**18, { from: state.owner });
      await state.feeToken.mint(state.bidder2, 100 * 10**18, { from: state.owner });
      await state.feeToken.approve(state.tokenProxy, 100 * 10**18, { from: state.user1 });
      await state.feeToken.approve(state.tokenProxy, 100 * 10**18, { from: state.bidder1 });
      await state.feeToken.approve(state.tokenProxy, 100 * 10**18, { from: state.bidder2 });
    }
    for (let i = 0; i < state.tokens.length; i++) {
      await state.tokens[i].mint(state.user1, 100 * 10**18, { from: state.owner });
      await state.tokens[i].mint(state.bidder1, 100 * 10**18, { from: state.owner });
      await state.tokens[i].mint(state.bidder2, 100 * 10**18, { from: state.owner });
      await state.tokens[i].approve(state.tokenProxy, 100 * 10**18, { from: state.user1 });
      await state.tokens[i].approve(state.tokenProxy, 100 * 10**18, { from: state.bidder1 });
      await state.tokens[i].approve(state.tokenProxy, 100 * 10**18, { from: state.bidder2 });
    }
    return state;
  }

  context.only('with simple initial allocation and zero fees', function() {
    let state;

    beforeEach(async function () {
      state = await setupRebalancingBsktToken(0, 2, [100, 100]);
    });

    it('should bid successfully for first bid', async function() {
      let creationSize = await state.rebalancingBsktToken.creationSize.call();
      await state.rebalancingBsktToken.issue(creationSize, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 50, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[2].address, 150, { from: state.dataManager });

      await state.rebalancingBsktToken.proposeRebalance({ from: state.user1 });

      const escrowBalancesStart = await queryBalances(state.escrow, state.tokens.slice(0, 3));
      const bidderBalancesStart = await queryBalances(state.bidder1, state.tokens.slice(0, 3));

      await moveToPeriod('AUCTION', state.lifecycle);
      await state.rebalancingBsktToken.bid(80, 100, { from: state.bidder1 });

      const escrowBalancesEnd = await queryBalances(state.escrow, state.tokens.slice(0, 3));
      const bidderBalancesEnd = await queryBalances(state.bidder1, state.tokens.slice(0, 3));

      const escrowBalancesDiff = computeBalancesDiff(escrowBalancesStart, escrowBalancesEnd);
      const bidderBalancesDiff = computeBalancesDiff(bidderBalancesStart, bidderBalancesEnd);

      assertBNArrayEqual(escrowBalancesDiff, [0, 0, 120], 'escrow balance diff should match');
      assertBNArrayEqual(bidderBalancesDiff, [0, 0, -120], 'bidder balance diff should match');

      const fundState = await state.rebalancingBsktToken.status.call();
      assert.equal(fundState, STATE.AUCTIONS_OPEN);
      // assert that bestBid is correct
    });

    it('should bid successfully for second bid', async function() {
      let creationSize = await state.rebalancingBsktToken.creationSize.call();
      await state.rebalancingBsktToken.issue(creationSize, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 50, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[2].address, 150, { from: state.dataManager });

      await state.rebalancingBsktToken.proposeRebalance({ from: state.user1 });

      const escrowBalancesStart = await queryBalances(state.escrow, state.tokens.slice(0, 3));
      const bidder1BalancesStart = await queryBalances(state.bidder1, state.tokens.slice(0, 3));
      const bidder2BalancesStart = await queryBalances(state.bidder2, state.tokens.slice(0, 3));

      await moveToPeriod('AUCTION', state.lifecycle);
      await state.rebalancingBsktToken.bid(80, 100, { from: state.bidder1 });
      await state.rebalancingBsktToken.bid(90, 100, { from: state.bidder2 });

      const escrowBalancesEnd = await queryBalances(state.escrow, state.tokens.slice(0, 3));
      const bidder1BalancesEnd = await queryBalances(state.bidder1, state.tokens.slice(0, 3));
      const bidder2BalancesEnd = await queryBalances(state.bidder2, state.tokens.slice(0, 3));

      const escrowBalancesDiff = computeBalancesDiff(escrowBalancesStart, escrowBalancesEnd);
      const bidder1BalancesDiff = computeBalancesDiff(bidder1BalancesStart, bidder1BalancesEnd);
      const bidder2BalancesDiff = computeBalancesDiff(bidder2BalancesStart, bidder2BalancesEnd);

      assertBNArrayEqual(escrowBalancesDiff, [0, 0, 135], 'escrow balance diff should match');
      assertBNArrayEqual(bidder1BalancesDiff, [0, 0, 0], 'bidder1 balance diff should match');
      assertBNArrayEqual(bidder2BalancesDiff, [0, 0, -135], 'bidder2 balance diff should match');

      const fundState = await state.rebalancingBsktToken.status.call();
      assert.equal(fundState, STATE.AUCTIONS_OPEN);
    });

    it('should bid and rebalance correctly for perfect bid', async function() {
      // Starts at 100, 100
      let creationSize = await state.rebalancingBsktToken.creationSize.call();
      await state.rebalancingBsktToken.issue(creationSize, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 50, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[2].address, 150, { from: state.dataManager });

      await state.rebalancingBsktToken.proposeRebalance({ from: state.user1 });

      const bidderBalancesStart = await queryBalances(state.bidder1, state.tokens.slice(0, 3));
      const fundBalancesStart = await queryBalances(state.rebalancingBsktToken.address, state.tokens.slice(0, 3));

      await moveToPeriod('AUCTION', state.lifecycle);
      await state.rebalancingBsktToken.bid(100, 100, { from: state.bidder1 });

      await moveToPeriod('REBALANCE', state.lifecycle);
      await state.rebalancingBsktToken.rebalance({ from: state.bidder1 });

      const bidderBalancesEnd = await queryBalances(state.bidder1, state.tokens.slice(0, 3));
      const fundBalancesEnd = await queryBalances(state.rebalancingBsktToken.address, state.tokens.slice(0, 3));

      const [updatedTokens, updatedQuantities] = await state.rebalancingBsktToken.creationUnit.call();

      // Order gets shuffled because of union implmentation
      assertArrayEqual(updatedTokens, [state.tokens[2].address, state.tokens[0].address], 'token addresses should be correct');
      assertBNArrayEqual(updatedQuantities, [150, 50], 'rebalancingBsktToken quantities should be correct');

      const bidderBalancesDiff = computeBalancesDiff(bidderBalancesStart, bidderBalancesEnd);
      const fundBalancesDiff = computeBalancesDiff(fundBalancesStart, fundBalancesEnd);

      assertBNArrayEqual(bidderBalancesDiff, [50, 100, -150], '');
      assertBNArrayEqual(fundBalancesDiff, [-50, -100, 150], '');
    });

    it('should bid and rebalance correctly for mediocre bid and multiple units', async function() {
      // Starts at 100, 100
      let creationSize = await state.rebalancingBsktToken.creationSize.call();
      await state.rebalancingBsktToken.issue(30 * creationSize, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 50, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[2].address, 150, { from: state.dataManager });

      await state.rebalancingBsktToken.proposeRebalance({ from: state.user1 });

      const bidderBalancesStart = await queryBalances(state.bidder1, state.tokens.slice(0, 3));
      const fundBalancesStart = await queryBalances(state.rebalancingBsktToken.address, state.tokens.slice(0, 3));

      await moveToPeriod('AUCTION', state.lifecycle);
      await state.rebalancingBsktToken.bid(30, 100, { from: state.bidder1 });

      await moveToPeriod('REBALANCE', state.lifecycle);
      await state.rebalancingBsktToken.rebalance({ from: state.bidder1 });

      const bidderBalancesEnd = await queryBalances(state.bidder1, state.tokens.slice(0, 3));
      const fundBalancesEnd = await queryBalances(state.rebalancingBsktToken.address, state.tokens.slice(0, 3));

      const [updatedTokens, updatedQuantities] = await state.rebalancingBsktToken.creationUnit.call();

      // Order gets shuffled because of union implmentation
      assertArrayEqual(updatedTokens, [state.tokens[2].address, state.tokens[0].address], 'token addresses should be correct');
      assertBNArrayEqual(updatedQuantities, [45, 15], 'rebalancingBsktToken quantities should be correct');

      const bidderBalancesDiff = computeBalancesDiff(bidderBalancesStart, bidderBalancesEnd);
      const fundBalancesDiff = computeBalancesDiff(fundBalancesStart, fundBalancesEnd);

      assertBNArrayEqual(bidderBalancesDiff, [2550, 3000, -1350], 'bidder balances differences should be correct');
      assertBNArrayEqual(fundBalancesDiff, [-2550, -3000, 1350], 'fund balances differences should be correct');
    });

    it('should issue, bid multiple times, rebalance, and redeem correctly', async function() {
      // Starts at 100, 100
      let creationSize = await state.rebalancingBsktToken.creationSize.call();
      await state.rebalancingBsktToken.issue(30 * creationSize, { from: state.user1 });

      await state.bsktRegistry.set(0, state.tokens[0].address, 50, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[2].address, 150, { from: state.dataManager });

      await state.rebalancingBsktToken.proposeRebalance({ from: state.user1 });

      await moveToPeriod('AUCTION', state.lifecycle);
      await state.rebalancingBsktToken.bid(25, 100, { from: state.bidder1 });
      await state.rebalancingBsktToken.bid(27, 100, { from: state.bidder2 });
      await state.rebalancingBsktToken.bid(30, 100, { from: state.bidder1 });

      await moveToPeriod('REBALANCE', state.lifecycle);
      await state.rebalancingBsktToken.rebalance({ from: state.bidder1 });

      const userBalancesStart = await queryBalances(state.user1, state.tokens.slice(0, 3));
      const fundBalancesStart = await queryBalances(state.rebalancingBsktToken.address, state.tokens.slice(0, 3));

      await moveToPeriod('OPEN', state.lifecycle);
      await state.rebalancingBsktToken.redeem(15 * creationSize, [], { from: state.user1 });

      const userBalancesEnd = await queryBalances(state.user1, state.tokens.slice(0, 3));
      const fundBalancesEnd = await queryBalances(state.rebalancingBsktToken.address, state.tokens.slice(0, 3));

      const userBalancesDiff = computeBalancesDiff(userBalancesStart, userBalancesEnd);
      const fundBalancesDiff = computeBalancesDiff(fundBalancesStart, fundBalancesEnd);

      assertBNArrayEqual(userBalancesDiff, [225, 0, 675]);
      assertBNArrayEqual(fundBalancesDiff, [-225, 0, -675]);
    });

    it('should not allow rebalance proposal with all zero quantities', async function() {
      await state.bsktRegistry.set(0, state.tokens[0].address, 0, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[2].address, 0, { from: state.dataManager });

      try {
        await state.rebalancingBsktToken.proposeRebalance({ from: state.user1 });
      } catch (e) {
        assertRevert(e);
      }
    });

  });

  context('with initial allocation and zero fees', function() {
    let state;

    beforeEach(async function () {
      state = await setupRebalancingBsktToken(0, 5, [100, 5000, 31200, 123013]);
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

    it('should compute bid quantities correctly with 100%', async function() {
      const bidQuantities = await state.rebalancingBsktToken.computeBidQuantities.call(
        100,
        100,
        [1000, 5000, 31200, 123013],
        [1500, 5000, 30000, 123013],
        { from: state.bidder1 }
      );
      const expectedBidQuantities = [500, 0, -1200, 0];
      assertBNArrayEqual(bidQuantities, expectedBidQuantities);
    });

    it('should compute bid quantities correctly with 70.2225%', async function() {
      const bidQuantities = await state.rebalancingBsktToken.computeBidQuantities.call(
        702225,
        1000000,
        [1000, 1000, 1000, 1000],
        [1500, 500, 1000, 1000],
        { from: state.bidder1 }
      );
      const expectedBidQuantities = [
        Math.floor(1053.3375 - 1000),
        Math.floor(351.1125 - 1000),
        Math.floor(702.225 - 1000),
        Math.floor(702.225 - 1000)
      ];
      assertBNArrayEqual(bidQuantities, expectedBidQuantities);
    });

    it('should compute bid quantities correctly with 130%', async function() {
      const bidQuantities = await state.rebalancingBsktToken.computeBidQuantities.call(
        130,
        100,
        [1000, 5000, 31200, 123013],
        [1500, 5000, 30000, 123013],
        { from: state.bidder1 }
      );
      const expectedBidQuantities = [950, 1500, 7800, 36903];
      assertBNArrayEqual(bidQuantities, expectedBidQuantities);
    });

    it('should bid and rebalance correctly', async function() {
      await state.bsktRegistry.set(1, state.tokens[0].address, 1500, { from: state.dataManager });
      await state.bsktRegistry.set(3, state.tokens[2].address, 30000, { from: state.dataManager });

      await state.rebalancingBsktToken.proposeRebalance({ from: state.user1 });

      await moveToPeriod('AUCTION', state.lifecycle);
      const bidder1BalanceStart = await queryBalances(state.bidder1, [state.tokens[0], state.tokens[1], state.tokens[2]]);
      const fundBalanceStart = await queryBalances(state.rebalancingBsktToken.address, [state.tokens[0], state.tokens[1], state.tokens[2]]);
      await state.rebalancingBsktToken.bid(100, 100, { from: state.bidder1 });

      await moveToPeriod('REBALANCE', state.lifecycle);
      await state.rebalancingBsktToken.rebalance({ from: state.bidder1 });
      const fundBalanceEnd = await queryBalances(state.rebalancingBsktToken.address, [state.tokens[0], state.tokens[1], state.tokens[2]]);
      const bidder1BalanceEnd = await queryBalances(state.bidder1, [state.tokens[0], state.tokens[1], state.tokens[2]]);

      const bidder1BalancesDiff = computeBalancesDiff(bidder1BalanceStart, bidder1BalanceEnd);
      const fundBalancesDiff = computeBalancesDiff(fundBalanceStart, fundBalanceEnd);
      assertBNEqual(bidder1BalancesDiff[0], -500, 'bidder state.tokens[0] should decrease by 500');
      assertBNEqual(fundBalancesDiff[0], 500, 'fund state.tokens[0] should increase by 500');
      assertBNEqual(bidder1BalancesDiff[2], 1200, 'bidder state.tokens[2] should increase by 1200');
      assertBNEqual(fundBalancesDiff[2], -1200, 'fund state.tokens[2] should decrease by 1200');
    });

    it('should bid and rebalance correctly for 80% bid', async function() {
      await state.bsktRegistry.set(1, state.tokens[0].address, 1500, { from: state.dataManager });
      await state.bsktRegistry.set(3, state.tokens[2].address, 30000, { from: state.dataManager });

      await state.rebalancingBsktToken.proposeRebalance({ from: state.user1 });

      await moveToPeriod('AUCTION', state.lifecycle);
      const bidder1BalanceStart = await queryBalances(state.bidder1, [state.tokens[0], state.tokens[1], state.tokens[2]]);
      const fundBalanceStart = await queryBalances(state.rebalancingBsktToken.address, [state.tokens[0], state.tokens[1], state.tokens[2]]);
      await state.rebalancingBsktToken.bid(80, 100, { from: state.bidder1 });

      await moveToPeriod('REBALANCE', state.lifecycle);
      await state.rebalancingBsktToken.rebalance({ from: state.bidder1 });
      const fundBalanceEnd = await queryBalances(state.rebalancingBsktToken.address, [state.tokens[0], state.tokens[1], state.tokens[2]]);
      const bidder1BalanceEnd = await queryBalances(state.bidder1, [state.tokens[0], state.tokens[1], state.tokens[2]]);

      const bidder1BalancesDiff = computeBalancesDiff(bidder1BalanceStart, bidder1BalanceEnd);
      const fundBalancesDiff = computeBalancesDiff(fundBalanceStart, fundBalanceEnd);
      assertBNEqual(bidder1BalancesDiff[0], -200, 'bidder state.tokens[0] should decrease by 500');
      assertBNEqual(fundBalancesDiff[0], 200, 'fund state.tokens[0] should increase by 500');
      assertBNEqual(bidder1BalancesDiff[2], 7200, 'bidder state.tokens[2] should increase by 1200');
      assertBNEqual(fundBalancesDiff[2], -7200, 'fund state.tokens[2] should decrease by 1200');
    });

    it('should propose rebalance correctly', async function() {
      await state.bsktRegistry.set(0, state.feeToken.address, 10**13 - 3141, { from: state.dataManager });
      await state.bsktRegistry.set(1, state.tokens[0].address, 100, { from: state.dataManager });
      await state.bsktRegistry.set(2, state.tokens[1].address, 6000, { from: state.dataManager });

      const dataManagerBalanceStart = await queryBalances(state.dataManager, [state.feeToken]);
      const fundBalanceStart = await queryBalances(state.rebalancingBsktToken.address, [state.feeToken]);

      await state.rebalancingBsktToken.proposeRebalance({ from: state.user1 });

      const dataManagerBalanceEnd = await queryBalances(state.dataManager, [state.feeToken]);
      const fundBalanceEnd = await queryBalances(state.rebalancingBsktToken.address, [state.feeToken]);
      const dataManagerBalancesDiff = computeBalancesDiff(dataManagerBalanceStart, dataManagerBalanceEnd);
      const fundBalancesDiff = computeBalancesDiff(fundBalanceStart, fundBalanceEnd);

      assert.isTrue(dataManagerBalancesDiff[0].eq(state.feeAmount), `balance diff should be ${state.feeAmount}`);
      assert.isTrue(fundBalancesDiff[0].eq(-state.feeAmount),  `balance diff should be ${-state.feeAmount}`);

      // Order is affected by union implementation
      const deltaTokens = await state.rebalancingBsktToken.getDeltaTokens.call();
      const targetQuantities = await state.rebalancingBsktToken.getTargetQuantities.call();
      const expectedDeltaTokens = [
        state.feeToken.address,
        state.tokens[0].address,
        state.tokens[1].address,
        state.tokens[2].address,
        state.tokens[3].address,
      ];
      const expectedTargetQuantities = [
        9999999996859,
        100,
        6000,
        31200,
        123013
      ];
      checkEntries(deltaTokens, targetQuantities, expectedDeltaTokens, expectedTargetQuantities);

      const fundState = await state.rebalancingBsktToken.status.call();
      assert.equal(fundState, STATE.OPT_OUT);
    });

    it('should fail for propose rebalance with not enough time left in period', async function() { await moveToPeriod('OPT_OUT', state.lifecycle);
      await tempo.wait(18 * 60 * 60);  // Move to time with not enough opt out duration left until auction
      try {
        await state.rebalancingBsktToken.proposeRebalance();
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

  context('freeze reporting', function() {
    let state;

    beforeEach(async function () {
      state = await setupRebalancingBsktToken(0, 2, [100, 100]);
      await state.tokens[0].mint(state.user2, 10**18, { from: state.owner });
      await state.tokens[0].approve(state.tokenProxy, 10**18, { from: state.user2 });
      await state.tokens[1].mint(state.user2, 10**18, { from: state.owner });
      await state.tokens[1].approve(state.tokenProxy, 10**18, { from: state.user2 });
    });

    it('should report frozen token correctly', async function() {
      await state.tokens[0].pause({ from: state.owner });
      await state.rebalancingBsktToken.reportFrozenToken(state.tokens[0].address, { from: state.user2 });
      const tokensToSkip = await state.rebalancingBsktToken.getTokensToSkip.call();
      assertArrayEqual(tokensToSkip, [state.tokens[0].address], 'reported frozen tokens should match');
    });

    it('should report multiple frozen token correctly', async function() {
      await state.tokens[0].pause({ from: state.owner });
      await state.tokens[1].pause({ from: state.owner });
      await state.rebalancingBsktToken.reportFrozenToken(state.tokens[0].address, { from: state.user2 });
      await state.rebalancingBsktToken.reportFrozenToken(state.tokens[1].address, { from: state.user2 });
      const tokensToSkip = await state.rebalancingBsktToken.getTokensToSkip.call();
      assertArrayEqual(tokensToSkip, [state.tokens[0].address, state.tokens[1].address], 'reported frozen tokens should match');
    });

    it('should report frozen, then unfrozen token correctly', async function() {
      await state.tokens[0].pause({ from: state.owner });
      await state.rebalancingBsktToken.reportFrozenToken(state.tokens[0].address, { from: state.user2 });
      await state.tokens[0].unpause({ from: state.owner });
      await state.rebalancingBsktToken.reportFrozenToken(state.tokens[0].address, { from: state.user2 });
      const tokensToSkip = await state.rebalancingBsktToken.getTokensToSkip.call();
      assertArrayEqual(tokensToSkip, [], 'reported frozen tokens should be empty');
    });

    it('should report frozen, then unfrozen token correctly after it has been removed from creation unit', async function() {
    });

    it('should not add falsely reported token to tokensToSkip', async function() {
      await state.rebalancingBsktToken.reportFrozenToken(state.tokens[0].address, { from: state.user2 });
      const tokensToSkip = await state.rebalancingBsktToken.getTokensToSkip.call();
      assertArrayEqual(tokensToSkip, [], 'reported frozen tokens should be empty');
    });

    it('should fail for reporting frozen token not in creation unit', async function() {
      try {
        await state.tokens[3].pause({ from: state.owner });
        await state.rebalancingBsktToken.reportFrozenToken(state.tokens[3].address, { from: state.user2 });
      } catch (e) {
        assertRevert(e);
      }
    });

    it('should fail if user balance is insufficient', async function() {
      try {
        await state.tokens[0].approve(state.rebalancingBsktToken.address, 10**18, { from: state.user2 });
        await state.rebalancingBsktToken.reportFrozenToken(state.tokens[0].address, { from: state.user2 });
      } catch (e) {
        assertRevert(e);
      }
    });

    it('should fail if approval amount is insufficient', async function() {
      try {
        await state.tokens[2].mint(state.user2, 10**18, { from: state.owner });
        await state.rebalancingBsktToken.reportFrozenToken(state.tokens[0].address, { from: state.user2 });
      } catch (e) {
        assertRevert(e);
      }
    });

    it('should skip frozen tokens for issue', async function() {
      await state.tokens[0].pause({ from: state.owner });
      await state.rebalancingBsktToken.reportFrozenToken(state.tokens[0].address, { from: state.user1 });

      const user1BalancesStart = await queryBalances(state.user1, state.tokens);
      await state.rebalancingBsktToken.issue(10**18, { from: state.user1 });
      const user1BalancesEnd = await queryBalances(state.user1, state.tokens);
      const user1BalancesDiff = computeBalancesDiff(user1BalancesStart, user1BalancesEnd);

      assertBNEqual(user1BalancesDiff[0], 0, 'no tokens[0] should be moved')
      assertBNEqual(user1BalancesDiff[1], -state.quantities[0], 'tokens[1] should be moved as usual');
    });

    it('should skip frozen tokens for redeem', async function() {
      await state.rebalancingBsktToken.issue(10**18, { from: state.user1 });
      await state.tokens[0].pause({ from: state.owner });
      await state.rebalancingBsktToken.reportFrozenToken(state.tokens[0].address, { from: state.user1 });

      const user1BalancesStart = await queryBalances(state.user1, state.tokens);
      await state.rebalancingBsktToken.redeem(10**18, [], { from: state.user1 });
      const user1BalancesEnd = await queryBalances(state.user1, state.tokens);
      const user1BalancesDiff = computeBalancesDiff(user1BalancesStart, user1BalancesEnd);

      assertBNEqual(user1BalancesDiff[0], 0, 'no tokens[0] should be moved')
      assertBNEqual(user1BalancesDiff[1], state.quantities[0], 'tokens[1] should be moved as usual');
    });

    it('should override tokensToSkip correctly', async function() {
      await state.rebalancingBsktToken.issue(10**18, { from: state.user1 });
      await state.tokens[0].pause({ from: state.owner });
      await state.rebalancingBsktToken.reportFrozenToken(state.tokens[0].address, { from: state.user1 });

      const user1BalancesStart = await queryBalances(state.user1, state.tokens);
      await state.rebalancingBsktToken.redeem(10**18, [state.tokens[0].address, state.tokens[1].address], { from: state.user1 });
      const user1BalancesEnd = await queryBalances(state.user1, state.tokens);
      const user1BalancesDiff = computeBalancesDiff(user1BalancesStart, user1BalancesEnd);

      assertBNEqual(user1BalancesDiff[0], 0, 'no tokens[0] should be moved')
      assertBNEqual(user1BalancesDiff[1], 0, 'no tokens[1] should be moved');
    });

  });

});
