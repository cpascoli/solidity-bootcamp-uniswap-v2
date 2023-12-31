// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ISwapPoolFactory } from "./interfaces/uniswap/ISwapPoolFactory.sol";
import { ISwapPoolPair } from "./interfaces/uniswap/ISwapPoolPair.sol";
import { SwapPair } from "./SwapPair.sol";

/// @notice Factory contract used to create instances of SwapPair for a pair of tokens.
contract SwapPairFactory is ISwapPoolFactory {
    
    address public feeTo;
    address public feeToSetter;
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    error InvalidCaller();
    error ZeroAddress();
    error IdenticalAddresses();
    error PairExists();

    modifier onlyFeeToSetter {
        if (msg.sender != feeToSetter) revert InvalidCaller();
        _;
    }

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if(tokenA == tokenB) revert IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if(token0 == address(0)) revert ZeroAddress();
        if(getPair[token0][token1] != address(0)) revert PairExists();
        
        // deploy pair contract
        bytes memory bytecode = type(SwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        ISwapPoolPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external onlyFeeToSetter {
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external onlyFeeToSetter {
        feeToSetter = _feeToSetter;
    }
}