// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;


library UQ112x112 {

    struct uq112x112 {
        uint224 _x;
    }

    /// @notice Returns a uq112x112 which represents the ratio of the numerator to the denominator.
    /// @dev Equivalent to encode(numerator).div(denominator)
    function fraction(uint112 numerator, uint112 denominator) internal pure returns (uq112x112 memory) {
        require(denominator > 0, "FixedPoint: DIV_BY_ZERO");

        return uq112x112((uint224(numerator) << 112) / denominator);
    }

    /// @notice Decode a uq112x112 into a uint with 18 decimals of precision
    function decode(uq112x112 memory self) internal pure returns (uint) {
        // we only have 256 - 224 = 32 bits to spare, so scaling up by ~60 bits is dangerous
        // instead, get close to:
        //  (x * 1e18) >> 112
        // without risk of overflowing, e.g.:
        //  (x) / 2 ** (112 - lg(1e18))
        return uint(self._x) / 5192296858534816;
    }


}


// library UQ112x112 {
//     uint224 constant Q112 = 2**112;

//     // encode a uint112 as a UQ112x112
//     function encode(uint112 y) internal pure returns (uint224 z) {
//         z = uint224(y) * Q112; // never overflows
//     }

//     // divide a UQ112x112 by a uint112, returning a UQ112x112
//     function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
//         z = x / uint224(y);
//     }
// }
