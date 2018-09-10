pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import "./dYdX/TokenProxy.sol";


library ERC20TokenUtils {

  using SafeMath for uint256;

  // Modified to work with tokenProxy
  // It should not be possible to falsely report a frozen token
  function checkFrozen(address token, address tokenProxy) public returns (bool) {
    IERC20 erc20 = IERC20(token);
    uint256 allowanceAmount = erc20.allowance(msg.sender, tokenProxy);
    require(allowanceAmount >= 1);
    uint256 balanceStart = erc20.balanceOf(msg.sender);
    require(balanceStart >= 1);

    uint256 balanceFromBefore = erc20.balanceOf(msg.sender);
    uint256 balanceToBefore = erc20.balanceOf(this);
    bool isOk = tokenProxy.call(bytes4(keccak256("transferTokens(address,address,address,uint256)")), token, address(msg.sender), address(this), uint256(1));
    uint256 balanceFromAfter = erc20.balanceOf(msg.sender);
    uint256 balanceToAfter = erc20.balanceOf(this);
    bool isFrozen;
    if (isOk && balanceFromBefore.sub(balanceFromAfter) == 1 && balanceToAfter.sub(balanceToBefore) == 1) {
      // token is not paused
      isFrozen = false;
    } else if (!isOk && balanceFromBefore.sub(balanceFromAfter) == 0 && balanceToAfter.sub(balanceToBefore) == 0) {
      // token is paused
      isFrozen = true;
    } else {
      revert();
    }

    balanceFromBefore = erc20.balanceOf(this);
    balanceToBefore = erc20.balanceOf(msg.sender);
    isOk = token.call(bytes4(keccak256("transfer(address,uint256)")), address(msg.sender), uint256(1));
    balanceFromAfter = erc20.balanceOf(this);
    balanceToAfter = erc20.balanceOf(msg.sender);
    if (isOk && balanceFromBefore.sub(balanceFromAfter) == 1 && balanceToAfter.sub(balanceToBefore) == 1) {
      // token is not paused
      isFrozen = isFrozen || false;
    } else if (!isOk && balanceFromBefore.sub(balanceFromAfter) == 0 && balanceToAfter.sub(balanceToBefore) == 0) {
      // token is paused
      isFrozen = isFrozen || true;
    } else {
      revert();
    }

    uint256 balanceEnd = erc20.balanceOf(msg.sender);
    assert(balanceStart == balanceEnd);

    return isFrozen;
  } 

}
