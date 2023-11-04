# RareSkills Advanced Solidity Bootcamp - Uniswap


A remake of [Uniswap V2 core](https://github.com/Uniswap/v2-core/tree/master/contracts) where the following changes are made:

- Using solidity 0.8.0 or higher, not using SafeMath.
- Use [PRBMath](https://github.com/PaulRBerg/prb-math) fixed point library.
- Use Openzeppelin’s SafeTransfer instead of building it from scratch like Unisawp does
- Use EIP 3156 instead of implementing a flash swap the way Uniswap does.
