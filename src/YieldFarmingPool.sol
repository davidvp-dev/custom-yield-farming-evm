// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title YieldFarmingPool
 * @dev Implementation of the yield farming pool contract.
 */
contract YieldFarmingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    constructor() Ownable (msg.sender) {
        
    }
}