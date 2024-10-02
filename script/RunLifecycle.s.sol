// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/src/test/PoolDonateTest.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";

// Tests the full lifecycle of PoolManager. Deployed contracts are in script/parameters/sepolia.json, they can be redeployed with script/DeployLifecycleTestHelpers.s.sol which prints the addresses. The script can be modified to only deploy new tokens.

// to run:
// forge script script/RunLifecycle.s.sol:RunLifecycle --rpc-url $SEPOLIA_RPC_URL --broadcast --slow --sender --sig "run" <address> -vvvv

// to only run swap tests
// forge script script/RunLifecycle.s.sol:RunLifecycle --rpc-url $SEPOLIA_RPC_URL --broadcast --slow --sender --sig "testSwap" <address> -vvvv

contract RunLifecycle is Script {
    // set from the json parameters
    IPoolManager public manager;

    PoolModifyLiquidityTest lpRouter;
    PoolSwapTest swapRouter;
    PoolDonateTest donateRouter;

    MockERC20 tokenA;
    MockERC20 tokenB;

    function setUp() public {
        uint256 chainId = block.chainid;
        if (chainId == 11155111) {
            manager = IPoolManager(vm.parseJsonAddress(vm.readFile("./script/parameters/sepolia.json"), ".PoolManager"));
            lpRouter = PoolModifyLiquidityTest(vm.parseJsonAddress(vm.readFile("./script/parameters/sepolia.json"), ".PoolModifyLiquidityTest"));
            swapRouter = PoolSwapTest(vm.parseJsonAddress(vm.readFile("./script/parameters/sepolia.json"), ".PoolSwapTest"));
            tokenA = MockERC20(vm.parseJsonAddress(vm.readFile("./script/parameters/sepolia.json"), ".MockA"));
            tokenB = MockERC20(vm.parseJsonAddress(vm.readFile("./script/parameters/sepolia.json"), ".MockB"));
        }
    }

    function run() public {
        // Additional helpers for interacting with the pool
        // TODO: Instead of deploying just import the addresses
        // TODO: Add support for donate
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // test the lifecycle (create tokens, create pool, add liquidity, swap)
        testLifecycle();

        vm.stopBroadcast();
    }

    // -----------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------

    function deployTokens() internal view returns (MockERC20 token0, MockERC20 token1) {
        if (uint160(address(tokenA)) < uint160(address(tokenB))) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }
    }

    function testLifecycle() internal {
        (MockERC20 token0, MockERC20 token1) = deployTokens();
        token0.mint(msg.sender, 1_000_000 ether);
        token1.mint(msg.sender, 1_000_000 ether);

        bytes memory ZERO_BYTES = new bytes(0);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        int24 tickSpacing = 60;

        // initialize the pool
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, tickSpacing, IHooks(address(0))
        );
        manager.initialize(poolKey, Constants.SQRT_PRICE_1_1, ZERO_BYTES);

        // approve the tokens to the routers
        token0.approve(address(lpRouter), type(uint256).max);
        token1.approve(address(lpRouter), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        // add full range liquidity to the pool
        lpRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(tickSpacing), TickMath.maxUsableTick(tickSpacing), 1 ether, 0
            ),
            ZERO_BYTES
        );

        // swap some tokens
        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;

        // 10 exactIn swaps altering zeroForOne each time
        IPoolManager.SwapParams memory params;
        for (uint256 i = 0; i < 10; i++) {
            console.log("Swapping ExactIn", i);
            console.log("zeroForOne", zeroForOne);
            params = IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1 // unlimited impact
            });

            zeroForOne = !zeroForOne;
        }

        // 10 exactOut swaps alterting zeroForOne each time
        for (uint256 i = 0; i < 10; i++) {
            console.log("Swapping ExactOut", i);
            console.log("zeroForOne", zeroForOne);
            params = IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1 // unlimited impact
            });
            zeroForOne = !zeroForOne;
            swapRouter.swap(poolKey, params, testSettings, ZERO_BYTES);
        }
    }

    function testSwap() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        (MockERC20 token0, MockERC20 token1) = deployTokens();

        bytes memory ZERO_BYTES = new bytes(0);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        int24 tickSpacing = 60;

        // initialize the pool
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, tickSpacing, IHooks(address(0))
        );

        // add full range liquidity to the pool
        lpRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(tickSpacing), TickMath.maxUsableTick(tickSpacing), 1 ether, 0
            ),
            ZERO_BYTES
        );

        // swap some tokens
        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;

        // 10 exactIn swaps altering zeroForOne each time
        IPoolManager.SwapParams memory params;
        for (uint256 i = 0; i < 10; i++) {
            console.log("Swapping ExactIn", i);
            console.log("zeroForOne", zeroForOne);
            params = IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1 // unlimited impact
            });

            zeroForOne = !zeroForOne;
        }

        // 10 exactOut swaps alterting zeroForOne each time
        for (uint256 i = 0; i < 10; i++) {
            console.log("Swapping ExactOut", i);
            console.log("zeroForOne", zeroForOne);
            params = IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1 // unlimited impact
            });
            zeroForOne = !zeroForOne;
            swapRouter.swap(poolKey, params, testSettings, ZERO_BYTES);
        }

        vm.stopBroadcast();
    }
}   
