import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { assert, expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployContracts, makeSwap, toUnits, toWei, getLastBlockTimestamp, waitSeconds } from "./helpers/test_helpers";
import { Contract } from "ethers";


describe("TWAP", function () {
    
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
        const token2DepositAmount = toWei(20);

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

    it("ptovides the cumulative price for token 0 and token 1", async function () {

        const [, , blockTimestamp_0] = await swapPair.getReserves()
        const price0_0 = await swapPair.price0CumulativeLast()
        const price1_0 = await swapPair.price1CumulativeLast()

        // wait 1 hours and synch prices
        await waitSeconds(60 * 60)
        await swapPair.sync()

        const [, , blockTimestamp_1] = await swapPair.getReserves()
        const price0_1 = await swapPair.price0CumulativeLast()
        const price1_1 = await swapPair.price1CumulativeLast()

        expect( price0_1 ).to.be.greaterThan(price0_0)
        expect( price1_1 ).to.be.greaterThan(price1_0)

        const interval_0 = blockTimestamp_1 - blockTimestamp_0
        expect( toUnits( price0_1.sub(price0_0).div(interval_0)) ).to.equal( 0.2 )
        expect( toUnits( price1_1.sub(price1_0).div(interval_0)) ).to.equal( 5 )

        // wait 2 hours and synch prices
        const interval = 2 * 60 * 60;
        await waitSeconds(interval)
        await swapPair.sync()

        const [, , blockTimestamp_2] = await swapPair.getReserves()
        const price0_2 = await swapPair.price0CumulativeLast()
        const price1_2 = await swapPair.price1CumulativeLast()

        expect( price0_2 ).to.be.greaterThan(price0_1)
        expect( price1_2 ).to.be.greaterThan(price1_1)

        // verify average price over 2 hours
        const interval_1 = blockTimestamp_2 - blockTimestamp_1
        expect( toUnits( price0_2.sub(price0_1).div(interval_1)) ).to.equal( 0.2 )
        expect( toUnits( price1_2.sub(price1_1).div(interval_1)) ).to.equal( 5 )
    });


    it("updates the cumulative price for token 0 and token 1", async function () {

        const [, , blockTimestamp_0] = await swapPair.getReserves()
        const price0_0 = await swapPair.price0CumulativeLast()
        const price1_0 = await swapPair.price1CumulativeLast()

        // wait 1 hours and synch prices
        await waitSeconds(60 * 60)
        await swapPair.sync()

        const [, , blockTimestamp_1] = await swapPair.getReserves()
        const price0_1 = await swapPair.price0CumulativeLast()
        const price1_1 = await swapPair.price1CumulativeLast()

        expect( price0_1 ).to.be.greaterThan(price0_0)
        expect( price1_1 ).to.be.greaterThan(price1_0)

        const interval_0 = blockTimestamp_1 - blockTimestamp_0
        expect( toUnits( price0_1.sub(price0_0).div(interval_0)) ).to.equal( 0.2 )
        expect( toUnits( price1_1.sub(price1_0).div(interval_0)) ).to.equal( 5 )

        // make a swap
        await makeSwap(toWei(10), toWei(0.9), token1, token2, swapPair, user0)
        
        // verify average price after 2 hours
        await waitSeconds(2 * 60 * 60)
        await swapPair.sync()

        // get new price
        const [, , blockTimestamp_2] = await swapPair.getReserves()
        const price0_2 = await swapPair.price0CumulativeLast()
        const price1_2 = await swapPair.price1CumulativeLast()

        expect( price0_2 ).to.be.greaterThan(price0_1)
        expect( price1_2 ).to.be.greaterThan(price1_1)
    
        const interval_1 = blockTimestamp_2 - blockTimestamp_1
        const price0 = toUnits(price0_2.sub(price0_1).div(interval_1))
        const price1 = toUnits(price1_2.sub(price1_1).div(interval_1))

        const [reserves0, reserves1, ] = await swapPair.getReserves()

        const expPrice0 = toUnits(toWei(reserves1).div(reserves0))
        const expPrice1 = toUnits(toWei(reserves0).div(reserves1))

        expect(price0).to.be.approximately(expPrice0, 0.001)
        expect(price1).to.be.approximately(expPrice1, 0.01)
    });

    
});
