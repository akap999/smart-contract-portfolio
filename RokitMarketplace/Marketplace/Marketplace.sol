pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import './EIP712Upgradeable.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

import "../NFT/IERC2981.sol";
import "../NFT/IRoyalties.sol";
import "../NFT/ILazyMint721.sol";
import "../NFT/ILazyMint1155.sol";




interface UnknownToken {
    function supportsInterface(bytes4 interfaceId) external returns (bool);
}

contract Marketplace is Initializable, OwnableUpgradeable, UUPSUpgradeable, EIP712Upgradeable {

    event Sale(
        address buyer,
        address seller,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 quantity
    );

    event BundleSale(
        address buyer,
        address seller,
        address tokenAddress,
        uint256[] tokenId,
        uint256 amount
    );

    event RoyaltyPaid(
        address tokenAddress,
        address royaltyReceiver,
        uint256 royaltyAmount
    );

    event DistributedRoyaltyPaid(
        address tokenAddress,
        address royaltyReceiver,
        RoyaltyShare[] collaborators,
        uint256 royaltyAmount
    );

    event CancelledOrder(
        address seller,
        address tokenAddress,
        uint256 tokenId,
        uint256 listingType
    );

    event NewRoyaltyLimit(
        uint256 newRoyaltyLimit
    );

    event NewMarketplaceFee(
        uint256 newMarketplaceFee
    );

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct Order {
        address user;               
        address tokenAddress;       
        uint256 tokenId;            
        uint256 quantity;           
        uint256 listingType;        
        address paymentToken;       
        uint256 value;              
        uint256 deadline;           
        uint256[] bundleTokens;     
        uint256[] bundleTokensQuantity;
        uint256 salt;               
    }

    struct PaymentInfo {
        address owner;
        address buyer;
        address tokenAddress;
        uint256 tokenId;
        uint256 amount;
        address paymentToken;
    }


    bytes32 constant ORDER_TYPEHASH = keccak256(
        "Order(address user,address tokenAddress,uint256 tokenId,uint256 quantity,uint256 listingType,address paymentToken,uint256 value,uint256 deadline,bytes32 bundleTokens,uint256 salt)"
    );

    uint256 public marketplaceFee; 
    uint256 public royaltyLimit;

    mapping(address => mapping(bytes32 => bool)) orderIsCancelledOrCompleted;
    mapping(address => mapping(bytes32 => uint256)) amountOf1155TokensLeftToSell;


   
    function initialize(
        string calldata name,
        string calldata version,
        uint256 _marketplaceFee,
        uint256 _royaltyLimit
    ) initializer public {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __EIP712_init(name, version);
        marketplaceFee = _marketplaceFee;
        royaltyLimit = _royaltyLimit;
    }


    /*
     * This function is called before proxy upgrade and makes sure it is authorized.
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}


    /*
     * Returns implementation address
     */
    function implementationAddress() external view returns (address){
        return _getImplementation();
    }



    function setRoyaltyLimit(uint256 _royaltyLimit) external onlyOwner{
        require(_royaltyLimit <= 9500,'Over 95%');
        royaltyLimit = _royaltyLimit;
        emit NewRoyaltyLimit(_royaltyLimit);
    }


    function setMarketplaceFee(uint256 _marketplaceFee) external onlyOwner{
        require(_marketplaceFee <= 9500,'Over 95%');
        marketplaceFee = _marketplaceFee;
        emit NewMarketplaceFee(_marketplaceFee);
    }


    function withdrawETH(uint256 amount, address payable receiver) external onlyOwner{
        require(receiver != address(0));
        require(amount != 0);
        receiver.transfer(amount);
    }


   
    function withdrawERC20(
        uint256 amount,
        address payable receiver,
        address tokenAddress
    ) external onlyOwner{
        require(receiver != address(0));
        require(amount != 0);
        IERC20(tokenAddress).transfer(receiver, amount);
    }


    function completeOrder(
        Order calldata _sellerOrder,
        Sig calldata _sellerSig,
        Order calldata _buyerOrder,
        Sig calldata _buyerSig
    ) public payable {
        bool isAuction = _sellerOrder.listingType == 1 || _sellerOrder.listingType == 4;
        if(isAuction){
            require(_sellerOrder.user == msg.sender || _buyerOrder.user == msg.sender, 'User address doesnt match');
            if(msg.sender == _buyerOrder.user)
                require(block.timestamp > _sellerOrder.deadline, 'Auction has not ended');
        }else{
            require(_buyerOrder.user == msg.sender, 'Buyer address doesnt match');
        }
        if(isAuction) require(_buyerOrder.paymentToken != address(0), 'Only ERC20 for auction');

        bool isERC721 = checkERCType(_buyerOrder.tokenAddress);
        bool isNotBundleOrder = _sellerOrder.listingType != 3 && _sellerOrder.listingType != 4;
        bool isERC1155 = !isERC721 && isNotBundleOrder;


        bytes32 sellerHash = buildHash(_sellerOrder);
        if(msg.sender == _buyerOrder.user)
            checkSignature(sellerHash, _sellerOrder.user, _sellerSig);

        if(isAuction){
            bytes32 buyerHash = buildHash(_buyerOrder);
            checkSignature(buyerHash, _buyerOrder.user, _buyerSig);
        }

        if(
            isERC1155
            && orderIsCancelledOrCompleted[_sellerOrder.user][sellerHash] == false
            && amountOf1155TokensLeftToSell[_sellerOrder.user][sellerHash] == 0
        ){
            amountOf1155TokensLeftToSell[_sellerOrder.user][sellerHash] = _sellerOrder.quantity;
        }

        checkOrdersValidity(_sellerOrder, _buyerOrder, isERC721, isNotBundleOrder, isAuction);
        checkOrdersCompatibility(_sellerOrder, _buyerOrder, isERC721, isNotBundleOrder, sellerHash);

        if(isNotBundleOrder)
            transferTokens(
                _sellerOrder.tokenAddress,
                _sellerOrder.tokenId,
                _sellerOrder.user,
                _buyerOrder.user,
                _buyerOrder.quantity,
                isERC721
            );
        if(isERC1155)
        {
            amountOf1155TokensLeftToSell[_sellerOrder.user][sellerHash] -=  _buyerOrder.quantity;
        }

        if(!isNotBundleOrder) transferBundle(_sellerOrder, _buyerOrder, isERC721);

        PaymentInfo memory payment = PaymentInfo(
            _sellerOrder.user,
            _buyerOrder.user,
            _sellerOrder.tokenAddress,
            _sellerOrder.tokenId,
            _buyerOrder.value,
            _sellerOrder.paymentToken
        );

        transferCoins(
            payment,
            isNotBundleOrder
        );

        if(isERC1155){  
            if(amountOf1155TokensLeftToSell[_sellerOrder.user][sellerHash] == 0) {
                orderIsCancelledOrCompleted[_sellerOrder.user][sellerHash] = true;
            }
        }else{
            orderIsCancelledOrCompleted[_sellerOrder.user][sellerHash] = true;
        }

        if(isNotBundleOrder){
            emit Sale(
                _buyerOrder.user,
                _sellerOrder.user,
                _sellerOrder.tokenAddress,
                _buyerOrder.tokenId,
                _buyerOrder.value,
                _buyerOrder.quantity
            );
        } else {
            emit BundleSale(
                _buyerOrder.user,
                _sellerOrder.user,
                _sellerOrder.tokenAddress,
                _sellerOrder.bundleTokens,
                _buyerOrder.value
            );
        }

    }


    
    function cancelOrder(
        Order calldata _usersOrder,
        Sig calldata _usersSig
    ) external {
        require(_usersOrder.user == msg.sender, 'Wrong order');
        bytes32 usersHash = buildHash(_usersOrder);
        checkSignature(usersHash, _usersOrder.user, _usersSig);
        orderIsCancelledOrCompleted[msg.sender][usersHash] = true;

        emit CancelledOrder(_usersOrder.user, _usersOrder.tokenAddress, _usersOrder.tokenId, _usersOrder.listingType);
    }



    function transferTokens(
        address tokenAddress,
        uint256 tokenId,
        address from,
        address to,
        uint256 quantity,
        bool isERC721
    ) private {
        bool supportsLazyMint = supportsLazyMint(tokenAddress, isERC721);

        if(isERC721){
            bool shouldLazyMint = supportsLazyMint &&
            needsLazyMint721(
                tokenAddress,
                from,
                tokenId
            );

            if(shouldLazyMint){
                ILazyMint721(tokenAddress).lazyMint(to, tokenId);
            }else{
                IERC721(tokenAddress).safeTransferFrom(from, to, tokenId);
            }
        }else{
            bool shouldLazyMint = supportsLazyMint &&
            needsLazyMint1155(
                tokenAddress,
                from,
                tokenId,
                quantity
            );

            if(shouldLazyMint){
                ILazyMint1155(tokenAddress)
                .lazyMint(to, tokenId, quantity);
            }else{
                IERC1155(tokenAddress).safeTransferFrom(from, to, tokenId, quantity, '');
            }
        }
    }



    function transferBundle(
        Order calldata _sellerOrder,
        Order calldata _buyerOrder,
        bool isERC721
    ) private {
        address tokenAddress = _buyerOrder.tokenAddress;
        bool supportsLazyMint = supportsLazyMint(_sellerOrder.tokenAddress, isERC721);

        for(uint i=0; i<_sellerOrder.bundleTokens.length; i++){
            require(_sellerOrder.bundleTokens[i] == _buyerOrder.bundleTokens[i], 'Wrong tokenId');
            require(_sellerOrder.bundleTokensQuantity[i] == _buyerOrder.bundleTokensQuantity[i], 'Wrong quantity');
            uint256 bundleTokenId = _sellerOrder.bundleTokens[i];
            uint256 bundleTokenQuantity = _sellerOrder.bundleTokensQuantity[i];

            if(isERC721){
                require(bundleTokenQuantity == 1,'ERC721 is unique');
                if(
                    supportsLazyMint &&
                    needsLazyMint721(
                    _sellerOrder.tokenAddress,
                    _sellerOrder.user,
                    bundleTokenId
                    )
                ){
                    ILazyMint721(_sellerOrder.tokenAddress)
                        .lazyMint(_buyerOrder.user, bundleTokenId);
                }else{
                    IERC721(tokenAddress)
                    .safeTransferFrom(
                        _sellerOrder.user,
                        _buyerOrder.user,
                        bundleTokenId
                    );
                }

            }else{
                if(supportsLazyMint &&
                needsLazyMint1155(
                    _sellerOrder.tokenAddress,
                    _sellerOrder.user,
                    bundleTokenId,
                    bundleTokenQuantity
                )){
                    ILazyMint1155(_sellerOrder.tokenAddress)
                        .lazyMint(_buyerOrder.user, bundleTokenId, bundleTokenQuantity);
                }else{
                    IERC1155(tokenAddress)
                    .safeTransferFrom(
                        _sellerOrder.user,
                        _buyerOrder.user,
                        bundleTokenId,
                        bundleTokenQuantity,
                        ''
                    );
                }
            }
        }
    }


    function transferCoins(
        PaymentInfo memory payment,
        bool isNotBundleOrder
    ) private {
        bool ERC20Payment = payment.paymentToken != address(0);
        uint256 transactionAmount = payment.amount;

        if(ERC20Payment){
            require(IERC20(payment.paymentToken)
                .balanceOf(payment.buyer) >= payment.amount, 'Not enough balance');
            require(IERC20(payment.paymentToken)
                .allowance(payment.buyer, address(this)) >= payment.amount, 'Not enough allowance');
        }else{
            require(msg.value >= payment.amount,'Not enough {value}');
        }

       
        if(UnknownToken(payment.tokenAddress).supportsInterface(type(IRoyaltyDistribution).interfaceId)){
            IRoyaltyDistribution tokenContract = IRoyaltyDistribution(payment.tokenAddress);

            if(
                tokenContract.royaltyDistributionEnabled()
                && tokenContract.getDefaultRoyaltyDistribution().length > 0
            ){

                
                if(
                    isNotBundleOrder
                    && tokenContract.getTokenRoyaltyDistribution(payment.tokenId).length > 0
                ){
                    RoyaltyShare[] memory royaltyShares = tokenContract.getTokenRoyaltyDistribution(payment.tokenId);
                    (address royaltyReceiver, uint256 royaltyAmount) = IRoyaltyDistribution(payment.tokenAddress)
                                                                    .royaltyInfo(payment.tokenId, payment.amount);
                    payDistributedRoyalty
                    (
                        payment,
                        royaltyReceiver,
                        royaltyAmount,
                        royaltyShares
                    );

                }else{
                    RoyaltyShare[] memory royaltyShares = tokenContract.getDefaultRoyaltyDistribution();
                    (address royaltyReceiver, uint256 royaltyAmount) = IRoyaltyDistribution(payment.tokenAddress)
                                                                    .royaltyInfo(payment.tokenId, payment.amount);
                    payDistributedRoyalty
                    (
                        payment,
                        royaltyReceiver,
                        royaltyAmount,
                        royaltyShares
                    );
                }
            }else{
                (address royaltyReceiver, uint256 royaltyAmount) = IRoyaltyDistribution(payment.tokenAddress)
                                                                .royaltyInfo(payment.tokenId, payment.amount);
                payRoyaltyIERC2981
                (
                    payment.buyer,
                    payment.owner,
                    payment.paymentToken,
                    payment.amount,
                    royaltyReceiver,
                    royaltyAmount,
                    payment.tokenAddress
                );
            }

        }else if(UnknownToken(payment.tokenAddress).supportsInterface(type(IERC2981).interfaceId)){
            (address royaltyReceiver, uint256 royaltyAmount) = IRoyaltyDistribution(payment.tokenAddress)
                                                            .royaltyInfo(payment.tokenId, payment.amount);
            payRoyaltyIERC2981
            (
                payment.buyer,
                payment.owner,
                payment.paymentToken,
                payment.amount,
                royaltyReceiver,
                royaltyAmount,
                payment.tokenAddress
            );

        }else{
            uint256 marketplaceFee = transactionAmount * marketplaceFee / 10000;
            uint256 amountforSeller = transactionAmount - marketplaceFee;

            if(ERC20Payment){
                IERC20(payment.paymentToken)
                    .transferFrom(payment.buyer, address(this), marketplaceFee);
                IERC20(payment.paymentToken)
                    .transferFrom(payment.buyer, payment.owner, amountforSeller);
            }else{
                payable(payment.owner).transfer(amountforSeller);
            }

        }

        if(payment.paymentToken == address(0)){
            uint256 amountToReturn = msg.value - transactionAmount;
            payable(payment.buyer).transfer(amountToReturn);
        }
    }


    function payRoyaltyIERC2981(
        address from,
        address to,
        address paymentToken,
        uint256 totalAmount,
        address royaltyReceiver,
        uint256 royaltyAmountToReceive,
        address tokenAddress
    ) private {
        if(totalAmount > 0)
        {
            bool ERC20Payment = paymentToken != address(0);
            uint256 marketplaceFee = totalAmount * marketplaceFee / 10000;
            uint256 royaltyAmount = royaltyAmountToReceive;
            uint256 maxRoyaltyAmount = totalAmount * royaltyLimit / 10000;
            if(royaltyAmount > maxRoyaltyAmount)
                royaltyAmount = maxRoyaltyAmount;

            uint256 amountToSeller = totalAmount - marketplaceFee - royaltyAmount;

            if(ERC20Payment){
                if(marketplaceFee > 0)
                    IERC20(paymentToken).transferFrom(from, address(this), marketplaceFee);
                if(royaltyAmount > 0)
                    IERC20(paymentToken).transferFrom(from, royaltyReceiver, royaltyAmount);
                if(amountToSeller > 0)
                    IERC20(paymentToken).transferFrom(from, to, amountToSeller);
            }else{
                if(royaltyAmount > 0)
                    payable(royaltyReceiver).transfer(royaltyAmount);
                if(amountToSeller > 0)
                    payable(to).transfer(amountToSeller);
            }

            if(royaltyAmount > 0)
                emit RoyaltyPaid(tokenAddress, royaltyReceiver, royaltyAmount);
        }
    }



    function payDistributedRoyalty(
        PaymentInfo memory payment,
        address royaltyReceiver,
        uint256 royaltyAmountToReceive,
        RoyaltyShare[] memory royaltyShares
    ) private {
        uint256 totalAmount = payment.amount;
        if(totalAmount > 0)
        {
            bool ERC20Payment = payment.paymentToken != address(0);
            uint256 marketplaceFee = totalAmount * marketplaceFee / 10000;
            uint256 royaltyAmount = royaltyAmountToReceive;

            uint256 maxRoyaltyAmount = totalAmount * royaltyLimit / 10000;
            if(royaltyAmount > maxRoyaltyAmount)
                royaltyAmount = maxRoyaltyAmount;

            uint256 amountToSeller = totalAmount - marketplaceFee - royaltyAmount;

            if(ERC20Payment){
                if(marketplaceFee > 0)
                    IERC20(payment.paymentToken)
                    .transferFrom(payment.buyer, address(this), marketplaceFee);
                if(amountToSeller > 0)
                    IERC20(payment.paymentToken)
                    .transferFrom(payment.buyer, payment.owner, amountToSeller);
            }else{
                if(amountToSeller > 0)
                    payable(payment.owner).transfer(amountToSeller);
            }

            if(royaltyAmount > 0){
                uint256 royaltiesLeftToPay = royaltyAmount;
                for(uint i=0; i<royaltyShares.length; i++){
                    address royaltyShareReceiver = royaltyShares[i].collaborator;
                    uint256 royaltyShare = royaltyAmount * royaltyShares[i].share / 10000;
                    if(royaltyShare > 0 && royaltiesLeftToPay >= royaltyShare){
                        if(ERC20Payment){
                            IERC20(payment.paymentToken)
                            .transferFrom(payment.buyer, royaltyShareReceiver, royaltyShare);
                        }else{
                            payable(royaltyShareReceiver).transfer(royaltyShare);
                        }
                        royaltiesLeftToPay -= royaltyShare;
                    }
                }

                if(royaltiesLeftToPay > 0){
                    if(ERC20Payment){
                        IERC20(payment.paymentToken)
                        .transferFrom(payment.buyer, royaltyReceiver, royaltiesLeftToPay);
                    }else{
                        payable(royaltyReceiver).transfer(royaltiesLeftToPay);
                    }
                }
            }

            if(royaltyAmount > 0)
                emit DistributedRoyaltyPaid(payment.tokenAddress, royaltyReceiver, royaltyShares, royaltyAmount);
        }
    }


    function checkOrdersValidity(
        Order calldata _sellerOrder,
        Order calldata _buyerOrder,
        bool isERC721,
        bool isNotBundleOrder,
        bool isAuction
    ) private {
        bool supportsLazyMint = supportsLazyMint(_sellerOrder.tokenAddress, isERC721);
        require(
            _sellerOrder.listingType == 0
            || _sellerOrder.listingType == 1
            || _sellerOrder.listingType == 3
            || _sellerOrder.listingType == 4
            ,'Unknown listing type'
        );

        if(isNotBundleOrder){
            require(_sellerOrder.bundleTokens.length == 0, 'Wrong listingType');
            if(isERC721){
                require(_buyerOrder.quantity == 1 && _sellerOrder.quantity == 1, 'Non-1 quantity');
                require(
                    (supportsLazyMint &&
                    needsLazyMint721(
                        _sellerOrder.tokenAddress,
                        _sellerOrder.user,
                        _sellerOrder.tokenId
                    ))
                    ||
                    IERC721(_sellerOrder.tokenAddress).ownerOf(_sellerOrder.tokenId) == _sellerOrder.user,
                    'Not an owner'
                );
            }else{
                require(_buyerOrder.quantity > 0 && _sellerOrder.quantity > 0, '0 quantity');
                require(
                    (supportsLazyMint &&
                    needsLazyMint1155(
                        _sellerOrder.tokenAddress,
                        _sellerOrder.user,
                        _sellerOrder.tokenId,
                        _buyerOrder.quantity
                    ))
                    ||
                    IERC1155(_sellerOrder.tokenAddress)
                    .balanceOf(_sellerOrder.user, _sellerOrder.tokenId)  >= _buyerOrder.quantity,
                    'Not enough tokens'
                );
            }
        }

        require(
            IERC721(_sellerOrder.tokenAddress).isApprovedForAll(_sellerOrder.user,address(this)),
            'Not approved'
        );

        if(!isAuction){
            require(_sellerOrder.deadline >= block.timestamp && _buyerOrder.deadline >= block.timestamp, 'Overdue order');
        } else {
            require(_buyerOrder.deadline >= block.timestamp, 'Overdue offer');
        }
    }


    function checkOrdersCompatibility(
        Order calldata _sellerOrder,
        Order calldata _buyerOrder,
        bool isERC721,
        bool isNotBundleOrder,
        bytes32 sellerHash
    ) private view {
        require(_buyerOrder.user != _sellerOrder.user, 'Buyer == Seller');
        require(_buyerOrder.tokenAddress == _sellerOrder.tokenAddress, 'Different tokens');
        require(_sellerOrder.tokenId == _buyerOrder.tokenId || !isNotBundleOrder, 'TokenIDs dont match');
        if(!isERC721 && isNotBundleOrder){
            require(
                amountOf1155TokensLeftToSell[_sellerOrder.user][sellerHash] >= _buyerOrder.quantity,
                'Cant buy that many'
            );
        }
        require(_sellerOrder.listingType == _buyerOrder.listingType, 'Listing type doesnt match');
        require(_sellerOrder.paymentToken == _buyerOrder.paymentToken, 'Payment token dont match');
        require(
            (isNotBundleOrder &&
            ((_sellerOrder.value <= _buyerOrder.value && isERC721) ||
            ((_sellerOrder.value * _buyerOrder.quantity) <= _buyerOrder.value && !isERC721)))
            ||
            (!isNotBundleOrder &&
            (_sellerOrder.value <= _buyerOrder.value)),
            'Value is too small'
        );
        require(
            hashBundleTokens(_sellerOrder.bundleTokens, _sellerOrder.bundleTokensQuantity) ==
            hashBundleTokens(_buyerOrder.bundleTokens, _buyerOrder.bundleTokensQuantity),
            'Token lists dont match'
        );
    }

    function checkSignature(
        bytes32 orderHash,
        address userAddress,
        Sig calldata _sellerSig
    ) private view {
        require (!orderIsCancelledOrCompleted[userAddress][orderHash],'Cancelled or complete');
        address recoveredAddress = recoverAddress(orderHash, _sellerSig);
        require(userAddress == recoveredAddress, 'Bad signature');
    }


    function checkERCType(address tokenAddress) private returns(bool isERC721){
        bool isERC721 = UnknownToken(tokenAddress).supportsInterface(type(IERC721).interfaceId);

        require(
        isERC721 ||
        UnknownToken(tokenAddress).supportsInterface(type(IERC1155).interfaceId),
        'Unknown Token');

        return isERC721;
    }


    function needsLazyMint721(
        address tokenAddress,
        address ownerAddress,
        uint256 tokenId
    ) private view returns(bool){
        return !ILazyMint721(tokenAddress).exists(tokenId)
        && OwnableUpgradeable(tokenAddress).owner() == ownerAddress;
    }


    function needsLazyMint1155(
        address tokenAddress,
        address ownerAddress,
        uint256 tokenId,
        uint256 quantity
    ) private view returns(bool){
        return IERC1155(tokenAddress)
        .balanceOf(ownerAddress, tokenId) < quantity
        && OwnableUpgradeable(tokenAddress).owner() == ownerAddress;
    }


 
    function supportsLazyMint(
        address tokenAddress,
        bool isERC721
    ) private returns(bool){
        return (isERC721 && UnknownToken(tokenAddress).supportsInterface(type(ILazyMint721).interfaceId))
        || (!isERC721 && UnknownToken(tokenAddress).supportsInterface(type(ILazyMint1155).interfaceId));
    }

    function buildHash(Order calldata _order) public view returns (bytes32){
        return _hashTypedDataV4(keccak256(abi.encode(
                ORDER_TYPEHASH,
                _order.user,
                _order.tokenAddress,
                _order.tokenId,
                _order.quantity,
                _order.listingType,
                _order.paymentToken,
                _order.value,
                _order.deadline,
                hashBundleTokens(_order.bundleTokens, _order.bundleTokensQuantity),
                _order.salt
            )));
    }


    function hashBundleTokens(
        uint256[] calldata _indexArray,
        uint256[] calldata _quantityArray
    ) public view returns(bytes32){
        if(_indexArray.length == 0) return bytes32(0);
        bytes32 indexHash = (keccak256(abi.encodePacked(_indexArray)));
        bytes32 arrayHash = (keccak256(abi.encodePacked(_quantityArray)));
        return (keccak256(abi.encodePacked(indexHash, arrayHash)));
    }

    function recoverAddress(
        bytes32 hash,
        Sig calldata _sig
    ) public view returns(address) {
        (address recoveredAddress, ) = ECDSAUpgradeable.tryRecover(hash, _sig.v, _sig.r, _sig.s);
        return recoveredAddress;
    }
}
