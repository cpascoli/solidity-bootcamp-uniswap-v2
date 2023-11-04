import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { deployContracts } from "./helpers/test_helpers";


describe("SwapPair Config", function () {

    it("has the expected factory", async function () {
        const { swapPoolFactory, uniswapV2Pair } = await loadFixture(deployContracts);
        expect(await uniswapV2Pair.factory()).to.be.equal( swapPoolFactory.address )
    });

    it("has no reserves", async function () {
        const { swapPoolFactory, uniswapV2Pair } = await loadFixture(deployContracts);
        expect(await uniswapV2Pair.getReserves()).to.deep.equal( [0, 0, 0] )
    });

});