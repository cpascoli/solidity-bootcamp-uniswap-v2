import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployContracts, toUnits, toWei, getLastBlockTimestamp } from "./helpers/test_helpers";
import { Contract } from "ethers";


describe("Uniswap V2++", function () {

    describe("Pair Contract", function () {
        it("has the expected factory", async function () {
            const { uniswapV2Factory, uniswapV2Pair } = await loadFixture(deployContracts);
            expect(await uniswapV2Pair.factory()).to.be.equal( uniswapV2Factory.address )
        });

        it("has no reserves", async function () {
            const { uniswapV2Factory, uniswapV2Pair } = await loadFixture(deployContracts);
            expect(await uniswapV2Pair.getReserves()).to.deep.equal( [0, 0, 0] )
        });
    })


    describe("Adding liquidity", function () {

        it("can add to the reserves", async function () {
            const { uniswapV2Pair, token1, token2, user0 } = await loadFixture(deployContracts);
            const token1DepositAmount = toWei(100);
            const token2DepositAmount = toWei(10);

            await token1.connect(user0).approve(uniswapV2Pair.address, token1DepositAmount)
            await token2.connect(user0).approve(uniswapV2Pair.address, token2DepositAmount)

            const deadline = await getLastBlockTimestamp() + 100;

            // when adding the initial liquidity it transfers the desired amount of LP tokens
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
            
            expect(await uniswapV2Pair.balanceOf(user0.address)).to.be.greaterThan( 0 )

            const [reserve0, reserve1, _] = await uniswapV2Pair.getReserves();
            expect(reserve0).to.equal(token1DepositAmount)
            expect(reserve1).to.equal(token2DepositAmount)
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

            // verify (almost) all liquidity has been withdrawn
            const [reserve0, reserve1, _] = await uniswapV2Pair.getReserves();
            expect(reserve0).to.be.lessThan( toWei(0.00001) ); // 3163 wei
            expect(reserve1).to.lessThan( toWei(0.00001) ); // 317 wei

            // verify user0 token balances
            const withdrawnToken1 = balance1After.sub(balance1Before)
            const withdrawnToken2 = balance2After.sub(balance2Before)
            expect(withdrawnToken1).to.approximately( token1DepositAmount, 5000 );
            expect(withdrawnToken2).to.approximately( token2DepositAmount, 500 );
        });
       
    })


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

        it("can swap token A for token B", async function () {
   
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
       
    })


    describe("Flash Loan", function () {
        
        let uniswapV2Pair: Contract;
        let flashLoanClient: Contract;
        let token1: Contract;
        let token2: Contract;
        let owner: SignerWithAddress;
        let user0: SignerWithAddress;

        beforeEach(async function () {
            const data = await loadFixture(deployContracts);
            owner = data.owner
            uniswapV2Pair = data.uniswapV2Pair
            flashLoanClient = data.flashLoanClient
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

        it("can do a flash loan", async function () {
   
            const loanAmount = toWei(50);

            // transfer some tokens to pay loan fees to flashLoanClient
            await token1.connect(user0).transfer(flashLoanClient.address, toWei(1));

            // verify max flash loan 
            const maxLoan = await uniswapV2Pair.maxFlashLoan(token1.address);
            expect(maxLoan).to.equal(toWei(100))

            // verify max fees 
            const fees = await uniswapV2Pair.flashFee(token1.address, loanAmount);
            expect(fees).to.equal(toWei(0.15))

            // perform flash loan
            await flashLoanClient.connect(user0).flashLoan(token1.address, loanAmount)

            // verify loan + fees was repaid 
            expect(await token1.balanceOf(flashLoanClient.address)).to.equal(toWei(1 - 0.15))
        });
       
    })

});