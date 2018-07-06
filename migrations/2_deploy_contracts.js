const BsktDataRegistry = artifacts.require('BsktDataRegistry');
const ERC20Token = artifacts.require('ERC20Token');
const Math = artifacts.require('Math');
const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');


module.exports = function(deployer, network) {
  if (network == 'development') {
    let bsktDataRegistry, token;


    deployer.then(function() {
      return deployer.deploy(Math);
    }).then(function() {
      return deployer.link(Math, [RebalancingBsktToken]);
    }).then(function() {
      return ERC20Token.new();
    }).then(function(_token) {
      token = _token;
      return BsktDataRegistry.new(token.address);
    }).then(function(_bsktDataRegistry) {
      bsktDataRegistry = _bsktDataRegistry;
      console.log('token address', token.address);
      return RebalancingBsktToken.new([token.address], [100], 'RebalancingBsktToken', 'RBT');
    });
  }
};
