import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployContracts, toUnits, toWei, getLastBlockTimestamp } from "./helpers/test_helpers";
import { Contract } from "ethers";


describe("Swaps", function () {
    
    let uniswapV2Pair: Contract;
    let token1: Contract;
    let token2: Contract;
    let owner: SignerWithAddress;
    let user0: SignerWithAddress;

    beforeEach(async function () {
        const data = await loadFixture(deployContracts);
        owner = data.owner
        uniswapV2Pair = data.uniswapV2Pair
        token1 = data.token1
        token2 = data.token2
        user0 = data.user0

        const token1DepositAmount = toWei(100);
        const token2DepositAmount = toWei(10);

        await token1.connect(owner).approve(uniswapV2Pair.address, token1DepositAmount)
        await token2.connect(owner).approve(uniswapV2Pair.address, token2DepositAmount)

        const deadline = await getLastBlockTimestamp() + 100;

        // when adding the initial liquidity it transfers the desired amount of LP tokens
        await uniswapV2Pair.connect(owner).addLiquidity(
            token1.address, // tokenA
            token2.address, // tokenB
            token1DepositAmount,  // amountADesired
            token2DepositAmount,   // amountBDesired
            toWei(10),  // amountAMin
            toWei(1),   // amountBMin
            user0.address, // to
            deadline
        )

        return { uniswapV2Pair, token1, token2, user0 }
    })

    it("can swap token 1 for token 2", async function () {

        const tokenInAmount = toWei(10);    // amount of token1 spent
        const amountOutMin = toWei(0.9)     // min amount of token2 expected to be received

        // approve token1 transfer
        await token1.connect(user0).approve(uniswapV2Pair.address, tokenInAmount)
        
        // get token balances before swap
        const balance1Before = await token1.balanceOf(user0.address);
        const balance2Before = await token2.balanceOf(user0.address);

        const deadline = await getLastBlockTimestamp() + 100;

        // perform the swap
        await uniswapV2Pair.connect(user0).swapExactTokensForTokens(
            tokenInAmount, // amountIn
            amountOutMin,   // amountOutMin
            token1.address, // tokenIn
            token2.address,  // tokenOut
            user0.address,
            deadline
        )

        // calcualte tokens spent and received
        const balance1After = await token1.balanceOf(user0.address);
        const balance2After = await token2.balanceOf(user0.address);
        
        const tokensSpent = balance1Before.sub(balance1After)
        const tokensReceived = balance2After.sub(balance2Before)

        expect(tokensSpent).to.equal(tokenInAmount) // 10 token1
        expect(tokensReceived).to.be.greaterThanOrEqual(amountOutMin) // 0.9066108938801491 token2
    });

    it("can swap token 2 for token 1", async function () {

        const tokenInAmount = toWei(1);  // amount of token2 spent
        const amountOutMin = toWei(9)     // min amount of token1 expected to be received

        // approve token1 transfer
        await token2.connect(user0).approve(uniswapV2Pair.address, tokenInAmount)
        
        // get token balances before swap
        const balance2Before = await token2.balanceOf(user0.address);
        const balance1Before = await token1.balanceOf(user0.address);

        const deadline = await getLastBlockTimestamp() + 100;

        // perform the swap
        await uniswapV2Pair.connect(user0).swapExactTokensForTokens(
            tokenInAmount, // amountIn
            amountOutMin,   // amountOutMin
            token2.address, // tokenIn
            token1.address,  // tokenOut
            user0.address,
            deadline
        )

        // calcualte tokens spent and received
        const balance2After = await token2.balanceOf(user0.address);
        const balance1After = await token1.balanceOf(user0.address);
        
        const tokensSpent = balance2Before.sub(balance2After)
        const tokensReceived = balance1After.sub(balance1Before)

        expect(tokensSpent).to.equal(tokenInAmount) // 1 token2
        expect(tokensReceived).to.be.greaterThanOrEqual(amountOutMin) // 9.066108938801491 token1
    });
    
});