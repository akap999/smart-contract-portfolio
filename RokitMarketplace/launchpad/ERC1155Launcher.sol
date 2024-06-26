pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";

//import './DeployersInterfaces.sol';
import './ERC1155Route.sol';

contract ERC1155Launcher is AccessControl{

    address public creator;
    bytes32 internal constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 internal constant CREATOR_ROLE = keccak256("CREATOR_ROLE");


   
    constructor(
        address _collectioncreator
    ){
        creator = _collectioncreator;
        _setupRole(CREATOR_ROLE, _collectioncreator);
        _setupRole(OWNER_ROLE, msg.sender);
    }


    
    function launch(
        address owner_,
        address marketplaceAddress_,
        string memory uri_,
        uint256 royalty_
    )
    external onlyRole(CREATOR_ROLE)
    returns(address)
    {
        return address(new ERC1155Route(
                owner_,
                marketplaceAddress_,
                uri_,
                royalty_
            ));
    }


    function setCreator(address _creator) external onlyRole(OWNER_ROLE){
        require (_creator != address(0), 'Cant accept 0 address');
        creator = _creator;
        grantRole(CREATOR_ROLE, _creator);
    }
}
