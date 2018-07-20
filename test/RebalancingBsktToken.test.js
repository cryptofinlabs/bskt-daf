const BsktRegistry = artifacts.require('BsktRegistry');
const ERC20Token = artifacts.require('ERC20Token');
const Escrow = artifacts.require('Escrow');
const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');


contract('RebalancingBsktToken', function(accounts) {

  context('with', function() {
    let feeToken, tokenA, tokenB, tokenC, tokenD, tokenE;
    let rebalancingBsktToken;
    let bsktRegistry;
    let escrow;
    let dataManager = accounts[1];

    beforeEach(async function () {
      feeToken = await ERC20Token.new({from: accounts[0]});
      bsktRegistry = await BsktRegistry.new(dataManager, feeToken.address, {from: accounts[0]});
      escrow = await Escrow.new();
      tokenA = await ERC20Token.new({from: accounts[0]});
      tokenB = await ERC20Token.new({from: accounts[0]});
      tokenC = await ERC20Token.new({from: accounts[0]});
      tokenD = await ERC20Token.new({from: accounts[0]});
      tokenE = await ERC20Token.new({from: accounts[0]});
      rebalancingBsktToken = await RebalancingBsktToken.new(
        [tokenA.address, tokenB.address, tokenC.address, tokenD.address, tokenE.address],
        [1000, 10000, 31200, 123013, 100],
        bsktRegistry.address,
        'RebalancingBsktToken',
        'RBT',
        {from: accounts[0]}
      );
    });

    it('should correctly compute creationSize', async function() {
      let creationSize = await rebalancingBsktToken.creationSize.call();
      assert.equal(creationSize, 16, 'creationSize should be 16');
    });

    it('should bid', async function() {
    });

  });

});
