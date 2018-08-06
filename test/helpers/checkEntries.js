// The order isn't kept by remove, so need helper to check
module.exports = function checkEntries(tokens, quantities, expectedTokens, expectedQuantities) {
  assert.equal(tokens.length, quantities.length, 'should have same length');
  assert.equal(tokens.length, expectedTokens.length, 'should have same length');
  assert.equal(tokens.length, expectedQuantities.length, 'should have same length');
  for (let i = 0; i < expectedTokens.length; i++) {
    const index = _.indexOf(tokens, expectedTokens[i]);
    assert.notEqual(index, -1, 'should contain token')
    assert.equal(quantities[index].toNumber(), expectedQuantities[i], 'should contain quantity at correct index')
  }
};
