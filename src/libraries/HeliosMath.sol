// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { HeliosConstants } from "../types/HeliosTypes.sol";

library HeliosMath {
    error DivisionByZero();
    error BpsOutOfRange(uint256 value);

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function mulDivDown(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) revert DivisionByZero();
        return x * y / denominator;
    }

    function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) revert DivisionByZero();
        if (x == 0 || y == 0) return 0;
        return (x * y - 1) / denominator + 1;
    }

    function applyBps(uint256 amount, uint256 bps) internal pure returns (uint256) {
        if (bps > HeliosConstants.BPS) revert BpsOutOfRange(bps);
        return amount * bps / HeliosConstants.BPS;
    }

    function complementBps(uint256 amount, uint256 bps) internal pure returns (uint256) {
        if (bps > HeliosConstants.BPS) revert BpsOutOfRange(bps);
        return amount - applyBps(amount, bps);
    }

    function toRay(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) revert DivisionByZero();
        return numerator * HeliosConstants.RAY / denominator;
    }

    function fromRay(uint256 value, uint256 ray) internal pure returns (uint256) {
        return value * ray / HeliosConstants.RAY;
    }

    function boundBps(uint256 value, uint256 maximum) internal pure returns (uint256) {
        if (maximum > HeliosConstants.BPS) revert BpsOutOfRange(maximum);
        return value > maximum ? maximum : value;
    }
}
