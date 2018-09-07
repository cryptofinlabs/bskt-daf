module.exports = function (actual, expected, message='') {
  for (let i = 0; i < actual.length; i++) {
    assert.equal(actual[i], expected[i], message);
  }
};
