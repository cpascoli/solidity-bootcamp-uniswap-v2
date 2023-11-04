import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { assert, expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployContracts, toUnits, toWei, getLastBlockTimestamp, waitSeconds } from "./helpers/test_helpers";
import { Contract } from "ethers";


describe("TWAP", function () {
    
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
        const token2DepositAmount = toWei(20);

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

    it("has cumulative price for token 0 and token 1", async function () {

        const price0_0 = await uniswapV2Pair.price0CumulativeLast()
        const price1_0 = await uniswapV2Pair.price1CumulativeLast()

        // wait 1 hours and synch prices
        await waitSeconds(60 * 60)
        await uniswapV2Pair.sync()

        const price0_1 = await uniswapV2Pair.price0CumulativeLast()
        const price1_1 = await uniswapV2Pair.price1CumulativeLast()

        expect( price0_1 ).to.be.greaterThan(price0_0)
        expect( price1_1 ).to.be.greaterThan(price1_0)

        // wait 2 hours and synch prices
        const interval = 2 * 60 * 60;
        await waitSeconds(interval)
        await uniswapV2Pair.sync()

        const price0_2 = await uniswapV2Pair.price0CumulativeLast()
        const price1_2 = await uniswapV2Pair.price1CumulativeLast()

        expect( price0_2 ).to.be.greaterThan(price0_1)
        expect( price1_2 ).to.be.greaterThan(price1_1)

        // verify average price over 2 hours
        expect( toUnits( price0_2.sub(price0_1).div(interval)) ).to.approximately( 0.2, 0.1 )
        expect( toUnits( price1_2.sub(price1_1).div(interval)) ).to.approximately( 5, 0.1 )
    });

    
});
