pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IERC2981.sol";



abstract contract Royalties is Ownable, IERC2981{

    struct RoyaltyShare {
        address collaborator;
        uint256 share;
    }

    bool public globalRoyaltyEnabled = true;

    bool public royaltyDistributionEnabled = true;

    uint256 public globalRoyalty;
    mapping(uint256 => uint256) public tokenRoyalty;

    RoyaltyShare[] private defaultCollaboratorsRoyaltyShare;
    mapping(uint256 => RoyaltyShare[]) public tokenCollaboratorsRoyaltyShare;

    address public royaltyReceiver;




    function royaltyInfo
    (
        uint256 _tokenId,
        uint256 _salePrice
    )
    external
    view
    override
    returns (
        address receiver,
        uint256 royaltyAmount
    ){
        uint256 royaltyAmount;
        if(globalRoyaltyEnabled){
            if(tokenRoyalty[_tokenId] == 0){
                royaltyAmount = _salePrice * globalRoyalty / 10000;
            }else{
                royaltyAmount = _salePrice * tokenRoyalty[_tokenId] / 10000;
            }
        }else{
            royaltyAmount = 0;
        }
        return (royaltyReceiver, royaltyAmount);
    }


   
    function setRoyaltyReceiver (address newRoyaltyReceiver) external onlyOwner {
        require(newRoyaltyReceiver != address(0), 'Cant set 0 address');
        require(newRoyaltyReceiver != royaltyReceiver, 'This address is already a receiver');
        royaltyReceiver = newRoyaltyReceiver;
    }



    function setGlobalRoyalty (uint256 _royalty) external onlyOwner {
        require(_royalty <= 9000,'Royalty is over 90%');
        globalRoyalty = _royalty;
    }


  
    function setTokenRoyalty (uint256 _royalty, uint256 _tokenId) external onlyOwner {
        require(_royalty <= 9000,'Royalty is over 90%');
        tokenRoyalty[_tokenId] = _royalty;
    }


  
    function disableRoyalty() external onlyOwner {
        globalRoyaltyEnabled = false;
    }

    function enableRoyalty() external onlyOwner {
        globalRoyaltyEnabled = true;
    }

    function disableRoyaltyDistribution() external onlyOwner {
        royaltyDistributionEnabled = false;
    }

    function enableRoyaltyDistribution() external onlyOwner {
        royaltyDistributionEnabled = true;
    }


    function setDefaultRoyaltyDistribution(
        address[] calldata collaborators,
        uint256[] calldata shares
    ) external onlyOwner {
        require(collaborators.length == shares.length, 'Arrays dont match');

        uint256 totalShares = 0;
        for (uint i=0; i<shares.length; i++){
            totalShares += shares[i];
        }
        require(totalShares <= 10000, 'Total shares > 10000');


        delete defaultCollaboratorsRoyaltyShare;
        for (uint i=0; i<collaborators.length; i++){
            defaultCollaboratorsRoyaltyShare.push(RoyaltyShare({
            collaborator: collaborators[i],
            share: shares[i]
            }));
        }
    }


    function getDefaultRoyaltyDistribution()
    public
    view
    returns(RoyaltyShare[] memory)
    {
        return defaultCollaboratorsRoyaltyShare;
    }


   
    function setTokenRoyaltyDistribution(
        address[] calldata collaborators,
        uint256[] calldata shares,
        uint256 tokenId
    ) external onlyOwner {
        require(collaborators.length == shares.length, 'Arrays dont match');

        uint256 totalShares = 0;
        for (uint i=0; i<shares.length; i++){
            totalShares += shares[i];
        }
        require(totalShares <= 10000, 'Total shares > 10000');


        delete tokenCollaboratorsRoyaltyShare[tokenId];

        for (uint i=0; i<collaborators.length; i++){
            tokenCollaboratorsRoyaltyShare[tokenId].push(RoyaltyShare({
            collaborator: collaborators[i],
            share: shares[i]
            }));
        }
    }


    function getTokenRoyaltyDistribution(uint256 tokenId)
    public
    view
    returns(RoyaltyShare[] memory)
    {
        return tokenCollaboratorsRoyaltyShare[tokenId];
    }

}
