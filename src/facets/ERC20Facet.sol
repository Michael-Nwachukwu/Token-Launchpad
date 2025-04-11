// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/Ownable.sol";
import "../libraries/Erc20.sol";

/**
 * @title ProjectToken
 * @dev ERC20 token created for each project
 */
contract TokenFacet is ERC20 {
    constructor(string memory name, string memory symbol, address initialOwner) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
