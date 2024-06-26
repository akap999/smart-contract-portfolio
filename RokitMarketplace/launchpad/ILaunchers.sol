pragma solidity ^0.8.0;

interface IERC721Launcher {
    function launch(
        address owner_,
        address marketplaceAddress_,
        string memory name_,
        string memory symbol_,
        string memory uri_,
        uint256 royalty_
    ) external returns(address);
}


interface IERC1155Launcher {
    function launch(
        address owner_,
        address marketplaceAddress_,
        string memory uri_,
        uint256 royalty_
    ) external returns(address);
}

