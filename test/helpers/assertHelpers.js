const BigNumber = require('bignumber.js');


function assertBNEqual(actual, expected, message='') {
  const expectedBN = new BigNumber(expected);
  assert.isTrue(actual.eq(expectedBN), `expected: ${expectedBN.toString()}, actual: ${actual.toString()} ${message}`);
};

function assertArrayEqual(actual, expected, message='') {
  for (let i = 0; i < actual.length; i++) {
    assert.equal(actual[i], expected[i], message);
  }
};

function assertBNArrayEqual(actual, expected, message='') {
  for (let i = 0; i < actual.length; i++) {
    assertBNEqual(actual[i], expected[i], message);
  }
};

module.exports = {
  assertBNEqual: assertBNEqual,
  assertArrayEqual: assertArrayEqual,
  assertBNArrayEqual: assertBNArrayEqual
};
