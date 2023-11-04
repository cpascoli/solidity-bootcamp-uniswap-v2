import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployContracts, toUnits, toWei, getLastBlockTimestamp } from "./helpers/test_helpers";
import { Contract } from "ethers";


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

    it("can take a flash loan on token 0", async function () {
        const loanAmount = toWei(50);

        // verify max flash loan 
        const maxLoan = await uniswapV2Pair.maxFlashLoan(token1.address);
        expect(maxLoan).to.equal(toWei(100))

        // verify max fees 
        const fees = await uniswapV2Pair.flashFee(token1.address, loanAmount);
        expect(fees).to.equal(toWei(0.15)) // fees: 0.3% of 50 units is 0.15 units

        // transfer some tokens to pay loan fees to flashLoanClient
        await token1.connect(user0).transfer(flashLoanClient.address, fees);

        // perform flash loan
        await flashLoanClient.connect(user0).flashLoan(token1.address, loanAmount)

        // verify loan + fees was repaid 
        expect(await token1.balanceOf(flashLoanClient.address)).to.equal(0)
    })

    it("can take a flash loan on token 1", async function () {
        const loanAmount = toWei(5);

        // verify max flash loan 
        const maxLoan = await uniswapV2Pair.maxFlashLoan(token2.address);
        expect(maxLoan).to.equal(toWei(10))

        // verify max fees 
        const fees = await uniswapV2Pair.flashFee(token2.address, loanAmount);
        expect(fees).to.equal(toWei(0.015)) // fees: 0.3% of 5 is 0.015

        // transfer some tokens to pay loan fees to flashLoanClient
        await token2.connect(user0).transfer(flashLoanClient.address, fees);

        // perform flash loan
        await flashLoanClient.connect(user0).flashLoan(token2.address, loanAmount)

        // verify loan + fees was repaid 
        expect(await token2.balanceOf(flashLoanClient.address)).to.equal(toWei(0))
    })
    
});
