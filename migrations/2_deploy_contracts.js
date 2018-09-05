const jsonfile = require('jsonfile');

const BsktRegistry = artifacts.require('BsktRegistry');
const ERC20Token = artifacts.require('ERC20Token');
const Math = artifacts.require('Math');
const BidImpl = artifacts.require('BidImpl');
const RebalancingBsktToken = artifacts.require('RebalancingBsktToken');


const DEPLOYED_ADDRESSES_PATH = './build/deployed-addresses.json';

module.exports = (deployer, network, accounts) => {
  if (network == 'development') {
    let bsktRegistry, feeToken, rebalancingBsktToken;
    let tokenA, tokenB;
    let feeAmount = 10**17;

    deployer.then(() => {
      return deployer.deploy(Math);
    }).then(() => {
      return deployer.link(Math, [RebalancingBsktToken]);
    }).then(() => {
      return deployer.deploy(BidImpl);
    }).then(() => {
      return deployer.link(BidImpl, [RebalancingBsktToken]);
    }).then(() => {
      return ERC20Token.new();
    }).then(_feeToken => {
      feeToken = _feeToken;
      return ERC20Token.new();
    }).then((_tokenA) => {
      tokenA = _tokenA;
      return ERC20Token.new();
    }).then(_tokenB => {
      tokenB = _tokenB;
      return BsktRegistry.new(accounts[1], feeToken.address, feeAmount);
    }).then(_bsktRegistry => {
      bsktRegistry = _bsktRegistry;
      return bsktRegistry.batchSet([tokenA.address, tokenB.address], [100000, 200000]);
    }).then(_bsktRegistry => {
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
      return feeToken.mint(accounts[0], 100 * 10**18, { from: accounts[0] });
    }).then(() => {
      return feeToken.approve(bsktRegistry.address, 100 * 10**18, { from: accounts[0] });
    }).then(() => {
      let deployedAddresses = {
        'bsktRegistry': bsktRegistry.address,
        'feeToken': feeToken.address,
        'rebalancingBsktToken': rebalancingBsktToken.address,
        'tokenA': tokenA.address,
        'tokenB': tokenB.address
      };
      console.log('deployed addresses:', deployedAddresses);
      jsonfile.writeFileSync(DEPLOYED_ADDRESSES_PATH, deployedAddresses, {spaces: 2});
    })
  }
};
