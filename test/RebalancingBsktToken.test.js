const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');
const ERC20Token = artifacts.require('ERC20Token');


contract('RebalancingBsktToken', function(accounts) {

  context('with', function() {
    let tokenA, tokenB, tokenC, tokenD, tokenE;
    let rebalancingBsktToken;

    beforeEach(async function () {
      tokenA = await ERC20Token.new({from: accounts[0]});
      tokenB = await ERC20Token.new({from: accounts[0]});
      tokenC = await ERC20Token.new({from: accounts[0]});
      tokenD = await ERC20Token.new({from: accounts[0]});
      tokenE = await ERC20Token.new({from: accounts[0]});
      rebalancingBsktToken = await RebalancingBsktToken.new(
        [tokenA.address, tokenB.address, tokenC.address, tokenD.address, tokenE.address],
        [1000, 10000, 31200, 123013, 100],
        'RebalancingBsktToken',
        'RBT',
        {from: accounts[0]}
      );
    });

    it('should correctly compute creationSize', async function() {
      let creationSize = await rebalancingBsktToken.creationSize.call();
      assert.equal(creationSize, 16, 'creationSize should be 16');
    });

  });

});
