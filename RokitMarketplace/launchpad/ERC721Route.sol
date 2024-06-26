pragma solidity ^0.8.0;

import "./CustomERC721.sol";

contract ERC721Route is CustomERC721 {

    
    constructor(
        address owner_,
        address marketplaceAddress_,
        string memory name_,
        string memory symbol_,
        string memory uri_,
        uint256 royalty_
    )
    CustomERC721(
        owner_,
        marketplaceAddress_,
        name_,
        symbol_,
        uri_,
        royalty_
    )
    {}

}
