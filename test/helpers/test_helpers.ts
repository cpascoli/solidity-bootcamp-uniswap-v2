import { ethers } from "hardhat";
import { BigNumber, Contract, constants } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import PAIR_ABI from "../../artifacts/contracts/SwapPair.sol/SwapPair.json";

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
    const SwapPairFactory = await ethers.getContractFactory("SwapPairFactory");
    const swapPairFactory = await SwapPairFactory.deploy(owner.address); // owner is the receiver of the fees

    // token pair
    const Token20 = await ethers.getContractFactory("Token20");
    const tokenA = await Token20.deploy(toWei(1_000_000), "Token A", "A");
    const tokenB = await Token20.deploy(toWei(200_000), "Token B", "B");
    await swapPairFactory.createPair(tokenA.address, tokenB.address)
    const pairAddress = await swapPairFactory.allPairs(0)
    const swapPair = new ethers.Contract(pairAddress, PAIR_ABI.abi, owner);

    // flashloan client
    const FlashLoanClient = await ethers.getContractFactory("FlashLoanClient");
    const flashLoanClient = await FlashLoanClient.deploy(swapPair.address);

    // return tokens ordered as in the pool
    const token1 = swapPair.token0() == tokenA.address ? tokenA : tokenB;
    const token2 = swapPair.token1() == tokenB.address ? tokenB : tokenA;

    // transfer some tokens to user0
    await token1.connect(owner).transfer(user0.address, toWei(100))
    await token2.connect(owner).transfer(user0.address, toWei(100))

    return { swapPairFactory, swapPair, flashLoanClient, token1, token2, owner, user0, user1, user2 };
}


export const makeSwap = async (
    tokenInAmount: BigNumber, 
    amountOutMin: BigNumber, 
    tokoenIn: Contract,
    tokenOut: Contract,
    swapPair: Contract,
    user: SignerWithAddress,
) => {
    // approve tokenIn transfer
    await tokoenIn.connect(user).approve(swapPair.address, tokenInAmount)
    
    // perform the swap
    const deadline = await getLastBlockTimestamp() + 100;
    await swapPair.connect(user).swapExactTokensForTokens(
        tokenInAmount, // amountIn
        amountOutMin,   // amountOutMin
        tokoenIn.address, // tokenIn
        tokenOut.address,  // tokenOut
        user.address,
        deadline
    )
}