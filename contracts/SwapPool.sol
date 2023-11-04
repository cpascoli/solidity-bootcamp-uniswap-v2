// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { PRBMathUD60x18Typed } from "prb-math/contracts/PRBMathUD60x18Typed.sol";
import { PRBMath } from "prb-math/contracts/PRBMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ISwapPoolPair } from "./interfaces/uniswap/ISwapPoolPair.sol";
import { ISwapPoolFactory } from "./interfaces/uniswap/ISwapPoolFactory.sol";
import { IERC3156FlashLender } from "./interfaces/flashloan/IERC3156FlashLender.sol";
import { IERC3156FlashBorrower } from "./interfaces/flashloan/IERC3156FlashBorrower.sol";
import { SwapPoolERC20 } from "./SwapPoolERC20.sol";

import "hardhat/console.sol";

contract SwapPool is ISwapPoolPair, SwapPoolERC20, IERC3156FlashLender, ReentrancyGuard {

    // using PRBMathUD60x18Typed for uint256;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;

    // addresses of token0 and token1 are sorted
    address public token0;
    address public token1;

    uint private reserve0;
    uint private reserve1;
    uint32 private blockTimestampLast;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    constructor() SwapPoolERC20() {
        factory = msg.sender;
    }

    function decimals() public view override(SwapPoolERC20, ISwapPoolPair) returns (uint8) {
        return super.decimals();
    }

    function DOMAIN_SEPARATOR() public view override(SwapPoolERC20, ISwapPoolPair) returns (bytes32) {
        return super.DOMAIN_SEPARATOR();
    }

    function PERMIT_TYPEHASH() public pure override(SwapPoolERC20, ISwapPoolPair) returns (bytes32) {
        return super.PERMIT_TYPEHASH();
    }

    function nonces(address owner) public view override(SwapPoolERC20, ISwapPoolPair) returns (uint) {
        return super.nonces(owner);
    }

    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override(SwapPoolERC20, ISwapPoolPair) {

        return super.permit(owner, spender, value, deadline, v, r, s);
    }

    function getReserves() public view returns (uint _reserve0, uint _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN');
        token0 = _token0;
        token1 = _token1;
    }

    // **** SWAPS ****

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address input,
        address output,
        address to,
        uint deadline
    ) external ensure(deadline) nonReentrant returns (uint amountOut) {
        amountOut = getAmountOut(amountIn, input, output);
        require(amountOut >= amountOutMin, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        SafeERC20.safeTransferFrom(
            IERC20(input), msg.sender, address(this), amountIn
        );
        _swap(amountOut, input, output, to);
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address input,
        address output,
        address to,
        uint deadline
    ) external ensure(deadline) nonReentrant returns (uint amountIn) {
        amountIn = getAmountIn(amountOut, input, output);
        require(amountIn <= amountInMax, 'UniswapV2: EXCESSIVE_INPUT_AMOUNT');
        SafeERC20.safeTransferFrom(
            IERC20(input), msg.sender, address(this), amountIn
        );
        _swap(amountOut, input, output, to);
    }


    // **** ADD LIQUIDITY ****

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
                require(amountBOptimal >= amountBMin, 'UniswapV2: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }

        SafeERC20.safeTransferFrom(IERC20(tokenA), msg.sender, address(this), amountA);
        SafeERC20.safeTransferFrom(IERC20(tokenB), msg.sender, address(this), amountB);
        liquidity = _mintShares(to);
    }

    // **** REMOVE LIQUIDITY ****

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


    // force balances to match reserves
    function skim(address to) external nonReentrant {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        SafeERC20.safeTransfer(IERC20(_token0), to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        SafeERC20.safeTransfer(IERC20(_token1), to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    // force reserves to match balances
    function sync() external nonReentrant() {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }


    // **** PRIVATE FUNCTIONS ****

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint _reserve0, uint _reserve1) private {

        console.log("_update balances:", balance0, balance1);
        console.log("_update reserves:", reserve0, _reserve1);

        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            
            // update the sum of the price for every second in the entire history of the contract.
            // https://docs.uniswap.org/contracts/v2/concepts/core-concepts/oracles
            
            price0CumulativeLast += PRBMathUD60x18Typed.div(
                PRBMath.UD60x18({ value: _reserve1}),
                PRBMath.UD60x18({ value: _reserve0})
            ).value * timeElapsed;

            price1CumulativeLast += PRBMathUD60x18Typed.div(
                PRBMath.UD60x18({ value: _reserve0}),
                PRBMath.UD60x18({ value: _reserve1})
            ).value * timeElapsed;

            console.log("_update price0:", timeElapsed, price0CumulativeLast);  // 720 2
            console.log("_update price1:", timeElapsed, price1CumulativeLast); // 18005 000000000000000000
        }

        reserve0 = balance0;
        reserve1 = balance1;
        blockTimestampLast = blockTimestamp;

        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint _reserve0, uint _reserve1) private returns (bool feeOn) {
        address feeTo = ISwapPoolFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0) * uint(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
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

    function _mintShares(address to) private returns (uint liquidity) {
        (uint _reserve0, uint _reserve1,) = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0 - _reserve0;
        uint amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
           _mint(address(0xDEAD), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        
        if (feeOn){
            // reserve0 and reserve1 are up-to-date
            kLast = uint(reserve0) * reserve1;
        }

        emit Mint(msg.sender, amount0, amount1);
    }


    function _burnShares(address to) private returns (uint amount0, uint amount1) {
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
        
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');

        _burn(address(this), liquidity);

        SafeERC20.safeTransfer(IERC20(_token0), to, amount0);
        SafeERC20.safeTransfer(IERC20(_token1), to, amount1);

        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);

        if (feeOn) {
            // reserve0 and reserve1 are up-to-date
            kLast = uint(reserve0) * reserve1;
        }

        emit Burn(msg.sender, amount0, amount1, to);
    }

  
    function _swap(uint amountOut, address input, address output, address to) private {

        (uint amount0Out, uint amount1Out) = input == token0 && output == token1 ? (uint(0), amountOut) :
            input == token1 && output == token0 ? (amountOut, uint(0)) : (uint(0), uint(0));
        
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint _reserve0, uint _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;

        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;

        if (amount0Out > 0) SafeERC20.safeTransfer(IERC20(_token0), to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) SafeERC20.safeTransfer(IERC20(_token1), to, amount1Out); // optimistically transfer tokens
        
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }

        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');

        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = (balance0 * 1000) - (amount0In * 3); // 0.3% fee
        uint balance1Adjusted = (balance1 * 1000) - (amount1In * 3); // 0.3% fee
        require(balance0Adjusted * balance1Adjusted >= uint(_reserve0) * _reserve1 * 1000**2, 'UniswapV2: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
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


    function _flashFee(address token, uint256 amount) private view returns(uint256) {
        require(token == token0 || token == token1, "Token not supported");

        return amount * 3 / 1000; // 0.3% fee
    }

    function _maxFlashLoan(address token) private view returns (uint256 reserve) {
        if (token == token0) {
            reserve = reserve0;
        }
        if (token == token1) {
            reserve = reserve1;
        }
    }


    function getAmountIn(uint amountOut, address input, address output) internal view returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint reserveIn, uint reserveOut) = getReservesSorted(input, output);
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * 997;

        amountIn = (numerator / denominator) + 1;
    }


    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, address input, address output) internal view returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        (uint reserveIn, uint reserveOut) = getReservesSorted(input, output);
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;

        amountOut = numerator / denominator;
    }

    function getReservesSorted(address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (reserveA, reserveB) = tokenA == token0 && tokenB == token1 ? (reserve0, reserve1) :
                            tokenA == token1 && tokenB == token0 ? (reserve1, reserve0) : (0, 0);
    }
}