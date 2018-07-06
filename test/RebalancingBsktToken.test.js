const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');
const ERC20Token = artifacts.require('ERC20Token');


contract('RebalancingBsktToken', function(accounts) {

  context('with', function() {
    let rebalancingBsktToken;

    beforeEach(async function () {
      token = await ERC20Token.new({from: accounts[0]});
      rebalancingBsktToken = await RebalancingBsktToken.new(
        [token.address],
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
