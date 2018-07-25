const BsktRegistry = artifacts.require('BsktRegistry');
const ERC20Token = artifacts.require('ERC20Token');
const Escrow = artifacts.require('Escrow');
const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');

const BigNumber = require('bignumber.js');


contract('RebalancingBsktToken', function(accounts) {

  async function setupRegistryStateA(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE) {
    await bsktRegistry.set(0, tokenA.address, 100, { from: dataManager });
    await bsktRegistry.set(1, tokenB.address, 100, { from: dataManager });
    await bsktRegistry.set(2, tokenC.address, 100, { from: dataManager });
    await bsktRegistry.set(3, tokenD.address, 100, { from: dataManager });
    await bsktRegistry.set(4, tokenE.address, 100, { from: dataManager });
  }

  async function setupRegistryStateB(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE) {
    await bsktRegistry.set(0, tokenA.address, 0, { from: dataManager });
    await bsktRegistry.set(4, tokenE.address, 10, { from: dataManager });
  }

  context('with fresh RebalancingBsktToken and zero fees', function() {
    let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    let feeAmount;
    let rebalancingBsktToken;
    let bsktRegistry;
    let escrow;
    const owner = accounts[0];
    const dataManager = accounts[1];
    const user1 = accounts[2];

    beforeEach(async function () {
      feeAmount = 0;
      feeToken = await ERC20Token.new({from: owner});
      // TODO; mint and approve
      bsktRegistry = await BsktRegistry.new(dataManager, feeToken.address, feeAmount, {from: dataManager});
      tokenA = await ERC20Token.new({ from: owner });
      tokenB = await ERC20Token.new({ from: owner });
      tokenC = await ERC20Token.new({ from: owner });
      tokenD = await ERC20Token.new({ from: owner });
      tokenE = await ERC20Token.new({ from: owner });
      rebalancingBsktToken = await RebalancingBsktToken.new(
        [],
        [],
        bsktRegistry.address,
        'RebalancingBsktToken',
        'RBT',
        {from: owner}
      );
      escrow = await rebalancingBsktToken.escrow.call();

      await tokenA.mint(user1, 100*10**18, { from: owner });
      await tokenB.mint(user1, 100*10**18, { from: owner });
      await tokenC.mint(user1, 100*10**18, { from: owner });
      await tokenD.mint(user1, 100*10**18, { from: owner });
      await tokenE.mint(user1, 100*10**18, { from: owner });

      await tokenA.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenB.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenC.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenD.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenE.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });

      await tokenA.approve(escrow, 100*10**18, { from: user1 });
      await tokenB.approve(escrow, 100*10**18, { from: user1 });
      await tokenC.approve(escrow, 100*10**18, { from: user1 });
      await tokenD.approve(escrow, 100*10**18, { from: user1 });
      await tokenE.approve(escrow, 100*10**18, { from: user1 });
    });

    it('should get rebalance deltas', async function() {
      await setupRegistryStateA(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE);
      let [targetTokens, deltas] = await rebalancingBsktToken.getRebalanceDeltas.call();
      assert.equal(targetTokens[0], tokenA.address);
      assert.equal(targetTokens[1], tokenB.address);
      assert.equal(targetTokens[2], tokenC.address);
      assert.equal(targetTokens[3], tokenD.address);
      assert.isTrue(deltas[0].eq(new BigNumber(100)));
      assert.isTrue(deltas[1].eq(new BigNumber(100)));
      assert.isTrue(deltas[2].eq(new BigNumber(100)));
      assert.isTrue(deltas[3].eq(new BigNumber(100)));
    });


    it('should bid', async function() {
      await bsktRegistry.set(0, tokenA.address, 100, { from: dataManager });
      await bsktRegistry.set(1, tokenB.address, 100, { from: dataManager });

      await rebalancingBsktToken.rebalance();
      let creationSize = await rebalancingBsktToken.creationSize.call();
      await rebalancingBsktToken.issue(creationSize, { from: user1 });

      await bsktRegistry.set(0, tokenA.address, 50, { from: dataManager });
      await bsktRegistry.set(1, tokenC.address, 150, { from: dataManager });

      const tokens = [tokenA.address, tokenB.address, tokenC.address];
      const quantities = [-50, -100, 150];
      await rebalancingBsktToken.bid(tokens, quantities, { from: user1 });

      // Check escrow has correct amount
      let escrowBalanceA = await tokenA.balanceOf.call(escrow);
      let escrowBalanceB = await tokenB.balanceOf.call(escrow);
      let escrowBalanceC = await tokenC.balanceOf.call(escrow);
      assert.equal(escrowBalanceA, 0, 'escrow balance tokenA should be 0');
      assert.equal(escrowBalanceB, 0, 'escrow balance tokenB should be 0');
      assert.equal(escrowBalanceC, 150, 'escrow balance tokenC should be 150');

      // Check user1 has correct amount
      let user1BalanceA = await tokenA.balanceOf.call(user1);
      let user1BalanceB = await tokenB.balanceOf.call(user1);
      let user1BalanceC = await tokenC.balanceOf.call(user1);
      assert.equal(user1BalanceA, 100*10**18, 'user1 balance tokenA should be unchanged');
      assert.equal(user1BalanceB, 100*10**18, 'user1 balance tokenB should be unchanged');
      assert.equal(user1BalanceC, 100*10**18 - 150, 'user1 balance tokenB should be 150 less');
    });

    it('should compare bids correctly', async function() {
      await setupRegistryStateA(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE)
      await setupRegistryStateB(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE)
    });

  });

  context('with initial allocation and zero fees', function() {
    let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    let feeAmount;
    let rebalancingBsktToken;
    let bsktRegistry;
    let escrow;
    const owner = accounts[0];
    const dataManager = accounts[1];
    const user1 = accounts[2];

    beforeEach(async function () {
      feeAmount = 0;
      feeToken = await ERC20Token.new({from: owner});
      bsktRegistry = await BsktRegistry.new(dataManager, feeToken.address, feeAmount, {from: dataManager});
      tokenA = await ERC20Token.new({ from: owner });
      tokenB = await ERC20Token.new({ from: owner });
      tokenC = await ERC20Token.new({ from: owner });
      tokenD = await ERC20Token.new({ from: owner });
      tokenE = await ERC20Token.new({ from: owner });

      rebalancingBsktToken = await RebalancingBsktToken.new(
        [tokenA.address, tokenB.address, tokenC.address, tokenD.address],
        [100, 5000, 31200, 123013],
        bsktRegistry.address,
        'RebalancingBsktToken',
        'RBT',
        {from: owner}
      );
      escrow = await rebalancingBsktToken.escrow.call();

      await tokenA.mint(user1, 100*10**18, { from: owner });
      await tokenB.mint(user1, 100*10**18, { from: owner });
      await tokenC.mint(user1, 100*10**18, { from: owner });
      await tokenD.mint(user1, 100*10**18, { from: owner });
      await tokenE.mint(user1, 100*10**18, { from: owner });

      await tokenA.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenB.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenC.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenD.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenE.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
    });

    it('should correctly compute creationSize', async function() {
      const creationSize = await rebalancingBsktToken.creationSize.call();
      assert.equal(creationSize, 10**16, 'creationSize should be 1e16');
    });

    it('should issue', async function() {
      await rebalancingBsktToken.issue(10**16, { from: user1 });
      const user1Balance = await rebalancingBsktToken.balanceOf.call(user1);
      console.log('', user1Balance);
    });

    it('should get rebalance deltas', async function() {
      await setupRegistryStateA(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE);
      let [targetTokens, deltas] = await rebalancingBsktToken.getRebalanceDeltas.call();
      console.log('targetTokens', targetTokens);
      console.log('deltas', deltas);
      console.log('delta', deltas[0].toNumber());
      console.log('delta', deltas[1].toNumber());
      console.log('delta', deltas[2].toNumber());
      console.log('delta', deltas[3].toNumber());
      console.log('delta', deltas[4].toNumber());
    });

    it('should get rebalance deltas for Bskt with some balances', async function() {
      await rebalancingBsktToken.issue(10**16, { from: user1 });
      await setupRegistryStateA(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE);
      let [targetTokens, deltas] = await rebalancingBsktToken.getRebalanceDeltas.call();
      console.log('targetTokens', targetTokens);
      console.log('deltas', deltas);
      console.log('delta', deltas[0].toNumber());
      console.log('delta', deltas[1].toNumber());
      console.log('delta', deltas[2].toNumber());
      console.log('delta', deltas[3].toNumber());
      console.log('delta', deltas[4].toNumber());
    });

    it('should bid', async function() {
    });

  });

  context('with initial allocation and fees', function() {
    let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    let feeAmount;
    let rebalancingBsktToken;
    let bsktRegistry;
    let escrow;
    let owner = accounts[0];
    let dataManager = accounts[1];
    let user1 = accounts[2];

    beforeEach(async function () {
      feeAmount = 10**17;
      feeToken = await ERC20Token.new({from: owner});
      bsktRegistry = await BsktRegistry.new(dataManager, feeToken.address, feeAmount, {from: dataManager});
      tokenA = await ERC20Token.new({ from: owner });
      tokenB = await ERC20Token.new({ from: owner });
      tokenC = await ERC20Token.new({ from: owner });
      tokenD = await ERC20Token.new({ from: owner });
      tokenE = await ERC20Token.new({ from: owner });

      rebalancingBsktToken = await RebalancingBsktToken.new(
        [tokenA.address, tokenB.address, tokenC.address, tokenD.address],
        [100, 5000, 31200, 123013],
        bsktRegistry.address,
        'RebalancingBsktToken',
        'RBT',
        {from: owner}
      );
      escrow = await rebalancingBsktToken.escrow.call();

      await tokenA.mint(user1, 100*10**18, { from: owner });
      await tokenB.mint(user1, 100*10**18, { from: owner });
      await tokenC.mint(user1, 100*10**18, { from: owner });
      await tokenD.mint(user1, 100*10**18, { from: owner });
      await tokenE.mint(user1, 100*10**18, { from: owner });

      await tokenA.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenB.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenC.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenD.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      await tokenE.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });

      // await feeToken.mint(user1, 100*10**18, { from: owner });
      // TODO add function to approve bsktRegistry from fund
      // await feeToken.approve(bsktRegistry.address, 100*10**18, { from: rebalancingBsktToken });
    });

    it('should', async function() {
    });

  });

});
