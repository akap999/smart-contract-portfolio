interface ILazyMint1155 {
    function owner() external view returns (address);
    function lazyMint(address to, uint256 tokenId, uint256 amount) external;
}