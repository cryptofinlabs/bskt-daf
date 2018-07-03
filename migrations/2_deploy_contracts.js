const BsktDataRegistry = artifacts.require('BsktDataRegistry');
const ERC20Token = artifacts.require('ERC20Token');

module.exports = function(deployer, network) {
  if (network == 'development') {
    deployer.then(function() {
      return ERC20Token.new();
    }).then(function(token) {
      return BsktDataRegistry.new(token.address);
    });
  }
};
