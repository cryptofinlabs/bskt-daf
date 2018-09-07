const BigNumber = require('bignumber.js');


module.exports = function (actual, expected, message='') {
  const expectedBN = new BigNumber(expected);
  assert.isTrue(actual.eq(expectedBN), `expected: ${expectedBN.toString()}, ${message} actual: ${actual.toString()}`);
};
