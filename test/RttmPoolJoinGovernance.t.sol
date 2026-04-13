// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RttmPool} from "../src/RttmPool.sol";

contract MockERC20B is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev TDD: genesis, gated join, BPS thresholds, governable pool params.
contract RttmPoolJoinGovernanceTest is Test {
    RttmPool internal pool;
    MockERC20B internal token;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA901);
    address internal dave = address(0xDAFE);

    function setUp() public {
        token = new MockERC20B();
        pool = new RttmPool(
            "RttM Pool Share",
            "RTTM",
            IERC20(address(token)),
            address(this),
            3 ether,
            3 ether,
            100,
            5000,
            5000,
            1 wei,
            100,
            10
        );
        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);
        token.mint(carol, 1_000 ether);
        token.mint(dave, 1_000 ether);
    }

    function _approve(address u, uint256 a) internal {
        vm.prank(u);
        token.approve(address(pool), a);
    }

    function _genesis(address[] memory addrs, uint256[] memory amts) internal {
        for (uint256 i; i < addrs.length; ++i) {
            _approve(addrs[i], type(uint256).max);
        }
        pool.completeGenesis(addrs, amts);
    }

    function test_genesis_mintsMembersAndAllowsGovernance() public {
        address[] memory a = new address[](1);
        a[0] = alice;
        uint256[] memory m = new uint256[](1);
        m[0] = 10 ether;
        _genesis(a, m);

        assertTrue(pool.isMember(alice));
        assertEq(pool.balanceOf(alice), 10 ether);
    }

    function test_applyJoin_requires_not_member_and_deposit() public {
        address[] memory a = new address[](1);
        a[0] = alice;
        uint256[] memory m = new uint256[](1);
        m[0] = 10 ether;
        _genesis(a, m);

        _approve(carol, type(uint256).max);
        vm.prank(carol);
        pool.applyJoin(5 ether);
        assertEq(uint256(pool.joinApplicationStatus(carol)), uint256(RttmPool.JoinAppStatus.Pending));
        assertEq(pool.pendingJoinDeposit(carol), 5 ether);
        assertFalse(pool.isMember(carol));
    }

    function test_join_direct_reverts_use_apply() public {
        _approve(carol, type(uint256).max);
        vm.prank(carol);
        vm.expectRevert(RttmPool.RttmPool__UseApplyJoin.selector);
        pool.join(10 ether);
    }

    function test_approveJoin_after_majority_vote_mints_shares() public {
        address[] memory ad = new address[](2);
        ad[0] = alice;
        ad[1] = bob;
        uint256[] memory am = new uint256[](2);
        am[0] = 10 ether;
        am[1] = 10 ether;
        _genesis(ad, am);

        _approve(carol, type(uint256).max);
        vm.prank(carol);
        pool.applyJoin(10 ether);

        vm.roll(3);
        vm.prank(alice);
        uint256 pid = pool.proposeApproveJoin(carol);

        vm.prank(alice);
        pool.castVote(pid, 1);
        vm.prank(bob);
        pool.castVote(pid, 1);

        vm.roll(block.number + pool.votingPeriodBlocks() + 1);
        pool.execute(pid);

        assertTrue(pool.isMember(carol));
        assertGt(pool.balanceOf(carol), 0);
        assertEq(pool.pendingJoinDeposit(carol), 0);
    }

    function test_approveJoin_fails_below_join_approval_bps() public {
        address[] memory ad = new address[](2);
        ad[0] = alice;
        ad[1] = bob;
        uint256[] memory am = new uint256[](2);
        am[0] = 10 ether;
        am[1] = 10 ether;
        _genesis(ad, am);

        _approve(carol, type(uint256).max);
        vm.prank(carol);
        pool.applyJoin(10 ether);

        vm.roll(3);
        vm.prank(alice);
        uint256 pid = pool.proposeApproveJoin(carol);

        vm.prank(alice);
        pool.castVote(pid, 1);

        vm.roll(block.number + pool.votingPeriodBlocks() + 1);
        vm.expectRevert(RttmPool.RttmPool__ProposalNotPassed.selector);
        pool.execute(pid);
    }

    function test_setPoolParams_via_governance_changes_minimums() public {
        address[] memory ad = new address[](2);
        ad[0] = alice;
        ad[1] = bob;
        uint256[] memory am = new uint256[](2);
        am[0] = 10 ether;
        am[1] = 10 ether;
        _genesis(ad, am);

        RttmPool.PoolParams memory np = RttmPool.PoolParams({
            memberMinimum: 5 ether,
            joinMinimum: 5 ether,
            votingPeriodBlocks: 100,
            proposalPassBps: 5000,
            joinApprovalBps: 5000
        });
        bytes memory data = abi.encodeCall(RttmPool.setPoolParams, (np));

        vm.roll(3);
        vm.prank(alice);
        uint256 pid = pool.proposeExternalCall(address(pool), data);

        vm.prank(alice);
        pool.castVote(pid, 1);
        vm.prank(bob);
        pool.castVote(pid, 1);
        vm.roll(block.number + pool.votingPeriodBlocks() + 1);
        pool.execute(pid);

        assertEq(pool.memberMinimum(), 5 ether);
        assertEq(pool.joinMinimum(), 5 ether);
    }

    function test_proposal_pass_uses_custom_bps() public {
        address[] memory ad = new address[](3);
        ad[0] = alice;
        ad[1] = bob;
        ad[2] = carol;
        uint256[] memory am = new uint256[](3);
        am[0] = 20 ether;
        am[1] = 20 ether;
        am[2] = 20 ether;
        for (uint256 i; i < ad.length; ++i) {
            _approve(ad[i], type(uint256).max);
        }
        pool.completeGenesis(ad, am);

        RttmPool.PoolParams memory np = RttmPool.PoolParams({
            memberMinimum: 3 ether,
            joinMinimum: 3 ether,
            votingPeriodBlocks: 100,
            proposalPassBps: 6000,
            joinApprovalBps: 5000
        });
        bytes memory setBps = abi.encodeCall(RttmPool.setPoolParams, (np));

        vm.roll(3);
        vm.prank(alice);
        uint256 pidParams = pool.proposeExternalCall(address(pool), setBps);
        vm.prank(alice);
        pool.castVote(pidParams, 1);
        vm.prank(bob);
        pool.castVote(pidParams, 1);
        vm.roll(block.number + pool.votingPeriodBlocks() + 1);
        pool.execute(pidParams);

        address sink = address(0x5151);
        bytes memory xfer = abi.encodeCall(IERC20.transfer, (sink, 1 ether));

        vm.roll(block.number + 5);
        vm.prank(alice);
        uint256 pid = pool.proposeExternalCall(address(token), xfer);

        vm.prank(alice);
        pool.castVote(pid, 1);

        vm.roll(block.number + pool.votingPeriodBlocks() + 1);
        vm.expectRevert(RttmPool.RttmPool__ProposalNotPassed.selector);
        pool.execute(pid);
    }
}
