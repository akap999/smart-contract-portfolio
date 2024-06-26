pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import "@openzeppelin/contracts/utils/Strings.sol";

import "./Royalties.sol";
import "./IRoyalties.sol";
import "./ILazyMint721.sol";

abstract contract CustomERC721 is Royalties, ERC721{
    using Strings for uint256;

    event UpdatedURI(
        string _uri
    );

    string private _uri;

    address public marketplaceAddress;

    modifier Lazy {
        require(msg.sender == marketplaceAddress, 'Unauthorized');
        _;
    }


    
    constructor(
        address owner_,
        address marketplaceAddress_,
        string memory name_,
        string memory symbol_,
        string memory uri_,
        uint256 royalty_
    )
        ERC721(name_, symbol_)
    {
        _uri = uri_;
        globalRoyalty = royalty_;
        transferOwnership(owner_);
        royaltyReceiver = owner_;
        marketplaceAddress = marketplaceAddress_;
    }


  
    function _baseURI() internal view virtual override returns (string memory) {
        return _uri;
    }


    function baseURI() external view returns (string memory) {
        return _baseURI();
    }


    function setURI(string memory uri_) external onlyOwner {
        _uri = uri_;

        emit UpdatedURI(
            uri_
        );
    }


    function mint(address to, uint256 tokenId) external onlyOwner {
        _safeMint(to, tokenId);
    }


    function lazyMint(address to, uint256 tokenId) external Lazy {
        _safeMint(to, tokenId);
    }

    function exists(uint256 tokenId) public view returns (bool){
        return _exists(tokenId);
    }


    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return
        interfaceId == type(IERC2981).interfaceId ||
        interfaceId == type(ILazyMint721).interfaceId ||
        interfaceId == type(IRoyaltyDistribution).interfaceId ||
        super.supportsInterface(interfaceId);
    }

}
