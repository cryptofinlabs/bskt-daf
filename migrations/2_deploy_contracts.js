const jsonfile = require('jsonfile');

const BsktRegistry = artifacts.require('BsktRegistry');
const ERC20Token = artifacts.require('ERC20Token');
const Math = artifacts.require('Math');
const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');


const DEPLOYED_ADDRESSES_PATH = './build/deployed-addresses.json';

module.exports = (deployer, network, accounts) => {
  if (network == 'development') {
    let bsktRegistry, feeToken, rebalancingBsktToken;
    let feeAmount = 10**17;

    deployer.then(() => {
      return deployer.deploy(Math);
    }).then(() => {
      return deployer.link(Math, [RebalancingBsktToken]);
    }).then(() => {
      return ERC20Token.new();
    }).then(_feeToken => {
      feeToken = _feeToken;
      return BsktRegistry.new(accounts[1], feeToken.address, feeAmount);
    }).then(_bsktRegistry => {
      bsktRegistry = _bsktRegistry;
      return RebalancingBsktToken.new(
        [feeToken.address],
        [100],
        10**18,
        bsktRegistry.address,
        7 * 24 * 60 * 60,
        0,
        24 * 60 * 60,
        3 * 24 * 60 * 60,
        12 * 60 * 60,
        24 * 60 * 60,
        'RebalancingBsktToken',
        'RBSKT'
      );
    }).then(_rebalancingBsktToken => {
      rebalancingBsktToken = _rebalancingBsktToken;
      let deployedAddresses = {
        'bsktRegistry': bsktRegistry.address,
        'feeToken': feeToken.address,
        'rebalancingBsktToken': rebalancingBsktToken.address
      };
      console.log('deployed addresses:', deployedAddresses);
      jsonfile.writeFileSync(DEPLOYED_ADDRESSES_PATH, deployedAddresses, {spaces: 2});
    })
  }
};
