pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import './ILaunchers.sol';
//import './I_NFT.sol';

 contract Launchpad is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    event ERC721Launched(
        address owner,
        string name,
        string symbol,
        string uri,
        uint256 royalty,
        address tokenAddress
    );

    event ERC1155Launched(
        address owner,
        string uri,
        uint256 royalty,
        address tokenAddress
    );

    address public marketplaceAddress;
    mapping(address => bool) public deployedTokenContract;

    IERC721Launcher ERC721Launcher;
    IERC1155Launcher ERC1155Launcher;


     /* This function is called before proxy upgrade and makes sure it is authorized.
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}


    /*
     * Function returns address of current implementation
     */
    function implementationAddress() external view returns (address){
        return _getImplementation();
    }

    
    
    function initialize() initializer public {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }


   function setAddresses(
        address _MarketplaceAddress,
        IERC721Launcher _ERC721Launcher,
        IERC1155Launcher _ERC1155Launcher
        )
    external
    onlyOwner
    {
        marketplaceAddress = _MarketplaceAddress;
        ERC721Launcher = _ERC721Launcher;
        ERC1155Launcher = _ERC1155Launcher;
    } 
   
   
    function launchERC721(
        string memory name_,
        string memory symbol_,
        string memory uri_,
        uint256 royalty_
    )
    external
    returns (address)
    {
        address collectionAddress =  ERC721Launcher.launch(
            msg.sender,
            marketplaceAddress,
            name_,
            symbol_,
            uri_,
            royalty_
        );
        deployedTokenContract[collectionAddress] = true;

        emit ERC721Launched(
            msg.sender,
            name_,
            symbol_,
            uri_,
            royalty_,
            collectionAddress
        );

        return collectionAddress;
    }
 
 function launchERC1155(
        string memory uri_,
        uint256 royalty_
    )
    external
    returns (address)
    {
        address collectionAddress =  ERC1155Launcher.launch(
            msg.sender,
            marketplaceAddress,
            uri_,
            royalty_
        );
        deployedTokenContract[collectionAddress] = true;

        emit ERC1155Launched(
            msg.sender,
            uri_,
            royalty_,
            collectionAddress
        );

        return collectionAddress;
    }
 
 
 
 
 
 }



