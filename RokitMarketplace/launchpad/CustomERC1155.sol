pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import "./Royalties.sol";
import "./ILazyMint1155.sol";
import "./IRoyalties.sol";

contract CustomERC1155 is Royalties, ERC1155 {

    event UpdatedURI(
        string _uri
    );

    address public marketplaceAddress;

    modifier Lazy {
        require(msg.sender == marketplaceAddress, 'Unauthorized');
        _;
    }

    
    constructor(
        address owner_,
        address marketplaceAddress_,
        string memory uri_,
        uint256 royalty_
    )
        ERC1155(uri_)
    {
        globalRoyalty = royalty_;
        transferOwnership(owner_);
        royaltyReceiver = owner_;
        marketplaceAddress = marketplaceAddress_;
    }



    function setURI(string memory uri_) external onlyOwner {
        _setURI(uri_);

        emit UpdatedURI(
            uri_
        );
    }


    function mint(
        address account,
        uint256 id,
        uint256 amount
    ) external onlyOwner {
        _mint(account, id, amount,'0x');
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external onlyOwner {
        _mintBatch(to, ids, amounts,'0x');
    }


 
    function lazyMint(address to, uint256 tokenId, uint256 amount) external Lazy {
        _mint(to, tokenId, amount,'0x');
    }


    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, IERC165) returns (bool) {
        return
        interfaceId == type(IERC2981).interfaceId ||
        interfaceId == type(ILazyMint1155).interfaceId ||
        interfaceId == type(IRoyaltyDistribution).interfaceId ||
        super.supportsInterface(interfaceId);
    }

}
