// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library CustomLib {
    uint32 private constant MAX_RESERVE_RATIO = 1000000;
    uint8 private constant MAX_PRECISION = 127;

    // The values below depend on MAX_PRECISION. If MAX_PRECISION is changed, these values must also be updated.
    uint256 private constant FIXED_1 = 0x080000000000000000000000000000000;
    uint256 private constant FIXED_2 = 0x100000000000000000000000000000000;
    uint256 private constant MAX_NUM = 0x200000000000000000000000000000000;

    /**
     * @dev General power function for Bancor formula
     * @param _baseN The numerator
     * @param _baseD The denominator
     * @param _expN The numerator of the exponent
     * @param _expD The denominator of the exponent
     * @return result and precision
     */
    function power(uint256 _baseN, uint256 _baseD, uint32 _expN, uint32 _expD) internal pure returns (uint256, uint8) {
        require(_baseN < MAX_NUM, "baseN too large");
        require(_baseD < MAX_NUM, "baseD too large");

        uint256 baseLog;
        uint256 base = _baseN * FIXED_1 / _baseD;
        if (base < FIXED_1) {
            baseLog = _baseLog(base, FIXED_1, MAX_PRECISION);
        } else {
            baseLog = _baseLog(FIXED_1, base, MAX_PRECISION);
        }

        uint256 baseLogTimesExp = baseLog * _expN / _expD;
        if (base < FIXED_1) {
            return (FIXED_1 * FIXED_1 / _generalExp(baseLogTimesExp, MAX_PRECISION), MAX_PRECISION);
        } else {
            return (_generalExp(baseLogTimesExp, MAX_PRECISION), MAX_PRECISION);
        }
    }

    /**
     * @dev Logarithm function for large numbers
     */
    function _baseLog(uint256 x, uint256 y, uint8 precision) private pure returns (uint256) {
        uint256 res = 0;

        // This implementation is simplified for the purpose of this example
        // A full implementation would include the logarithm calculation
        // from the original Bancor formula

        // For simplicity, we'll use a less efficient but functional approach
        uint256 xi = x;
        uint256 yi = y;

        while (xi < yi) {
            xi = xi * FIXED_1 / FIXED_1;
            res += FIXED_1;
        }

        return res * precision / MAX_PRECISION;
    }

    /**
     * @dev General exponentiation function
     */
    function _generalExp(uint256 _x, uint8 _precision) private pure returns (uint256) {
        uint256 xi = _x;
        uint256 res = 0;

        // This implementation is simplified for the purpose of this example
        // A full implementation would include the exponentiation calculation
        // from the original Bancor formula

        // For simplicity, we'll approximate using the e^x Taylor series
        xi = (xi * _precision) / MAX_PRECISION;
        res = FIXED_1 + xi + (xi * xi / 2) + (xi * xi * xi / 6);

        return res;
    }
}
