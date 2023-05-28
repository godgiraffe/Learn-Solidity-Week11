// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";
import { IWETH } from "v2-periphery/interfaces/IWETH.sol";

// This is a pracitce contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    // struct CallbackData {
    //     address borrowPool;
    //     address targetSwapPool;
    //     address borrowToken;
    //     address debtToken;
    //     uint256 borrowAmount;
    //     uint256 debtAmount;
    //     uint256 debtAmountOut;
    // }
    struct CallbackData {
        uint borrowTokenAmount;
        uint repayToLowerPoolAmount;
        address priceLowerPool;
        address priceHigherPool;
    }
    uint8 constant USDC_DECIMAL = 6;
    uint8 constant WETH_DECIMAL = 18;

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

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(sender == address(this), "Sender must be this contract");
        require(amount0 > 0 || amount1 > 0, "amount0 or amount1 must be greater than 0");

        (uint borrowTokenAmount, uint repayToLowerPoolAmount, address priceLowerPool, address priceHigherPool) = abi
            .decode(data, (uint, uint, address, address));
        address wethAddr = IUniswapV2Pair(priceLowerPool).token0();
        address usdcAddr = IUniswapV2Pair(priceLowerPool).token1();

        // 計算借來的 ether 能換到多少 usdc
        uint getUsdcAmount = _getAmountOut(borrowTokenAmount, 50 ether, 6_000 * 10 ** USDC_DECIMAL); // 543966536

        // 因為是直接 call swap，所以要主動打 weth 進 pool
        IERC20(wethAddr).transfer(address(priceHigherPool), borrowTokenAmount);
        IUniswapV2Pair(priceHigherPool).swap(0, getUsdcAmount, sender, "");

        // 把需要還的 usdc 還回去
        IERC20(usdcAddr).transfer(address(priceLowerPool), repayToLowerPoolAmount);
    }


    // Method 1 is
    //  - borrow WETH from lower price pool
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    // Method 2 is
    //  - borrow USDC from higher price pool
    //  - swap USDC for WETH in lower pool
    //  - repay WETH to higher pool
    // for testing convenient, we implement the method 1 here
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // 計算借 borrowETH 的話，要還多少 token 回去
        uint256 repayToLowerPoolAmount = _getAmountIn(borrowETH, 4_000 * 10 ** USDC_DECIMAL, 50 ether);

        CallbackData memory data;
        data.borrowTokenAmount = borrowETH;
        data.repayToLowerPoolAmount = repayToLowerPoolAmount;
        data.priceLowerPool = priceLowerPool;
        data.priceHigherPool = priceHigherPool;

        IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(data));
    }

    //
    // INTERNAL PURE
    //

    // copy from UniswapV2Library
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
