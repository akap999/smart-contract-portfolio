// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

pragma abicoder v2;

contract Vault is Ownable {
    using SafeMath for uint;
   // using Math for uint;

    address public routerAddress = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
    IRouter public router = IRouter(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);
    IPositionRouter public positionRouter =
        IPositionRouter(0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868);
    IReader public reader = IReader(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);
    address public constant GMXVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;


    address depositTokenAddress;
    address protocolAddress =
        address(0x4eD0Cf4DfB7b280c1e1C5D6Fbf9a7Ba3d2324a99);

    IERC20 public immutable depositToken;
    IERC20 public swappedToken;

    uint24 public constant poolFee = 3000;
    uint256 public minExecutionFee = 180000000000000;

    uint public totalSupply;
    uint public protocolFee;
    uint public maintenanceFee; 
    uint public maintenanceFeePercentage;
    mapping(address => bool) depositor;
    uint public depositors;

    address[] public tokenList;

    string public vaultName;

    mapping(address => uint) public balanceOf;
    mapping(address => uint) public swappedSupply;
    mapping(address => uint) public userUSDBalance;

    //arrays to store collateral and index tokens
    address[] public collateralTokens;
    address[] public indexTokens;
    bool[] public isLongs;

    bool public isPositionOpen = false;
    bool public withdrawable = false;
    bool public depositable = true;

    mapping(address => address) public priceFeedAddress;

    modifier isWithdrawable() {
        require(withdrawable, "Vault: Withdrawals are disabled");
        _;
    }

    modifier isDepositable() {
        require(depositable, "Vault: Deposits are disabled");
        _;
    }

    constructor(
        address _owner,
        address _depositToken,
        uint _maintenanceFeePercentage,
        string memory _vaultName
    ) {
        depositToken = IERC20(_depositToken);
        depositTokenAddress = _depositToken;
        maintenanceFeePercentage = _maintenanceFeePercentage;
        transferOwnership(_owner);
        vaultName = _vaultName;
        
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        
        address positionRouterAddress = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;
        router.approvePlugin(positionRouterAddress);

        priceFeedAddress[
            0x2170Ed0880ac9A755fd29B2688956BD959F933F8
        ] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        priceFeedAddress[
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
        ] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        priceFeedAddress[
            0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f
        ] = 0x6ce185860a4963106506C203335A2910413708e9;
        priceFeedAddress[
            0xf97f4df75117a78c1A5a0DBb814Af92458539FB4
        ] = 0x86E53CF1B870786351Da77A57575e79CB55812CB;
        priceFeedAddress[
            0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0
        ] = 0x9C917083fDb403ab5ADbEC26Ee294f6EcAda2720;
        priceFeedAddress[
            0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
        ] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        priceFeedAddress[
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831
        ] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        priceFeedAddress[
            0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
        ] = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
        priceFeedAddress[
            0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1
        ] = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;
        priceFeedAddress[
            0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F
        ] = 0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8;
    }

    function _mint(address _to, uint usd) private {
        uint256 _shares = usd / getShareValue();
        totalSupply += _shares;
        balanceOf[_to] += _shares;
    }

    function approve(address _token) public {
        uint256 MAX_INT = type(uint256).max;
        IERC20(_token).approve(address(this), MAX_INT);
    }

    function _burn(address _from, uint _shares) private {
        totalSupply -= _shares;
        balanceOf[_from] -= _shares;
    }

    ISwapRouter public immutable swapRouter;
 
    uint24 public constant feeTier = 3000;

    function isTokenInList(address tokenAddress) internal view returns (bool) {
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == tokenAddress) {
                return true;
            }
        }
        return false;
    }

    function addTokenToList(address tokenAddress) public {
        if (!isTokenInList(tokenAddress)) {
            tokenList.push(tokenAddress);
        }
    }

    function swap(  //shouldn't tokenIn = Deposit token?
        address _tokenIn,
        address _tokenOut,
        uint amountIn,
        uint minOut,
        uint maxIn,
        uint8 _swap // 0-gmx, 1-uniswap - to diff swap
    ) external onlyOwner returns (uint256 amountOut) {
        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);

        require(
            amountIn <= tokenIn.balanceOf(address(this)),
            "Vault: Vault has insufficient balance"
        );

        addTokenToList(_tokenOut);
        tokenIn.approve(address(router), amountIn);

        uint initialBalance = tokenOut.balanceOf(address(this));
        if(_swap==0){ //gmx
            address[] memory _path = new address[](2);
            _path[0] = _tokenIn;
            _path[1] = _tokenOut;
            router.swap(_path, amountIn, minOut, address(this));
        }
        else if(_swap==1){ //uniswap
            ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: feeTier,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: (uint160)(Math.sqrt(maxIn) / 128)
            });
            swapRouter.exactInputSingle(params);
        }
        else{
            revert('wrong input');
        }
        
        uint finalBalance = tokenOut.balanceOf(address(this));
        amountOut = finalBalance - initialBalance;

        tokenIn.approve(address(router), 0);

        swappedSupply[_tokenIn] -= amountIn;
        swappedSupply[_tokenOut] += amountOut;
        return amountOut;
    }

    function internalSwap(
        address _tokenIn,
        address _tokenOut,
        uint amountIn,
        uint minOut,
        uint8 _swap
    ) internal returns (uint256 amountOut) {
        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);

        require(
            amountIn <= tokenIn.balanceOf(address(this)),
            "Vault: Vault has insufficient balance"
        );

        addTokenToList(_tokenOut);
        tokenIn.approve(address(router), amountIn);

        uint initialBalance = tokenOut.balanceOf(address(this));
        if(_swap==0){  //gmx
            address[] memory _path = new address[](2);
            _path[0] = _tokenIn;
            _path[1] = _tokenOut;
            router.swap(_path, amountIn, minOut, address(this));
        }
        else if(_swap==1){ //uniswap
            ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: feeTier,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: (uint160)(amountIn)
            });
            swapRouter.exactInputSingle(params);
        }
        else{
            revert('wrong input');
        }
        
        uint finalBalance = tokenOut.balanceOf(address(this));
        amountOut = finalBalance - initialBalance;

        tokenIn.approve(address(router), 0);

        swappedSupply[_tokenIn] -= amountIn;
        swappedSupply[_tokenOut] += amountOut;
        return amountOut;
    }

    function createIncreasePosition(
        address _transactionToken,
        address[] memory _path,
        address _indexToken,
        uint _amountIn,
        uint _minOut,
        uint _sizeDelta,
        bool _isLong,
        uint _acceptablePrice, 
        uint _minExecutionFee
    ) public payable {
        require(msg.value == _minExecutionFee, 'not transferring enough val');
        minExecutionFee = _minExecutionFee;
        IERC20 transactionToken = IERC20(_transactionToken);
        transactionToken.approve(routerAddress, _amountIn);
        bytes32 _referralCode = 0x0000000000000000000000000000000000000000000000000000000000000000;
        address _callbackTarget = 0x0000000000000000000000000000000000000000;
        positionRouter.createIncreasePosition{value: minExecutionFee}(
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            minExecutionFee,
            _referralCode,
            _callbackTarget
        );
        indexTokens.push(_indexToken);
        collateralTokens.push(_path[_path.length - 1]);
        isLongs.push(_isLong);
    }

    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget

    ) public payable {
        require(msg.value == _executionFee, 'not transferring enough val');
        positionRouter.createDecreasePosition{value: _executionFee}(_path, _indexToken, _collateralDelta, _sizeDelta, _isLong, address(this), _acceptablePrice, _minOut, _executionFee, _withdrawETH, _callbackTarget);
    }

    function readAllPositonData() external view returns (uint256[] memory) {
        return
            reader.getPositions(
                GMXVault,
                address(this),
                collateralTokens,
                indexTokens,
                isLongs
            );
    }

    function deposit(uint256 _amount) external payable isDepositable {
        //uint _amount = amount; - irrelavwnt so removed
        require(msg.value>=_amount,'insuffecient value');
        
        uint _maintenanceFeePercentage = maintenanceFeePercentage; //gas save
        uint amountToDeposit = _amount
            .mul(1000 - 5 - (_maintenanceFeePercentage.mul(10)))
            .div(1000);
        require(userUSDBalance[msg.sender]+amountToDeposit<=5000,'limit exceeded');
        
        protocolFee += _amount.mul(5).div(1000); //check? protocol fee keeps on increasing
        maintenanceFee += _amount.mul(_maintenanceFeePercentage).div(100); //check?  maintainance fee keeps on increasing

        if(!depositor[msg.sender]){ //improved logic
            depositors += 1;
            depositor[msg.sender] = true;
        }

        addTokenToList(depositTokenAddress);
        swappedSupply[depositTokenAddress] += amountToDeposit;

        depositToken.transferFrom(msg.sender, address(this), _amount);
        depositToken.approve(protocolAddress, protocolFee.mul(1000000));
        depositToken.transfer(protocolAddress, protocolFee);

        userUSDBalance[msg.sender] += amountToDeposit; // reentrancy checked
        _mint(msg.sender, amountToDeposit); // reentrancy checked
    }

    function withdraw(uint _shares,uint8 _swap) external payable isWithdrawable { //_swap -> 0-gmx, 1-uniswap - to diff swap
        require(
            _shares <= balanceOf[msg.sender],
            "Vault: You don't have enough shares"
        );

        uint currentDepositTokenBalance = (_shares *
            swappedSupply[tokenList[0]]) / totalSupply;

        for (uint256 i = 0; i < tokenList.length; i++) {
            if (swappedSupply[tokenList[i]] > 0) {
                if (tokenList[i] != depositTokenAddress) {
                    uint amountCurrentToken = (_shares *
                        swappedSupply[tokenList[i]]) / totalSupply;
                    currentDepositTokenBalance += internalSwap(
                        tokenList[i],
                        depositTokenAddress,
                        amountCurrentToken,
                        0,
                        _swap
                    );
                }
            }
        }

        swappedSupply[tokenList[0]] -= currentDepositTokenBalance;

        if (userUSDBalance[msg.sender] >= currentDepositTokenBalance) {
            userUSDBalance[msg.sender] -= currentDepositTokenBalance;
        } else {
            userUSDBalance[msg.sender] = 0;
            uint profitShare = (currentDepositTokenBalance -= userUSDBalance[
                msg.sender
            ]).mul(20).div(100);
            depositToken.transfer(owner(), profitShare);
        }
        
        _burn(msg.sender, _shares); //reentrancy checked
        depositToken.transfer(msg.sender, currentDepositTokenBalance);
    }

    function changeWithdrawable(bool _withdrawable) external onlyOwner {
        withdrawable = _withdrawable;
        depositToken.transfer(owner(), maintenanceFee);
    }

    function changeDepositable(bool _depositable) external onlyOwner {
        depositable = _depositable;
    }

    function getDepositable() external view returns (bool) {
        return depositable;
    }

    function getWithdrawable() external view returns (bool) {
        return withdrawable;
    }

    function changeTrader(address _newTrader) external onlyOwner {
        transferOwnership(_newTrader);
    }

    function getBalanceOf(address _address) external view returns (uint) {
        return balanceOf[_address];
    }

    function getTotalSupply() external view returns (uint) {
        return totalSupply;
    }

    function getSwappedSupply()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256[] memory tokenBalances = new uint256[](tokenList.length);
        for (uint256 i = 0; i < tokenList.length; i++) {
            tokenBalances[i] = swappedSupply[tokenList[i]];
        }
        return (tokenList, tokenBalances);
    }

    function getThePrice(address _priceFeedAddress) public view returns (int) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            _priceFeedAddress
        );
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return price;
    }


    function getPriceForAllTokensInVault() internal view returns (uint256) {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (swappedSupply[tokenList[i]] > 0) {
                require(
                    priceFeedAddress[tokenList[i]] != address(0),
                    "Vault: Price feed not found"
                );
                uint256 price = uint256(
                    getThePrice(priceFeedAddress[tokenList[i]])
                );
                totalValue += (swappedSupply[tokenList[i]] * price) / 1e2;
            }
        }
        return totalValue;
    }

    function getShareValue() public view returns (uint256) {
        uint256 totalValue = getPriceForAllTokensInVault();
        if (totalSupply == 0) {
            return 1e6;
        }
        return totalValue / totalSupply;
    }
}

interface IRouter {
    function addPlugin(address _plugin) external;

    function pluginTransfer(
        address _token,
        address _account,
        address _receiver,
        uint256 _amount
    ) external;

    function pluginIncreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external;

    function pluginDecreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) external returns (uint256);

    function swap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address _receiver
    ) external;

    function approvePlugin(address _plugin) external;

    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external payable returns (bytes32);

    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget
    ) external payable returns (bytes32);
}


interface IPositionRouter {
    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external payable returns (bytes32);

    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget
    ) external payable returns (bytes32);
}

interface IReader {
    function getPositions(
        address _vault,
        address _account,
        address[] memory _collateralTokens,
        address[] memory _indexTokens,
        bool[] memory _isLong
    ) external view returns (uint256[] memory);
}

library Math {
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        // else z = 0 (default value)
    }
}
