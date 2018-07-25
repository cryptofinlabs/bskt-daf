const BsktRegistry = artifacts.require('BsktRegistry');
const ERC20Token = artifacts.require('ERC20Token');

const _ = require('underscore');
const BigNumber = require('bignumber.js');


contract('BsktRegistry', function(accounts) {

  // === HELPER FUNCTIONS ===

  // The order isn't kept by remove, so need helper to check
  function checkEntries(tokens, quantities, expectedTokens, expectedQuantities) {
    assert.equal(tokens.length, quantities.length, 'should have same length');
    assert.equal(tokens.length, expectedTokens.length, 'should have same length');
    assert.equal(tokens.length, expectedQuantities.length, 'should have same length');
    for (let i = 0; i < expectedTokens.length; i++) {
      const index = _.indexOf(tokens, expectedTokens[i]);
      assert.notEqual(index, -1, 'should contain token')
      assert.equal(quantities[index], expectedQuantities[i], 'should contain quantity at correct index')
    }
  }

  context('with fresh registry and zero fees', function() {
    let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    let feeAmount;
    let bsktRegistry;
    const owner = accounts[0];
    const dataManager = accounts[1];

    beforeEach(async function () {
      feeAmount = 0;
      feeToken = await ERC20Token.new({ from: owner });
      tokenA = await ERC20Token.new({ from: owner });
      tokenB = await ERC20Token.new({ from: owner });
      tokenC = await ERC20Token.new({ from: owner });
      tokenD = await ERC20Token.new({ from: owner });
      tokenE = await ERC20Token.new({ from: owner });
      bsktRegistry = await BsktRegistry.new(dataManager, feeToken.address, feeAmount, { from: dataManager });
    });

    it('should set first entry', async function() {
      await bsktRegistry.set(0, tokenA.address, 10, { from: dataManager });
      const tokens = await bsktRegistry.getTokens.call();
      const quantities = await bsktRegistry.getAllQuantities.call();
      assert.equal(tokens.length, 1, 'should be one entry');
      assert.equal(tokens.length, quantities.length, 'should have same length');
      assert.equal(tokens[0], tokenA.address, 'should be correct address');
      assert.equal(quantities[0], 10, 'should be correct quantity');
    });

    it('should get quantities', async function() {
      const quantities = await bsktRegistry.getQuantities.call([tokenA.address, tokenB.address]);
      // TODO: add assert chai for bignumber
      // (There's that library but it uses the bad should.be syntax)
      assert.isTrue(quantities[0].eq(new BigNumber(0)));
      assert.isTrue(quantities[1].eq(new BigNumber(0)));
    });

  });

  context('with populated registry and zero fees', function() {
    let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    let feeAmount;
    let bsktRegistry;
    let owner = accounts[0];
    let dataManager = accounts[1];
    let user1 = accounts[2];

    beforeEach(async function () {
      feeAmount = 0;
      feeToken = await ERC20Token.new({ from: owner });
      tokenA = await ERC20Token.new({ from: owner });
      tokenB = await ERC20Token.new({ from: owner });
      tokenC = await ERC20Token.new({ from: owner });
      tokenD = await ERC20Token.new({ from: owner });
      tokenE = await ERC20Token.new({ from: owner });
      bsktRegistry = await BsktRegistry.new(dataManager, feeToken.address, feeAmount, { from: dataManager });

      await bsktRegistry.set(0, tokenA.address, 10, { from: dataManager });
      await bsktRegistry.set(1, tokenB.address, 11091, { from: dataManager });
      await bsktRegistry.set(2, tokenC.address, 31124, { from: dataManager });
      await bsktRegistry.set(3, tokenD.address, 7962, { from: dataManager });
    });

    it('should overwrite existing entry', async function() {
      await bsktRegistry.set(3, tokenE.address, 581, { from: dataManager });
      const tokens = await bsktRegistry.getTokens.call();
      const quantities = await bsktRegistry.getAllQuantities.call();
      checkEntries(
        tokens,
        quantities,
        [tokenA.address, tokenB.address, tokenC.address, tokenE.address],
        [10, 11091, 31124, 581]
      );
    });

    it('should remove entry', async function() {
      await bsktRegistry.remove(tokenC.address, { from: dataManager });
      const tokens = await bsktRegistry.getTokens.call();
      const quantities = await bsktRegistry.getAllQuantities.call();
      checkEntries(
        tokens,
        quantities,
        [tokenA.address, tokenB.address, tokenD.address],
        [10, 11091, 7962]
      );
    });

    it('should remove first entry', async function() {
    });

    it('should remove all entries', async function() {
    });


    it('should get quantities', async function() {
      const quantities = await bsktRegistry.getQuantities.call([tokenD.address, tokenC.address, tokenB.address, tokenA.address]);
      assert.isTrue(quantities[0].eq(new BigNumber(7962)));
      assert.isTrue(quantities[1].eq(new BigNumber(31124)));
      assert.isTrue(quantities[2].eq(new BigNumber(11091)));
      assert.isTrue(quantities[3].eq(new BigNumber(10)));
    });

    it('should get quantities 2', async function() {
      const quantities = await bsktRegistry.getQuantities.call([tokenD.address, tokenB.address, tokenA.address]);
      assert.isTrue(quantities[0].eq(new BigNumber(7962)));
      assert.isTrue(quantities[1].eq(new BigNumber(11091)));
      assert.isTrue(quantities[2].eq(new BigNumber(10)));
    });

    it('should get quantities with tokens not in registry', async function() {
      const quantities = await bsktRegistry.getQuantities.call([tokenD.address, tokenB.address, tokenE.address]);
      assert.isTrue(quantities[0].eq(new BigNumber(7962)));
      assert.isTrue(quantities[1].eq(new BigNumber(11091)));
      assert.isTrue(quantities[2].eq(new BigNumber(0)));
    });

  });

  context('with fresh registry and fees', function() {
    let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    let feeAmount;
    let bsktRegistry;
    const owner = accounts[0];
    const dataManager = accounts[1];
    const user1 = accounts[2];

    beforeEach(async function () {
      feeAmount = 10**17;
      feeToken = await ERC20Token.new({ from: owner });
      tokenA = await ERC20Token.new({ from: owner });
      tokenB = await ERC20Token.new({ from: owner });
      tokenC = await ERC20Token.new({ from: owner });
      tokenD = await ERC20Token.new({ from: owner });
      tokenE = await ERC20Token.new({ from: owner });
      bsktRegistry = await BsktRegistry.new(dataManager, feeToken.address, feeAmount, { from: dataManager });

      await feeToken.mint(user1, 100*10**18, { from: owner });
      await feeToken.approve(bsktRegistry.address, 100*10**18, { from: user1 });
    });

    it('should charge fee for reading quantities', async function() {
      await bsktRegistry.set(0, tokenA.address, 10, { from: dataManager });
      const user1BalanceStartFeeToken = await feeToken.balanceOf.call(user1)
      const tokens = await bsktRegistry.getTokens.call({ from: user1 });
      await bsktRegistry.getQuantities(tokens, { from: user1 });
      const user1BalanceEndFeeToken = await feeToken.balanceOf.call(user1)
      const registryBalanceFeeToken = await feeToken.balanceOf.call(dataManager);

      assert.isTrue(user1BalanceStartFeeToken.minus(user1BalanceEndFeeToken).eq(feeAmount));
      assert.isTrue(registryBalanceFeeToken.eq(feeAmount));
    });

    it('should charge fee for reading all quantities', async function() {
      const user1BalanceStartFeeToken = await feeToken.balanceOf.call(user1)
      const tokens = await bsktRegistry.getTokens.call({ from: user1 });
      await bsktRegistry.getAllQuantities({ from: user1 });
      const user1BalanceEndFeeToken = await feeToken.balanceOf.call(user1)
      const registryBalanceFeeToken = await feeToken.balanceOf.call(dataManager);

      assert.isTrue(user1BalanceStartFeeToken.minus(user1BalanceEndFeeToken).eq(feeAmount));
      assert.isTrue(registryBalanceFeeToken.eq(feeAmount));
    });

    it('should fail when insufficient fees', async function() {
    });

  });

});
