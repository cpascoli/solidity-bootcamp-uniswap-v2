import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { deployContracts, toUnits, toWei, getLastBlockTimestamp } from "./helpers/test_helpers";


describe("Liquidity", function () {

    describe("Adding liquidity", function () {

        it("add tokens to the reserves", async function () {
            const { uniswapV2Pair, token1, token2, user0 } = await loadFixture(deployContracts);
            const token1DepositAmount = toWei(100);
            const token2DepositAmount = toWei(10);

            await token1.connect(user0).approve(uniswapV2Pair.address, token1DepositAmount)
            await token2.connect(user0).approve(uniswapV2Pair.address, token2DepositAmount)

            const deadline = await getLastBlockTimestamp() + 100;

            // add liquidity
            await uniswapV2Pair.connect(user0).addLiquidity(
                token1.address, // tokenA
                token2.address, // tokenB
                token1DepositAmount,  // amountADesired
                token2DepositAmount,   // amountBDesired
                toWei(10),  // amountAMin
                toWei(1),   // amountBMin
                user0.address, // to
                deadline
            )
            
            // verify reserves have been added
            const [reserve0, reserve1, _] = await uniswapV2Pair.getReserves();
            expect(reserve0).to.equal(token1DepositAmount)
            expect(reserve1).to.equal(token2DepositAmount)
        });

        it("returns LP tokens to the user", async function () {
            const { uniswapV2Pair, token1, token2, user0 } = await loadFixture(deployContracts);
            const token1DepositAmount = toWei(100);
            const token2DepositAmount = toWei(10);

            await token1.connect(user0).approve(uniswapV2Pair.address, token1DepositAmount)
            await token2.connect(user0).approve(uniswapV2Pair.address, token2DepositAmount)

            const deadline = await getLastBlockTimestamp() + 100;

            // add liquidity
            await uniswapV2Pair.connect(user0).addLiquidity(
                token1.address, // tokenA
                token2.address, // tokenB
                token1DepositAmount,  // amountADesired
                token2DepositAmount,   // amountBDesired
                toWei(10),  // amountAMin
                toWei(1),   // amountBMin
                user0.address, // to
                deadline
            )
            
            // verify user0 received the desired amount of LP tokens
            expect(await uniswapV2Pair.balanceOf(user0.address)).to.be.greaterThan( 0 )
        });
    })

    describe("Removing liquidity", function () {

        it("can remove the liquidity provided", async function () {
            const { uniswapV2Pair, token1, token2, user0 } = await loadFixture(deployContracts);

            const token1DepositAmount = toWei(100);
            const token2DepositAmount = toWei(10);

            await token1.connect(user0).approve(uniswapV2Pair.address, token1DepositAmount)
            await token2.connect(user0).approve(uniswapV2Pair.address, token2DepositAmount)

            const deadline1 = await getLastBlockTimestamp() + 100;

            // when adding the initial liquidity it transfers the desired amount of LP tokens
            await uniswapV2Pair.connect(user0).addLiquidity(
                token1.address, // tokenA
                token2.address, // tokenB
                token1DepositAmount,  // amountADesired
                token2DepositAmount,   // amountBDesired
                toWei(10),  // amountAMin
                toWei(1),   // amountBMin
                user0.address, // to
                deadline1
            );
            
            // approve LP token transfer
            const lpBalance = await uniswapV2Pair.balanceOf(user0.address);

            await uniswapV2Pair.connect(user0).approve(uniswapV2Pair.address, lpBalance);

            // remove liquidity
            const deadline2 = await getLastBlockTimestamp() + 100;
            await uniswapV2Pair.connect(user0).removeLiquidity(
                token1.address, // tokenA
                token2.address, // tokenB
                lpBalance,  // liquidity
                toWei(10 * 0.097),  // amountAMin
                toWei(1 * 0.097),   // amountBMin
                user0.address, // to
                deadline2
            )
    
            // verify (almost) all liquidity has been withdrawn
            const [reserve0, reserve1, _] = await uniswapV2Pair.getReserves();
            expect(reserve0).to.be.lessThan( toWei(0.00001) ); // 3163 wei
            expect(reserve1).to.lessThan( toWei(0.00001) ); // 317 wei
        });

        it("burns LP tokens", async function () {
            const { uniswapV2Pair, token1, token2, user0 } = await loadFixture(deployContracts);

            const token1DepositAmount = toWei(100);
            const token2DepositAmount = toWei(10);

            await token1.connect(user0).approve(uniswapV2Pair.address, token1DepositAmount)
            await token2.connect(user0).approve(uniswapV2Pair.address, token2DepositAmount)

            const deadline1 = await getLastBlockTimestamp() + 100;

            // when adding the initial liquidity it transfers the desired amount of LP tokens
            await uniswapV2Pair.connect(user0).addLiquidity(
                token1.address, // tokenA
                token2.address, // tokenB
                token1DepositAmount,  // amountADesired
                token2DepositAmount,   // amountBDesired
                toWei(10),  // amountAMin
                toWei(1),   // amountBMin
                user0.address, // to
                deadline1
            );
            
            // approve LP token transfer
            const lpBalance = await uniswapV2Pair.balanceOf(user0.address);

            await uniswapV2Pair.connect(user0).approve(uniswapV2Pair.address, lpBalance);

            // remove liquidity
            const balance1Before = await token1.balanceOf(user0.address);
            const balance2Before = await token2.balanceOf(user0.address);

            const deadline2 = await getLastBlockTimestamp() + 100;
            await uniswapV2Pair.connect(user0).removeLiquidity(
                token1.address, // tokenA
                token2.address, // tokenB
                lpBalance,  // liquidity
                toWei(10 * 0.097),  // amountAMin
                toWei(1 * 0.097),   // amountBMin
                user0.address, // to
                deadline2
            )
            const balance1After = await token1.balanceOf(user0.address);
            const balance2After = await token2.balanceOf(user0.address);

            // verify tokens for the liquidity removed are returned to the user
            expect(balance1After).to.approximately( balance1Before.add(token1DepositAmount), 5000 );
            expect(balance2After).to.approximately( balance2Before.add(token2DepositAmount), 500 );
        });
    })
    
});