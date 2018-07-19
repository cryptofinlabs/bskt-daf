const BsktRegistry = artifacts.require('BsktRegistry');
const ERC20Token = artifacts.require('ERC20Token');
const Math = artifacts.require('Math');
const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');


module.exports = function(deployer, network, accounts) {
  if (network == 'development') {
    let bsktRegistry, token;


    deployer.then(function() {
      return deployer.deploy(Math);
    }).then(function() {
      return deployer.link(Math, [RebalancingBsktToken]);
    }).then(function() {
      return ERC20Token.new();
    }).then(function(_token) {
      token = _token;
      return BsktRegistry.new(accounts[1], token.address);
    });
    //.then(function(_bsktRegistry) {
      //bsktRegistry = _bsktRegistry;
      //console.log('token address', token.address);
      //return RebalancingBsktToken.new([token.address], [100], bsktRegistry, 'RebalancingBsktToken', 'RBT');
    //});
  }
};
