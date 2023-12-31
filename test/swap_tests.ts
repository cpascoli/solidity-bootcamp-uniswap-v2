import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployContracts, toUnits, toWei, getLastBlockTimestamp, makeSwap } from "./helpers/test_helpers";
import { Contract } from "ethers";


describe("Swaps", function () {
    
    let swapPair: Contract;
    let token1: Contract;
    let token2: Contract;
    let owner: SignerWithAddress;
    let user0: SignerWithAddress;

    beforeEach(async function () {
        const data = await loadFixture(deployContracts);
        owner = data.owner
        swapPair = data.swapPair
        token1 = data.token1
        token2 = data.token2
        user0 = data.user0

        const token1DepositAmount = toWei(100);
        const token2DepositAmount = toWei(10);

        await token1.connect(owner).approve(swapPair.address, token1DepositAmount)
        await token2.connect(owner).approve(swapPair.address, token2DepositAmount)

        const deadline = await getLastBlockTimestamp() + 100;

        // when adding the initial liquidity it transfers the desired amount of LP tokens
        await swapPair.connect(owner).addLiquidity(
            token1.address, // tokenA
            token2.address, // tokenB
            token1DepositAmount,  // amountADesired
            token2DepositAmount,   // amountBDesired
            toWei(10),  // amountAMin
            toWei(1),   // amountBMin
            user0.address, // to
            deadline
        )

        return { swapPair, token1, token2, user0 }
    })

    it("swaps token 0 for token 1", async function () {

        const tokenInAmount = toWei(10);  // amount of token1 spent
        const amountOutMin = toWei(0.9)   // min amount of token2 expected to be received

        // approve token1 transfer
        await token1.connect(user0).approve(swapPair.address, tokenInAmount)
        
        // get token balances before swap
        const balance1Before = await token1.balanceOf(user0.address);
        const balance2Before = await token2.balanceOf(user0.address);

        // perform the swap
        await makeSwap(tokenInAmount, amountOutMin, token1, token2, swapPair, user0)

        // calcualte tokens spent and received
        const balance1After = await token1.balanceOf(user0.address);
        const balance2After = await token2.balanceOf(user0.address);
        
        const tokensSpent = balance1Before.sub(balance1After)
        const tokensReceived = balance2After.sub(balance2Before)

        expect(tokensSpent).to.equal(tokenInAmount)
        expect(tokensReceived).to.be.greaterThanOrEqual(amountOutMin)
    });

    it("swaps token 1 for token 0", async function () {

        const tokenInAmount = toWei(1);  // amount of token2 spent
        const amountOutMin = toWei(9)    // min amount of token1 expected to be received

        // approve token1 transfer
        await token2.connect(user0).approve(swapPair.address, tokenInAmount)
        
        // get token balances before swap
        const balance2Before = await token2.balanceOf(user0.address);
        const balance1Before = await token1.balanceOf(user0.address);

        // perform the swap
        await makeSwap(tokenInAmount, amountOutMin, token2, token1, swapPair, user0)

        // calcualte tokens spent and received
        const balance2After = await token2.balanceOf(user0.address);
        const balance1After = await token1.balanceOf(user0.address);
        
        const tokensSpent = balance2Before.sub(balance2After)
        const tokensReceived = balance1After.sub(balance1Before)

        expect(tokensSpent).to.equal(tokenInAmount)
        expect(tokensReceived).to.be.greaterThanOrEqual(amountOutMin)
    });

    it("reverts when swap is expired", async function () {
        await token1.connect(user0).approve(swapPair.address, toWei(10))
    
        const deadline = await getLastBlockTimestamp() - 1;
        await expect(
            swapPair.connect(user0).swapExactTokensForTokens(
                toWei(10), // amountIn
                toWei(0.9),   // amountOutMin
                token1.address, // tokenIn
                token2.address,  // tokenOut
                user0.address,
                deadline
            )
        ).to.be.revertedWithCustomError(swapPair, "TransactionExpired")
    });
    
});
