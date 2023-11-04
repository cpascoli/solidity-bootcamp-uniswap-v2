import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { deployContracts } from "./helpers/test_helpers";


describe("SwapPair Config", function () {

    it("has the expected factory", async function () {
        const { swapPoolFactory, swapPair } = await loadFixture(deployContracts);
        expect(await swapPair.factory()).to.be.equal( swapPoolFactory.address )
    });

    it("has no reserves", async function () {
        const { swapPair } = await loadFixture(deployContracts);
        expect(await swapPair.getReserves()).to.deep.equal( [0, 0, 0] )
    });

    it("reverts if initialized twice", async function () {
        const { swapPair, token1, token2 } = await loadFixture(deployContracts);
        await expect( swapPair.initialize(token1.address, token2.address) ).to.be.revertedWith("Initializable: contract is already initialized")
    });

});