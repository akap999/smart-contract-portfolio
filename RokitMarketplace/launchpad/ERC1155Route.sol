pragma solidity ^0.8.0;

import "./CustomERC1155.sol";

contract ERC1155Route is CustomERC1155 {


    constructor(
        address owner_,
        address marketplaceAddress_,
        string memory uri_,
        uint256 royalty_
    )
        CustomERC1155(
            owner_,
            marketplaceAddress_,
            uri_,
            royalty_
        )
    {}

}
