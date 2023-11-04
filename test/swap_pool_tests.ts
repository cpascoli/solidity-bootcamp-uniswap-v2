import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { deployContracts } from "./helpers/test_helpers";


describe("SwapPair Config", function () {

    it("has the expected factory", async function () {
        const { swapPoolFactory, swapPair } = await loadFixture(deployContracts);
        expect(await swapPair.factory()).to.be.equal( swapPoolFactory.address )
    });

    it("has no reserves", async function () {
        const { swapPoolFactory, swapPair } = await loadFixture(deployContracts);
        expect(await swapPair.getReserves()).to.deep.equal( [0, 0, 0] )
    });

});