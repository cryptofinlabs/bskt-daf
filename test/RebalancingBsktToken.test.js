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

    // TODO pull out common setup stuff
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

    it('should compare bids correctly', async function() {
      await setupRegistryStateA(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE)
      await setupRegistryStateB(dataManager, bsktRegistry, tokenA, tokenB, tokenC, tokenD, tokenE)
    });

  });

  context.only('with simple initial allocation and zero fees', function() {
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
        [tokenA.address, tokenB.address],
        [100, 100],
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

    it('should bid successfully for first bid', async function() {
      let creationSize = await rebalancingBsktToken.creationSize.call();
      await rebalancingBsktToken.issue(creationSize, { from: user1 });

      await bsktRegistry.set(0, tokenA.address, 50, { from: dataManager });
      await bsktRegistry.set(1, tokenC.address, 150, { from: dataManager });

      const bidTokens = [tokenA.address, tokenB.address, tokenC.address];
      const bidQuantities = [-50, -100, 150];
      await rebalancingBsktToken.bid(bidTokens, bidQuantities, { from: user1 });

      // Check escrow has correct amount
      let escrowBalanceA = await tokenA.balanceOf.call(escrow);
      let escrowBalanceB = await tokenB.balanceOf.call(escrow);
      let escrowBalanceC = await tokenC.balanceOf.call(escrow);
      assert.equal(escrowBalanceA, 0, 'escrow tokenA balance should be 0');
      assert.equal(escrowBalanceB, 0, 'escrow tokenB balance should be 0');
      assert.equal(escrowBalanceC, 150, 'escrow tokenC balance should be 150');

      // Check user1 has correct amount
      let user1BalanceA = await tokenA.balanceOf.call(user1);
      let user1BalanceB = await tokenB.balanceOf.call(user1);
      let user1BalanceC = await tokenC.balanceOf.call(user1);
      assert.equal(user1BalanceA, 100*10**18, 'user1 tokenA balance should be unchanged');
      assert.equal(user1BalanceB, 100*10**18, 'user1 tokenB balance should be unchanged');
      assert.equal(user1BalanceC, 100*10**18 - 150, 'user1 tokenB balance should be 150 less');

      // assert that bestBid is correct
    });

    it('should bid successfully for second bid', async function() {
    });

    it('should bid and rebalance correctly for perfect bid', async function() {
      // Starts at 100, 100
      let creationSize = await rebalancingBsktToken.creationSize.call();
      await rebalancingBsktToken.issue(creationSize, { from: user1 });

      await bsktRegistry.set(0, tokenA.address, 50, { from: dataManager });
      await bsktRegistry.set(1, tokenC.address, 150, { from: dataManager });

      const bidTokens = [tokenA.address, tokenB.address, tokenC.address];
      const bidQuantities = [-50, -100, 150];
      await rebalancingBsktToken.bid(bidTokens, bidQuantities, { from: user1 });

      await rebalancingBsktToken.rebalance({ from: user1 });

      const updatedTokens = await rebalancingBsktToken.getTokens.call();
      const updatedQuantities = await rebalancingBsktToken.getQuantities.call();
      //const [updatedTokens, updatedQuantities] = await rebalancingBsktToken.getCreationUnit.call();
      assert.equal(updatedTokens[0], tokenA.address);
      assert.equal(updatedTokens[1], tokenB.address);
      assert.equal(updatedTokens[2], tokenC.address);
      // TODO: helper to check arrays
      // helper to check arrays of BigNumber
      assert.equal(updatedQuantities[0].toNumber(), 50, 'rebalancingBsktToken quantities should be correct');
      assert.equal(updatedQuantities[1].toNumber(), 0, 'rebalancingBsktToken quantities should be correct');
      assert.equal(updatedQuantities[2].toNumber(), 150, 'rebalancingBsktToken quantities should be correct');

      const tokenABalance = await tokenA.balanceOf.call(rebalancingBsktToken.address);
      const tokenBBalance = await tokenB.balanceOf.call(rebalancingBsktToken.address);
      const tokenCBalance = await tokenC.balanceOf.call(rebalancingBsktToken.address);
      assert.equal(tokenABalance, 50, 'rebalancingBsktToken tokenA balance should be correct');
      assert.equal(tokenBBalance, 0, 'rebalancingBsktToken tokenB balance should be correct');
      assert.equal(tokenCBalance, 150, 'rebalancingBsktToken tokenC balance should be correct');

      // todo: add bidder account
      // todo check that bidder's resulting balance is ok
    });

    it('should bid and rebalance correctly for mediocre bid and multiple units', async function() {
      // Starts at 100, 100
      let creationSize = await rebalancingBsktToken.creationSize.call();
      await rebalancingBsktToken.issue(3*creationSize, { from: user1 });

      await bsktRegistry.set(0, tokenA.address, 50, { from: dataManager });
      await bsktRegistry.set(1, tokenC.address, 150, { from: dataManager });

      const bidTokens = [tokenA.address, tokenB.address, tokenC.address];
      const bidQuantities = [-30, -100, 75];
      await rebalancingBsktToken.bid(bidTokens, bidQuantities, { from: user1 });

      await rebalancingBsktToken.rebalance({ from: user1 });

      const updatedTokens = await rebalancingBsktToken.getTokens.call();
      const updatedQuantities = await rebalancingBsktToken.getQuantities.call();
      assert.equal(updatedTokens[0], tokenA.address);
      assert.equal(updatedTokens[1], tokenB.address);
      assert.equal(updatedTokens[2], tokenC.address);
      // TODO: helper to check arrays
      // helper to check arrays of BigNumber
      assert.equal(updatedQuantities[0].toNumber(), 70, 'rebalancingBsktToken quantities should be correct');
      assert.equal(updatedQuantities[1].toNumber(), 0, 'rebalancingBsktToken quantities should be correct');
      assert.equal(updatedQuantities[2].toNumber(), 75, 'rebalancingBsktToken quantities should be correct');

      const tokenABalance = await tokenA.balanceOf.call(rebalancingBsktToken.address);
      const tokenBBalance = await tokenB.balanceOf.call(rebalancingBsktToken.address);
      const tokenCBalance = await tokenC.balanceOf.call(rebalancingBsktToken.address);
      assert.equal(tokenABalance.toNumber(), 3*70, 'rebalancingBsktToken tokenA balance should be correct');
      assert.equal(tokenBBalance.toNumber(), 0, 'rebalancingBsktToken tokenB balance should be correct');
      assert.equal(tokenCBalance.toNumber(), 3*75, 'rebalancingBsktToken tokenC balance should be correct');

      // todo: add bidder account
      // todo check that bidder's resulting balance is ok
    });

    // issue, register, bid, rebalance, redeem
    it('should', async function() {
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

  //context('with realistic mid-lifecycle', function() {
    //let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    //let feeAmount;
    //let rebalancingBsktToken;
    //let bsktRegistry;
    //let escrow;
    //let owner = accounts[0];
    //let dataManager = accounts[1];
    //let user1 = accounts[2];

    //beforeEach(async function () {
      //feeAmount = 10**17;
      //feeToken = await ERC20Token.new({from: owner});
      //bsktRegistry = await BsktRegistry.new(dataManager, feeToken.address, feeAmount, {from: dataManager});
      //tokenA = await ERC20Token.new({ from: owner });
      //tokenB = await ERC20Token.new({ from: owner });
      //tokenC = await ERC20Token.new({ from: owner });
      //tokenD = await ERC20Token.new({ from: owner });
      //tokenE = await ERC20Token.new({ from: owner });

      //rebalancingBsktToken = await RebalancingBsktToken.new(
        //[tokenA.address, tokenB.address, tokenC.address, tokenD.address],
        //[100, 5000, 31200, 123013],
        //bsktRegistry.address,
        //'RebalancingBsktToken',
        //'RBT',
        //{from: owner}
      //);
      //escrow = await rebalancingBsktToken.escrow.call();

      //await tokenA.mint(user1, 100*10**18, { from: owner });
      //await tokenB.mint(user1, 100*10**18, { from: owner });
      //await tokenC.mint(user1, 100*10**18, { from: owner });
      //await tokenD.mint(user1, 100*10**18, { from: owner });
      //await tokenE.mint(user1, 100*10**18, { from: owner });

      //await tokenA.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      //await tokenB.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      //await tokenC.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      //await tokenD.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });
      //await tokenE.approve(rebalancingBsktToken.address, 100*10**18, { from: user1 });

       //await feeToken.mint(user1, 100*10**18, { from: owner });
      //// TODO add function to approve bsktRegistry from fund
      //// await feeToken.approve(bsktRegistry.address, 100*10**18, { from: rebalancingBsktToken });

      //let creationSize = await rebalancingBsktToken.creationSize.call();
      //await rebalancingBsktToken.issue(15*creationSize, { from: user1 });

      //await bsktRegistry.set(0, tokenA.address, 50, { from: dataManager });
      //await bsktRegistry.set(1, tokenC.address, 150, { from: dataManager });

      //const bidTokens = [tokenA.address, tokenB.address, tokenC.address];
      //const bidQuantities = [-30, -100, 75];
    //});

    //it('should bid and rebalance correctly for mediocre bid', async function() {
      //// Starts at 100, 100
      //let creationSize = await rebalancingBsktToken.creationSize.call();
      //await rebalancingBsktToken.issue(creationSize, { from: user1 });

      //await bsktRegistry.set(0, tokenA.address, 50, { from: dataManager });
      //await bsktRegistry.set(1, tokenC.address, 150, { from: dataManager });

      //const bidTokens = [tokenA.address, tokenB.address, tokenC.address];
      //const bidQuantities = [-30, -100, 75];
      //await rebalancingBsktToken.bid(bidTokens, bidQuantities, { from: user1 });

      //await rebalancingBsktToken.rebalance({ from: user1 });

      //const updatedTokens = await rebalancingBsktToken.getTokens.call();
      //const updatedQuantities = await rebalancingBsktToken.getQuantities.call();
      //assert.equal(updatedTokens[0], tokenA.address);
      //assert.equal(updatedTokens[1], tokenB.address);
      //assert.equal(updatedTokens[2], tokenC.address);
      //// TODO: helper to check arrays
      //// helper to check arrays of BigNumber
      //assert.equal(updatedQuantities[0].toNumber(), 70, 'rebalancingBsktToken quantities should be correct');
      //assert.equal(updatedQuantities[1].toNumber(), 0, 'rebalancingBsktToken quantities should be correct');
      //assert.equal(updatedQuantities[2].toNumber(), 75, 'rebalancingBsktToken quantities should be correct');

      //const tokenABalance = await tokenA.balanceOf.call(rebalancingBsktToken.address);
      //const tokenBBalance = await tokenB.balanceOf.call(rebalancingBsktToken.address);
      //const tokenCBalance = await tokenC.balanceOf.call(rebalancingBsktToken.address);
      //assert.equal(tokenABalance.toNumber(), 70, 'rebalancingBsktToken tokenA balance should be correct');
      //assert.equal(tokenBBalance.toNumber(), 0, 'rebalancingBsktToken tokenB balance should be correct');
      //assert.equal(tokenCBalance.toNumber(), 75, 'rebalancingBsktToken tokenC balance should be correct');

      //// todo: add bidder account
      //// todo check that bidder's resulting balance is ok
    //});

  //});

});
