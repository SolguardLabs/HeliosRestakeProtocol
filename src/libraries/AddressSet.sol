// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library AddressSet {
    error ZeroAddress();
    error IndexOutOfBounds(uint256 index, uint256 length);

    struct Set {
        address[] values;
        mapping(address => uint256) indexPlusOne;
    }

    function add(Set storage set, address value) internal returns (bool inserted) {
        if (value == address(0)) revert ZeroAddress();
        if (set.indexPlusOne[value] != 0) return false;
        set.values.push(value);
        set.indexPlusOne[value] = set.values.length;
        return true;
    }

    function remove(Set storage set, address value) internal returns (bool removed) {
        uint256 indexPlusOne = set.indexPlusOne[value];
        if (indexPlusOne == 0) return false;

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = set.values.length - 1;
        if (index != lastIndex) {
            address lastValue = set.values[lastIndex];
            set.values[index] = lastValue;
            set.indexPlusOne[lastValue] = indexPlusOne;
        }

        set.values.pop();
        delete set.indexPlusOne[value];
        return true;
    }

    function contains(Set storage set, address value) internal view returns (bool) {
        return set.indexPlusOne[value] != 0;
    }

    function length(Set storage set) internal view returns (uint256) {
        return set.values.length;
    }

    function at(Set storage set, uint256 index) internal view returns (address) {
        if (index >= set.values.length) revert IndexOutOfBounds(index, set.values.length);
        return set.values[index];
    }

    function page(Set storage set, uint256 offset, uint256 limit)
        internal
        view
        returns (address[] memory result)
    {
        uint256 total = set.values.length;
        if (offset >= total) return new address[](0);
        uint256 end = offset + limit;
        if (end > total) end = total;

        result = new address[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            result[i - offset] = set.values[i];
        }
    }
}
