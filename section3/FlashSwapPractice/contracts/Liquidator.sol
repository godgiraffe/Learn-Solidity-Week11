// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";
import { IUniswapV2Factory } from "v2-core/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router01 } from "v2-periphery/interfaces/IUniswapV2Router01.sol";
import { IWETH } from "v2-periphery/interfaces/IWETH.sol";
import { IFakeLendingProtocol } from "./interfaces/IFakeLendingProtocol.sol";

// This is liquidator contrac for testing,
// all you need to implement is flash swap from uniswap pool and call lending protocol liquidate function in uniswapV2Call
// lending protocol liquidate rule can be found in FakeLendingProtocol.sol
contract Liquidator is IUniswapV2Callee, Ownable {
    struct CallbackData {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
    }

    address internal immutable _FAKE_LENDING_PROTOCOL;
    address internal immutable _UNISWAP_ROUTER;
    address internal immutable _UNISWAP_FACTORY;
    address internal immutable _WETH9;
    uint256 internal constant _MINIMUM_PROFIT = 0.01 ether;

    constructor(address lendingProtocol, address uniswapRouter, address uniswapFactory) {
        _FAKE_LENDING_PROTOCOL = lendingProtocol;
        _UNISWAP_ROUTER = uniswapRouter;
        _UNISWAP_FACTORY = uniswapFactory;
        _WETH9 = IUniswapV2Router01(uniswapRouter).WETH();
    }

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    // UniSwap - WETH/USDC Pool - 100 WETH : 10,000 USDC  ->  1eth = 100usdc
    // lendProtocol - give me 80 usdc, I give you 1 eth

    /*
    step :
    1. get pool address (WETH/USDC) - Factory.getPair(address tokenA, address tokenB) external view returns (address pair);
    2. 確認換 80usdc 出來，要打多少 weth 進去 - Router01.getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
    3. 跟 UniSwap 進行「你先給我錢，再去call 我指定的 func，再去驗證我有沒有還錢」的 Swap - Pair.function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
      3 - 0.  拿到 80 usdc 了
      3 - 1. 透過之前學的 abi.encode，把想帶的參數 encode 成一個變數打進 uniswap call 套利合約的 uniswapV2Call 中
      3 - 2. decode 剛剛打進來的參數
      3 - 3. 執行利套利邏輯
      3 - 4. 還錢!!
    4. 剩下來多的，就是賺的
    */
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(sender == address(this), "Sender must be this contract");
        require(amount0 > 0 || amount1 > 0, "amount0 or amount1 must be greater than 0");

        // 4. decode callback data
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) = abi.decode(data, (address, address, uint256, uint256));
        // 5. call liquidate
        IERC20(tokenOut).approve(_FAKE_LENDING_PROTOCOL, amountOut);
        IFakeLendingProtocol(_FAKE_LENDING_PROTOCOL).liquidatePosition();
        // 6. deposit ETH to WETH9, because we will get ETH from lending protocol
        // IWETH(_WETH9).deposit{value: amountIn}();
        IWETH(tokenIn).deposit{value: amountIn}();
        // 7. repay WETH to uniswap pool
        // IWETH(_WETH9).transfer(address(this), amountIn);
        IWETH(tokenIn).transfer(msg.sender, amountIn);    // 把錢還給 uni swap pool, 因為這個 func 是 uniswap pool call 的, 所以是還給 msg.sender

        // check profit
        require(address(this).balance >= _MINIMUM_PROFIT, "Profit must be greater than 0.01 ether");
    }

    // we use single hop path for testing
    function liquidate(address[] calldata path, uint256 amountOut) external {
        require(amountOut > 0, "AmountOut must be greater than 0");
        // path[0] = weth
        // path[1] = usdc
        // amountOut = 80 usdc
        // 1. get uniswap pool address
        address pool = IUniswapV2Factory(_UNISWAP_FACTORY).getPair(path[0], path[1]);
        // 2. calculate repay amount
        uint amountIn = IUniswapV2Router01(_UNISWAP_ROUTER).getAmountsIn(amountOut, path)[0];
        // 3. flash swap from uniswap pool
        CallbackData memory data;
        data.tokenIn = path[0];   // weth
        data.tokenOut = path[1];  // usdc
        data.amountIn = amountIn;
        data.amountOut = amountOut;
        // IUniswapV2Pair(pool).swap(0, amountOut, msg.sender, abi.encode(data));
        IUniswapV2Pair(pool).swap(0, amountOut, address(this), abi.encode(data));
    }

    receive() external payable {}
}