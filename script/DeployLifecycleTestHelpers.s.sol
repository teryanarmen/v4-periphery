// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console2.sol";
import "forge-std/Script.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateView} from "../src/lens/StateView.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/src/test/PoolDonateTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract DeployLifecycleTestHelpers is Script {

    IPoolManager public manager;

    function setUp() public {
        uint256 chainId = block.chainid;
        if (chainId == 11155111) {
            manager = IPoolManager(vm.parseJsonAddress(vm.readFile("./script/parameters/sepolia.json"), ".PoolManager"));

        }
    }

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        PoolModifyLiquidityTest lpRouter = new PoolModifyLiquidityTest(manager);
        PoolSwapTest swapRouter = new PoolSwapTest(manager);
        PoolDonateTest donateRouter = new PoolDonateTest(manager);
        MockERC20 tokenA = new MockERC20("MockA", "A", 18);
        MockERC20 tokenB = new MockERC20("MockB", "B", 18);
        
        
        console2.log("PoolModifyLiquidityTest", address(lpRouter));
        console2.log("PoolSwapTest", address(swapRouter));
        console2.log("PoolDonateTest", address(donateRouter));
        console2.log("MockA", address(tokenA));
        console2.log("MockB", address(tokenB));

        vm.stopBroadcast();
    }
}
