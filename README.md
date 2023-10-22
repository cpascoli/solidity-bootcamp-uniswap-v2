# RareSkills Advanced Solidity Bootcamp - week 3


A remake of [Uniswap V2 core](https://github.com/Uniswap/v2-core/tree/master/contracts) where the following changes are made:

- Use solidity 0.8.0 or higher, don’t use SafeMath
- Use an existing fixed point library, but don’t use the Uniswap one.
- Use Openzeppelin’s or Solmate’s safeTransfer instead of building it from scratch like Unisawp does
- Instead of implementing a flash swap the way Uniswap does, use EIP 3156.
