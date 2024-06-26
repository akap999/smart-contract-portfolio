pragma solidity ^0.8.0;


interface ILazyMint721 {
    function exists(uint256 tokenId) external view returns (bool);
    function owner() external view returns (address);
    function lazyMint(address to, uint256 tokenId) external;
}