const BsktRegistry = artifacts.require('BsktRegistry');
const ERC20Token = artifacts.require('ERC20Token');
const Escrow = artifacts.require('Escrow');
const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');

const BigNumber = require('bignumber.js');


contract('RebalancingBsktToken', function(accounts) {

  async function setupRegistryStateA(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE) {
    await bsktRegistry.set(0, tokenA.address, 10, { from: dataManager });
    await bsktRegistry.set(1, tokenB.address, 10, { from: dataManager });
    await bsktRegistry.set(2, tokenC.address, 10, { from: dataManager });
    await bsktRegistry.set(3, tokenD.address, 10, { from: dataManager });
  }

  async function setupRegistryStateB(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE) {
    await bsktRegistry.set(0, tokenA.address, 0, { from: dataManager });
    await bsktRegistry.set(4, tokenE.address, 10, { from: dataManager });
  }

  context('with fresh RebalancingBsktToken', function() {
    let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    let rebalancingBsktToken;
    let bsktRegistry;
    let escrow;
    let owner = accounts[0];
    let dataManager = accounts[1];

    beforeEach(async function () {
      feeToken = await ERC20Token.new({from: owner});
      // TODO; mint and approve
      bsktRegistry = await BsktRegistry.new(dataManager, feeToken.address, {from: dataManager});
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
    });

    it('should get rebalance deltas', async function() {
      await setupRegistryStateA(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE);
      let [targetTokens, deltas] = await rebalancingBsktToken.getRebalanceDeltas.call();
      assert.equal(targetTokens[0], tokenA.address);
      assert.equal(targetTokens[1], tokenB.address);
      assert.equal(targetTokens[2], tokenC.address);
      assert.equal(targetTokens[3], tokenD.address);
      assert.isTrue(deltas[0].eq(new BigNumber(10)));
      assert.isTrue(deltas[1].eq(new BigNumber(10)));
      assert.isTrue(deltas[2].eq(new BigNumber(10)));
      assert.isTrue(deltas[3].eq(new BigNumber(10)));
    });


    it('should bid', async function() {
    });

    it('should compare bids correctly', async function() {
      await setupRegistryStateA(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE)
      await setupRegistryStateB(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE)
    });


  });

  context('with initial allocation', function() {
    let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    let rebalancingBsktToken;
    let bsktRegistry;
    let escrow;
    let owner = accounts[0];
    let dataManager = accounts[1];
    let user1 = accounts[2];

    beforeEach(async function () {
      feeToken = await ERC20Token.new({from: owner});
      bsktRegistry = await BsktRegistry.new(dataManager, feeToken.address, {from: dataManager});
      tokenA = await ERC20Token.new({ from: owner });
      tokenB = await ERC20Token.new({ from: owner });
      tokenC = await ERC20Token.new({ from: owner });
      tokenD = await ERC20Token.new({ from: owner });
      tokenE = await ERC20Token.new({ from: owner });

      rebalancingBsktToken = await RebalancingBsktToken.new(
        [tokenA.address, tokenB.address, tokenC.address, tokenD.address, tokenE.address],
        [1000, 10000, 31200, 123013, 100],
        bsktRegistry.address,
        'RebalancingBsktToken',
        'RBT',
        {from: owner}
      );

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
      let creationSize = await rebalancingBsktToken.creationSize.call();
      assert.equal(creationSize, 16, 'creationSize should be 16');
    });

    it('should issue', async function() {
      await rebalancingBsktToken.issue(10**16, { from: user1 });
      const user1Balance = await rebalancingBsktToken.balanceOf.call(user1);
      console.log('', user1Balance);
    });

    it('should get rebalance deltas', async function() {
      // TODO: issue to have some balance. this is a valid test tho
      await setupRegistryStateA(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE);
      let [targetTokens, deltas] = await rebalancingBsktToken.getRebalanceDeltas.call();
      console.log('targetTokens', targetTokens);
      console.log('deltas', deltas);
    });

  });

});
