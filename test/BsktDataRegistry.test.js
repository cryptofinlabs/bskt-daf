const BsktDataRegistry = artifacts.require('BsktDataRegistry');
const ERC20Token = artifacts.require('ERC20Token');


contract('BsktDataRegistry', function(accounts) {

  context('with', function() {
    let bsktDataRegistry, token;

    beforeEach(async function () {
      token = await ERC20Token.new({from: accounts[0]});
      bsktDataRegistry = await BsktDataRegistry.new([token.address], {from: accounts[0]})
    });

    it('should', async function() {
      assert.isTrue(true, 'true');
    });

  });

});
