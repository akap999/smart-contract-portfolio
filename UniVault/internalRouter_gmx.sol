// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

pragma abicoder v2;

contract GmxRouter is Ownable {

    IRouter public router = IRouter(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);

    mapping(address => address) public priceFeedAddress;

    constructor() {
        Ownable_init();
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
            0xf97f4df75117a78c1a5a0dbb814af92458539fb4
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

    ISwapRouter public immutable swapRouter;

    function swap(address _tokenIn, address _tokenOut, uint amountIn, uint minOut) external returns (uint256 amountOut) {
        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);

        require(
            amountIn <= tokenIn.balanceOf(address(msg.sender)),
            "Vault: Vault has insufficient balance"
        );

        address[] memory _path = new address[](2);
        _path[0] = _tokenIn;
        _path[1] = _tokenOut;

        uint initialBalance = tokenOut.balanceOf(address(msg.sender));
        router.swap(_path, amountIn, minOut, address(this));
        uint finalBalance = tokenOut.balanceOf(address(msg.sender));
        amountOut = finalBalance - initialBalance;

        return amountOut;
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
}
