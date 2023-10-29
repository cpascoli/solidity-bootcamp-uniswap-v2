import { ethers } from "hardhat";
import { BigNumber, constants } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

import PAIR_ABI from "../../artifacts/contracts/SwapPool.sol/SwapPool.json";

export type Bid = { price: number, timestamp: number }
export const day = 24 * 60 * 60;

/**
 * Increases the time of the test blockchain by the given number of seconds
 * @param secs the number of seconds to wait
 */
export const waitSeconds = async  (secs: number) => {
	const ts = (await time.latest()) + secs
	await time.increaseTo(ts)
}

/**
 * Converts from wei to units.
 * @param amount the amount in wei to convert in units
 * @returns the amount in units as a number
 */
export const toUnits = (amount: BigNumber) : number => {
    return Number(ethers.utils.formatUnits(amount, 18));
}

/**
 * Converts from units to wei.
 * @param units the amount of units to convert in wei
 * @returns the unit value in wei as a BigNumber
 */
export const toWei = (units: number) : BigNumber => {
    return ethers.utils.parseUnits( units.toString(), 18); 
}

/**
 * @returns the timestamp of the last mined block.
 */
export const getLastBlockTimestamp = async () => {
    return (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp
}

/**
 * @returns an object containing an instance of the MyNFT contract
 */
export const deployContracts = async () => {

    const [ owner, user0, user1, user2 ] = await ethers.getSigners();

    // factory
    const SwapPoolFactory = await ethers.getContractFactory("SwapPoolFactory");
    const swapPoolFactory = await SwapPoolFactory.deploy(owner.address); // owner is the receiver of the fees

    // token pair
    const Token20 = await ethers.getContractFactory("Token20");
    const token1 = await Token20.deploy(toWei(1_000_000), "Token A", "A");
    const token2 = await Token20.deploy(toWei(200_000), "Token B", "B");
    await swapPoolFactory.createPair(token1.address, token2.address)
    const pairAddress = await swapPoolFactory.allPairs(0)
    const uniswapV2Pair = new ethers.Contract(pairAddress, PAIR_ABI.abi, owner);

    // flashloan client
    const FlashLoanClient = await ethers.getContractFactory("FlashLoanClient");
    const flashLoanClient = await FlashLoanClient.deploy(uniswapV2Pair.address);


    // transfer some tokens to user0
    await token1.connect(owner).transfer(user0.address, toWei(100))
    await token2.connect(owner).transfer(user0.address, toWei(100))

    return { swapPoolFactory, uniswapV2Pair, flashLoanClient, token1, token2, owner, user0, user1, user2 };
}