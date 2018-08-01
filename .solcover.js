module.exports = {
  accounts: 10,
  //norpc: true,
  testCommand: 'truffle test --network coverage test/BsktRegistry.test.js test/RebalancingBsktToken.test.js',
  copyPackages: ['openzeppelin-solidity', 'cryptofin-solidity'],
  skipFiles: ['TestMath.sol']
};
