// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";

import { ISwapPoolPair } from "./interfaces/uniswap/ISwapPoolPair.sol";
import { ISwapPoolFactory } from "./interfaces/uniswap/ISwapPoolFactory.sol";
import { IERC3156FlashLender } from "./interfaces/flashloan/IERC3156FlashLender.sol";
import { IERC3156FlashBorrower } from "./interfaces/flashloan/IERC3156FlashBorrower.sol";

/// @title Liquidity Pool for swapping a pair of ERC20 tokens.
/// @dev This contract is based on Uniswap V2 implementation, wiith some modifications:
/// - Uses modern solidity version that does not require SafeMath.
/// - Use PRBMath fixed point library.
/// - Use Openzeppelin code, including ERC20, SafeTransfer, ReentrancyGuard, etc. 
/// - Use EIP 3156 instead of implementing a flash swap the way Uniswap does.
contract SwapPair is Initializable, ISwapPoolPair, ERC20, IERC3156FlashLender, ReentrancyGuard {

    using FixedPointMathLib for uint256;

    string public constant NAME = 'SwapPool LP Token';
    string public constant SYMBOL = 'SPLP';
    uint public constant MINIMUM_LIQUIDITY = 1e3;
    uint public constant SWAP_FEE = 30; // in basis point: 0.3%
    uint public constant SWAP_FEE_FACTOR = 1e4;

    address public immutable factory;
    address public token0;
    address public token1;
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint private reserve0;
    uint private reserve1;
    uint32 private blockTimestampLast;

    event Sync(uint reserve0, uint reserve1);
    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(address indexed sender, uint amount0In, uint amount1In, uint amount0Out, uint amount1Out, address indexed to);
   

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    constructor() ERC20() {
        factory = msg.sender;
    }


    /// @notice Initializer function that ptovides the addresses of the tokens to be swapped.
    /// @dev Called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external initializer {
        require(msg.sender == factory, 'Invalid Caller');
        token0 = _token0;
        token1 = _token1;
    }

    /// @notice Swaps an exact amount of 'input' tokens for an amount of 'output' tokens not below a minimum amount.
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address input,
        address output,
        address to,
        uint deadline
    ) external ensure(deadline) nonReentrant returns (uint amountOut) {
        amountOut = getAmountOut(amountIn, input, output);
        require(amountOut >= amountOutMin, 'Insufficient Output Amount');
        SafeERC20.safeTransferFrom(
            IERC20(input), msg.sender, address(this), amountIn
        );
        _swap(amountOut, input, output, to);
    }

    /// @notice Swaps an amount of 'input' tokens not greater than 'amountInMax' for an exact amount of 'output' tokens.
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address input,
        address output,
        address to,
        uint deadline
    ) external ensure(deadline) nonReentrant returns (uint amountIn) {
        amountIn = getAmountIn(amountOut, input, output);
        require(amountIn <= amountInMax, 'Excessive Input Amount');
        SafeERC20.safeTransferFrom(
            IERC20(input), msg.sender, address(this), amountIn
        );
        _swap(amountOut, input, output, to);
    }

    /// @notice Adds liquidity to the pool and mints share tokens.
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) nonReentrant returns (uint amountA, uint amountB, uint liquidity) {
       
        (uint reserveA, uint reserveB) = getReservesSorted(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'Insufficient B Amount');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'Insufficient A Amount');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }

        SafeERC20.safeTransferFrom(IERC20(tokenA), msg.sender, address(this), amountA);
        SafeERC20.safeTransferFrom(IERC20(tokenB), msg.sender, address(this), amountB);
        liquidity = _mintShares(to);
    }

    
    /// @notice Removes liquidity from the pool and burns share tokens.
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) nonReentrant returns (uint amountA, uint amountB) {

        SafeERC20.safeTransferFrom(
            IERC20(address(this)), msg.sender, address(this), liquidity
        );

        // burns liquidity and returns tokens
        (uint amount0, uint amount1) = _burnShares(to);

        (amountA, amountB) = tokenA == token0 && tokenB == token1 ? (amount0, amount1) :
                            tokenB == token0 && tokenA == token1  ? (amount1, amount0) : (0, 0);

        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }


    /// @notice Force balances to match reserves
    function skim(address to) external nonReentrant {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        SafeERC20.safeTransfer(IERC20(_token0), to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        SafeERC20.safeTransfer(IERC20(_token1), to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    /// @notice Force reserves to match balances
    function sync() external nonReentrant() {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }


    ///// IERC3156FlashLender /////

    /**
     * @dev The amount of currency available to be lent.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view returns (uint256) {
        return _maxFlashLoan(token);
    }

    /**
     * @dev The fee to be charged for a given loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) external view returns (uint256) {
        return _flashFee(token, amount);
    }

    /**
     * @notice Perform an ERC3156 flash loan for the token and amount provided.
     * @param receiver The receiver of the loan, must implement IERC3156FlashBorrower.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant returns (bool) {

        require(amount > 0, "Flash loan amount can't be zero");
        require (amount <= _maxFlashLoan(token), "Not enough reserves");
        // _flashFee reverts if token is not supported
        uint256 fee = _flashFee(token, amount);

        // token is token0 or token1
        IERC20 loanToken = token == token0 ? IERC20(token0) : IERC20(token1);

        // transfer the loan
        SafeERC20.safeTransfer(loanToken, address(receiver), amount);

        // canll IERC3156 callback
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == keccak256("ERC3156FlashBorrower.onFlashLoan"),
            "IERC3156: Callback failed"
        );

        // get the loan + fee back
        SafeERC20.safeTransferFrom(loanToken, address(receiver), address(this), amount + fee);

        // update reserves
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1, reserve0, reserve1);

        return true;
    }


    // **** PUBLIC FUNCTIONS ****

    /// @notice Returns the name of the pool' share token.
    function name() public pure override returns (string memory) {
        return NAME;
    }

    /// @notice Returns the symbol of the pool' share token.
    function symbol() public pure override returns (string memory) {
        return SYMBOL;
    }

    /// @notice Returns the pool's reserves and the timestamp of the last block when the reserves were updated.
    function getReserves() public view returns (uint _reserve0, uint _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    
    // **** PRIVATE FUNCTIONS ****

    /// @notice Sync the reserves to the balances provided and update the oracle price accumulators.
    function _update(uint balance0, uint balance1, uint _reserve0, uint _reserve1) private {
        
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);

        unchecked {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                // update the sum of the price for every second in the entire history of the contract.
                // https://docs.uniswap.org/contracts/v2/concepts/core-concepts/oracles
                price0CumulativeLast +=  _reserve1.divWadUp(_reserve0) * timeElapsed;
                price1CumulativeLast +=  _reserve0.divWadUp(_reserve1) * timeElapsed;
            }
        }

        reserve0 = balance0;
        reserve1 = balance1;
        blockTimestampLast = blockTimestamp;

        emit Sync(reserve0, reserve1);
    }


    /// @notice If fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint _reserve0, uint _reserve1) private returns (bool feeOn) {
        address feeTo = ISwapPoolFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = FixedPointMathLib.sqrt(_reserve0 * _reserve1);
                uint rootKLast = FixedPointMathLib.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply() * (rootK - rootKLast);
                    uint denominator = (rootK * 5) + rootKLast;
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }


    /// @notice Mint shares to the recipient address equivalent to the liquidity provided.
    function _mintShares(address recipient) private returns (uint liquidity) {
        (uint _reserve0, uint _reserve1,) = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0 - _reserve0;
        uint amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        
        if (_totalSupply == 0) {
            liquidity = FixedPointMathLib.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
           _mint(address(0xDEAD), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = FixedPointMathLib.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
        }
        require(liquidity > 0, 'INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(recipient, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        
        if (feeOn){
            // reserve0 and reserve1 are up-to-date
            kLast = uint(reserve0) * reserve1;
        }

        emit Mint(msg.sender, amount0, amount1);
    }


    /// @notice burns all the shares transferred to the contract and returns the liquidity to the recipient address.
    function _burnShares(address recipient) private returns (uint amount0, uint amount1) {
        (uint _reserve0, uint _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));

        uint liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity * balance0 / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * balance1 / _totalSupply; // using balances ensures pro-rata distribution
        
        require(amount0 > 0 && amount1 > 0, 'Insufficient Liquidity Burned');

        _burn(address(this), liquidity);

        require(totalSupply() >= MINIMUM_LIQUIDITY, "Below minimum shares balance");

        SafeERC20.safeTransfer(IERC20(_token0), recipient, amount0);
        SafeERC20.safeTransfer(IERC20(_token1), recipient, amount1);

        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);

        if (feeOn) {
            // reserve0 and reserve1 are up-to-date
            kLast = uint(reserve0) * reserve1;
        }

        emit Burn(msg.sender, amount0, amount1, recipient);
    }


    /// @notice Send 'amountOut' of 'output' tokens to the recipient address and updates the reserves.
    function _swap(uint amountOut, address input, address output, address recipient) private {

        (uint amount0Out, uint amount1Out) = input == token0 && output == token1 ? (uint(0), amountOut) :
            input == token1 && output == token0 ? (amountOut, uint(0)) : (uint(0), uint(0));
        
        require(amount0Out > 0 || amount1Out > 0, 'Insufficient Output Amount');
        (uint _reserve0, uint _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'Insufficeint Liquidity');

        uint balance0;
        uint balance1;

        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;

        if (amount0Out > 0) SafeERC20.safeTransfer(IERC20(_token0), recipient, amount0Out);
        if (amount1Out > 0) SafeERC20.safeTransfer(IERC20(_token1), recipient, amount1Out);
        
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }

        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'Insufficient Input Amount');

        // { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        // uint balance0Adjusted = (balance0 * SWAP_FEE_FACTOR) - (amount0In * SWAP_FEE); // 0.3% fee
        // uint balance1Adjusted = (balance1 * SWAP_FEE_FACTOR) - (amount1In * SWAP_FEE); // 0.3% fee
        // require(balance0Adjusted * balance1Adjusted >= uint(_reserve0) * _reserve1 * SWAP_FEE_FACTOR**2, 'Invalid K');
        // }

        _update(balance0, balance1, _reserve0, _reserve1);

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, recipient);
    }


    function _flashFee(address token, uint256 amount) private view returns(uint256) {
        require(token == token0 || token == token1, "Token not supported");

        return amount * SWAP_FEE / SWAP_FEE_FACTOR;
    }


    function _maxFlashLoan(address token) private view returns (uint256 reserve) {
        if (token == token0) {
            reserve = reserve0;
        }
        if (token == token1) {
            reserve = reserve1;
        }
    }


    /// @notice Given an output amount of an asset returns the maximum input amount of the other asset.
    /// @dev The ammountIn returned includes swap fees. 
    function getAmountIn(uint amountOut, address input, address output) private view returns (uint amountIn) {
        require(amountOut > 0, 'Insufficient Output Amount');
        (uint reserveIn, uint reserveOut) = getReservesSorted(input, output);
        require(reserveIn > 0 && reserveOut > 0, 'Insufficent Liquidity');

        uint numerator = reserveIn * amountOut * SWAP_FEE_FACTOR;
        uint denominator = (reserveOut - amountOut) * (SWAP_FEE_FACTOR - SWAP_FEE);

        amountIn = (numerator / denominator) + 1;
    }


    /// @notice Given an input amount of an asset returns the maximum output amount of the other asset.
    /// @dev The ammountOut returned is net of swap fees. 
    function getAmountOut(uint amountIn, address input, address output) private view returns (uint amountOut) {
        require(amountIn > 0, 'Insufficent Input Amount');
        (uint reserveIn, uint reserveOut) = getReservesSorted(input, output);
        require(reserveIn > 0 && reserveOut > 0, 'Insufficent Liquidity');

        uint amountInWithFee = amountIn * (SWAP_FEE_FACTOR - SWAP_FEE);
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * SWAP_FEE_FACTOR) + amountInWithFee;

        amountOut = numerator / denominator;
    }

     /// @notice Returns the reserves for a tokens pair sorted by token addresses. 
    function getReservesSorted(address tokenA, address tokenB) private view returns (uint reserveA, uint reserveB) {
        (reserveA, reserveB) = tokenA == token0 && tokenB == token1 ? (reserve0, reserve1) :
                                tokenA == token1 && tokenB == token0 ? (reserve1, reserve0) : (0, 0);
    }


    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) private pure returns (uint amountB) {
        require(amountA > 0, 'Insufficent Amount');
        require(reserveA > 0 && reserveB > 0, 'Insufficent Liquidity');
        amountB = amountA * reserveB / reserveA;
    }
}