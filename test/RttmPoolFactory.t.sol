// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RttmPool} from "../src/RttmPool.sol";
import {RttmPoolFactory} from "../src/RttmPoolFactory.sol";

contract MockTok is ERC20 {
    constructor() ERC20("T", "T") {}

    function mint(address to, uint256 a) external {
        _mint(to, a);
    }
}

contract RttmPoolFactoryTest is Test {
    MockTok internal token;
    RttmPoolFactory internal factory;
    address internal alice = address(0xA11CE);

    function setUp() public {
        token = new MockTok();
        factory = new RttmPoolFactory();
        token.mint(alice, 100 ether);
    }

    function test_create_then_completeGenesis() public {
        RttmPoolFactory.DeployConfig memory c = RttmPoolFactory.DeployConfig({
            name: "P",
            symbol: "P",
            treasuryToken: address(token),
            memberMinimum: 1 ether,
            joinMinimum: 1 ether,
            votingPeriodBlocks: 10,
            proposalPassBps: 5000,
            joinApprovalBps: 5000,
            duesAmount: 0,
            duesPeriodSeconds: 0,
            duesGraceSeconds: 0
        });
        vm.prank(alice);
        RttmPool pool = factory.createPool(c);

        vm.prank(alice);
        token.approve(address(pool), 10 ether);

        address[] memory m = new address[](1);
        m[0] = alice;
        uint256[] memory a = new uint256[](1);
        a[0] = 10 ether;

        vm.prank(alice);
        factory.completeGenesisFor(pool, m, a);

        assertTrue(pool.isMember(alice));
        assertTrue(pool.genesisCompleted());
    }

    function test_completeGenesisFor_non_creator_reverts() public {
        RttmPoolFactory.DeployConfig memory c = RttmPoolFactory.DeployConfig({
            name: "P",
            symbol: "P",
            treasuryToken: address(token),
            memberMinimum: 1 ether,
            joinMinimum: 1 ether,
            votingPeriodBlocks: 10,
            proposalPassBps: 5000,
            joinApprovalBps: 5000,
            duesAmount: 0,
            duesPeriodSeconds: 0,
            duesGraceSeconds: 0
        });
        vm.prank(alice);
        RttmPool pool = factory.createPool(c);

        address[] memory m = new address[](1);
        m[0] = alice;
        uint256[] memory a = new uint256[](1);
        a[0] = 1 ether;

        vm.expectRevert(RttmPoolFactory.RttmPoolFactory__NotCreator.selector);
        factory.completeGenesisFor(pool, m, a);
    }
}
