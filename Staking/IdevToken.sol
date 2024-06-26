// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IdevToken {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function burn(address account, uint256 amount) external returns(bool);
    function mint(address account, uint256 amount) external returns(bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function getOwner() external view returns (address);
    function allowance(address owner, address spender) external view returns(uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address spender, address recipient, uint256 amount) external returns(bool);
    function increaseAllowance(address spender, uint256 amount) external returns (bool);
    function decreaseAllowance(address spender, uint256 amount) external returns (bool);

















}

