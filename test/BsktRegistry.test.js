const BsktRegistry = artifacts.require('BsktRegistry');
const ERC20Token = artifacts.require('ERC20Token');

const _ = require('underscore');
const BigNumber = require('bignumber.js');

const assertRevert = require('./helpers/assertRevert.js');
const assertArrayEqual = require('./helpers/assertArrayEqual.js');
const checkEntries = require('./helpers/checkEntries.js');


contract('BsktRegistry', function(accounts) {

  // === HELPER FUNCTIONS ===

  context('with fresh registry and zero fees', function() {
    let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    let feeAmount;
    let bsktRegistry;
    const owner = accounts[0];
    const dataManager = accounts[1];
    const user1 = accounts[2];

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

    it('should get entry', async function() {
      const quantity = await bsktRegistry.get.call(tokenA.address, { from: user1 });
      assert.isTrue(quantity.eq(new BigNumber(0)));
    });

    it('should batch set', async function() {
      const targetTokens = [tokenA.address, tokenC.address, tokenB.address];
      const targetQuantities = [314, 159, 265];
      await bsktRegistry.batchSet(targetTokens, targetQuantities, { from: dataManager });
      const tokens = await bsktRegistry.getTokens.call();
      const quantities = await bsktRegistry.getAllQuantities.call();
      checkEntries(tokens, quantities, targetTokens, targetQuantities);
    });

    it('should withdraw tokens', async function() {
      // Consider scenario where tokens accidentally sent directly to registry contract
      await feeToken.mint(bsktRegistry.address, 10**18, { from: owner });
      const registryFeeTokenBalanceStart = await feeToken.balanceOf.call(bsktRegistry.address);
      const ownerFeeTokenBalanceStart = await feeToken.balanceOf.call(owner);
      await bsktRegistry.withdrawTokens(feeToken.address, 10**18, { from: dataManager });
      const registryFeeTokenBalanceEnd = await feeToken.balanceOf.call(bsktRegistry.address);
      const ownerFeeTokenBalanceEnd = await feeToken.balanceOf.call(dataManager);

      assert.isTrue(registryFeeTokenBalanceStart.minus(registryFeeTokenBalanceEnd).eq(10**18));
      assert.isTrue(ownerFeeTokenBalanceEnd.minus(ownerFeeTokenBalanceStart).eq(10**18));
    });

    it('should fail to withdraw tokens for non-owner', async function() {
      try {
        await feeToken.mint(bsktRegistry.address, 10**18, { from: owner });
        await bsktRegistry.withdrawTokens(feeToken.address, 10**18, { from: user1 });
      } catch(e) {
        assertRevert(e);
      }
    });

    it('should fail to withdraw tokens when insufficient balance', async function() {
      try {
        await feeToken.mint(bsktRegistry.address, 10**18, { from: owner });
        await bsktRegistry.withdrawTokens(feeToken.address, 100**18, { from: dataManager });
      } catch(e) {
        assertRevert(e);
      }
    });

    it('should set frozen', async function() {
      const targetTokens = [tokenA.address, tokenC.address, tokenB.address];
      const targetQuantities = [314, 159, 265];
      await bsktRegistry.batchSet(targetTokens, targetQuantities, { from: dataManager });

      const targetFrozenTokens = [
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000002'
      ];
      await bsktRegistry.setFrozen(targetFrozenTokens, { from: dataManager });
      const frozenTokens = await bsktRegistry.getFrozenTokens();
      assertArrayEqual(targetFrozenTokens, frozenTokens);
    });

    it('should set frozen should fail with length greater than number of tokens', async function() {
      const targetFrozenTokens = [
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000002'
      ];
      try {
        await bsktRegistry.setFrozen(targetFrozenTokens, { from: dataManager });
      } catch (e) {
        assertRevert(e);
      }
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
      const didRemove = await bsktRegistry.remove.call(tokenC.address, { from: dataManager });
      await bsktRegistry.remove(tokenC.address, { from: dataManager });
      const tokens = await bsktRegistry.getTokens.call();
      const quantities = await bsktRegistry.getAllQuantities.call();
      assert.equal(didRemove, true, 'should return true');
      checkEntries(
        tokens,
        quantities,
        [tokenA.address, tokenB.address, tokenD.address],
        [10, 11091, 7962]
      );
    });

    it('should fail to remove entry', async function() {
      const didRemove = await bsktRegistry.remove.call(tokenE.address, { from: dataManager });
      await bsktRegistry.remove(tokenE.address, { from: dataManager });
      const tokens = await bsktRegistry.getTokens.call();
      const quantities = await bsktRegistry.getAllQuantities.call();
      assert.equal(didRemove, false, 'should return false');
      checkEntries(
        tokens,
        quantities,
        [tokenA.address, tokenB.address, tokenC.address, tokenD.address],
        [10, 11091, 31124, 7962]
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

    it('should get entry', async function() {
      const quantity = await bsktRegistry.get.call(tokenC.address, { from: user1 });
      assert.isTrue(quantity.eq(new BigNumber(31124)));
    });

    it('should batch set and overwrite', async function() {
      const targetTokens = [tokenA.address, tokenC.address, tokenB.address];
      const targetQuantities = [314, 159, 265];
      await bsktRegistry.batchSet(targetTokens, targetQuantities, { from: dataManager });
      const tokens = await bsktRegistry.getTokens.call();
      const quantities = await bsktRegistry.getAllQuantities.call();
      checkEntries(tokens, quantities, targetTokens, targetQuantities);
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
      const user1BalanceStartFeeToken = await feeToken.balanceOf.call(user1);
      const tokens = await bsktRegistry.getTokens.call({ from: user1 });
      await bsktRegistry.getQuantities(tokens, { from: user1 });
      const user1BalanceEndFeeToken = await feeToken.balanceOf.call(user1)
      const registryBalanceFeeToken = await feeToken.balanceOf.call(dataManager);

      assert.isTrue(user1BalanceStartFeeToken.minus(user1BalanceEndFeeToken).eq(feeAmount));
      assert.isTrue(registryBalanceFeeToken.eq(feeAmount));
    });

    it('should charge fee for reading all quantities', async function() {
      const user1BalanceStartFeeToken = await feeToken.balanceOf.call(user1);
      const tokens = await bsktRegistry.getTokens.call({ from: user1 });
      await bsktRegistry.getAllQuantities({ from: user1 });
      const user1BalanceEndFeeToken = await feeToken.balanceOf.call(user1)
      const registryBalanceFeeToken = await feeToken.balanceOf.call(dataManager);

      assert.isTrue(user1BalanceStartFeeToken.minus(user1BalanceEndFeeToken).eq(feeAmount));
      assert.isTrue(registryBalanceFeeToken.eq(feeAmount));
    });

    it('should fail when insufficient fees', async function() {
    });

    it('should get entry and charge fee', async function() {
      const feeTokenBalanceStart = await feeToken.balanceOf.call(user1);
      await bsktRegistry.get(tokenA.address, { from: user1 });
      const feeTokenBalanceEnd = await feeToken.balanceOf.call(user1);
      assert.isTrue(feeTokenBalanceStart.minus(feeTokenBalanceEnd).eq(feeAmount), 'correct fee amount should be deducted');
    });

  });

});
