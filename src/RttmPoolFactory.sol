// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RttmPool} from "./RttmPool.sol";

/// @notice Deploys `RttmPool` with this contract as `genesisAuthority`. Genesis members must `approve` the **pool**
///         address, then the pool creator calls `completeGenesisFor` (two-step flow).
contract RttmPoolFactory {
    mapping(address pool => address creator) public poolCreator;

    struct DeployConfig {
        string name;
        string symbol;
        address treasuryToken;
        uint256 memberMinimum;
        uint256 joinMinimum;
        uint256 votingPeriodBlocks;
        uint256 proposalPassBps;
        uint256 joinApprovalBps;
        uint256 duesAmount;
        uint256 duesPeriodSeconds;
        uint256 duesGraceSeconds;
    }

    event PoolDeployed(address indexed pool, address indexed treasury, address indexed creator);

    function createPool(DeployConfig calldata c) external returns (RttmPool pool) {
        pool = new RttmPool(
            c.name,
            c.symbol,
            IERC20(c.treasuryToken),
            address(this),
            c.memberMinimum,
            c.joinMinimum,
            c.votingPeriodBlocks,
            c.proposalPassBps,
            c.joinApprovalBps,
            c.duesAmount,
            c.duesPeriodSeconds,
            c.duesGraceSeconds
        );
        poolCreator[address(pool)] = msg.sender;
        emit PoolDeployed(address(pool), c.treasuryToken, msg.sender);
    }

    function completeGenesisFor(RttmPool pool, address[] calldata members, uint256[] calldata amounts) external {
        if (address(pool) == address(0)) revert RttmPoolFactory__ZeroPool();
        if (poolCreator[address(pool)] != msg.sender) revert RttmPoolFactory__NotCreator();
        if (pool.genesisAuthority() != address(this)) revert RttmPoolFactory__NotAuthority();
        pool.completeGenesis(members, amounts);
    }

    error RttmPoolFactory__ZeroPool();
    error RttmPoolFactory__NotAuthority();
    error RttmPoolFactory__NotCreator();
}
