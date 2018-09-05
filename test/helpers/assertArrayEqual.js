module.exports = function (expected, actual) {
  for (let i = 0; i < expected.length; i++) {
    assert.equal(expected[i], actual[i]);
  }
};
