// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RttmPool} from "../src/RttmPool.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RttmPoolTest is Test {
    RttmPool internal pool;
    MockERC20 internal token;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        token = new MockERC20();
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
    }

    function _approve(address user, uint256 amount) internal {
        vm.prank(user);
        token.approve(address(pool), amount);
    }

    function _genesis(address[] memory addrs, uint256[] memory amts) internal {
        for (uint256 i; i < addrs.length; ++i) {
            _approve(addrs[i], type(uint256).max);
        }
        pool.completeGenesis(addrs, amts);
    }

    function test_joinAndContribute_MintsSharesWithAutoDelegate() public {
        address[] memory a = new address[](1);
        a[0] = alice;
        uint256[] memory m = new uint256[](1);
        m[0] = 10 ether;
        _genesis(a, m);

        assertTrue(pool.isMember(alice));
        assertEq(pool.balanceOf(alice), 10 ether);
        assertEq(pool.getVotes(alice), 10 ether);
        assertTrue(pool.isDuesCurrent(alice));

        vm.prank(alice);
        pool.contribute(5 ether);

        assertEq(pool.balanceOf(alice), 15 ether);
        assertEq(pool.getVotes(alice), 15 ether);
        assertEq(token.balanceOf(address(pool)), 15 ether);
    }

    function test_payDues_extendsPaidUntilAndMintsShares() public {
        address[] memory a = new address[](1);
        a[0] = alice;
        uint256[] memory m = new uint256[](1);
        m[0] = 10 ether;
        _genesis(a, m);

        uint64 paidThrough = pool.duesPaidUntil(alice);
        vm.prank(alice);
        pool.payDues(3);

        assertEq(pool.duesPaidUntil(alice), paidThrough + 300);
        assertGt(pool.balanceOf(alice), 10 ether);
    }

    function test_proposeAndVoteRevertWhenDuesLate() public {
        vm.roll(1);
        address[] memory ab = new address[](2);
        ab[0] = alice;
        ab[1] = bob;
        uint256[] memory mb = new uint256[](2);
        mb[0] = 10 ether;
        mb[1] = 10 ether;
        _genesis(ab, mb);

        vm.warp(block.timestamp + 200);

        vm.prank(alice);
        vm.expectRevert(RttmPool.RttmPool__DuesNotCurrent.selector);
        pool.proposeExternalCall(address(token), "");

        vm.warp(1);
        vm.roll(3);
        uint256 pid = _proposeFromBob();

        vm.warp(block.timestamp + 200);
        vm.prank(alice);
        vm.expectRevert(RttmPool.RttmPool__DuesNotCurrent.selector);
        pool.castVote(pid, 1);
    }

    function test_kick_afterGrace_expelsAndKeepsTokensInPool() public {
        address[] memory a = new address[](1);
        a[0] = alice;
        uint256[] memory m = new uint256[](1);
        m[0] = 10 ether;
        _genesis(a, m);

        uint256 poolBal = token.balanceOf(address(pool));
        vm.warp(block.timestamp + 200);

        pool.kick(alice);

        assertFalse(pool.isMember(alice));
        assertEq(pool.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(pool)), poolBal);
    }

    function test_kick_revertsInsideGrace() public {
        address[] memory a = new address[](1);
        a[0] = alice;
        uint256[] memory m = new uint256[](1);
        m[0] = 10 ether;
        _genesis(a, m);

        vm.warp(block.timestamp + 105);

        vm.expectRevert(RttmPool.RttmPool__NotKickable.selector);
        pool.kick(alice);
    }

    function test_proposalExecutesWhenMajorityOfSupplyVotesYes() public {
        vm.roll(1);
        address[] memory ab = new address[](2);
        ab[0] = alice;
        ab[1] = bob;
        uint256[] memory mb = new uint256[](2);
        mb[0] = 10 ether;
        mb[1] = 10 ether;
        _genesis(ab, mb);

        address sink = address(uint160(0x5151));
        bytes memory data = abi.encodeCall(IERC20.transfer, (sink, 4 ether));

        vm.roll(3);
        vm.prank(alice);
        uint256 pid = pool.proposeExternalCall(address(token), data);

        vm.prank(alice);
        pool.castVote(pid, 1);
        vm.prank(bob);
        pool.castVote(pid, 1);

        uint256 snap = pool.getProposal(pid).snapshot;
        assertEq(snap, 2);
        assertEq(pool.getPastTotalSupply(snap), 20 ether);

        vm.roll(block.number + pool.votingPeriodBlocks() + 1);

        pool.execute(pid);
        assertEq(token.balanceOf(sink), 4 ether);
        assertEq(token.balanceOf(address(pool)), 16 ether);
    }

    function test_proposalFailsWithoutMajorityOfEntireSupply() public {
        vm.roll(1);
        address[] memory ab = new address[](2);
        ab[0] = alice;
        ab[1] = bob;
        uint256[] memory mb = new uint256[](2);
        mb[0] = 10 ether;
        mb[1] = 10 ether;
        _genesis(ab, mb);

        bytes memory data = abi.encodeCall(IERC20.transfer, (bob, 1 ether));

        vm.roll(3);
        vm.prank(alice);
        uint256 pid = pool.proposeExternalCall(address(token), data);

        vm.prank(alice);
        pool.castVote(pid, 1);

        vm.roll(block.number + pool.votingPeriodBlocks() + 1);

        vm.expectRevert(RttmPool.RttmPool__ProposalNotPassed.selector);
        pool.execute(pid);
    }

    function test_governanceCanReviseDuesParamsViaSelfCall() public {
        vm.roll(1);
        address[] memory ab = new address[](2);
        ab[0] = alice;
        ab[1] = bob;
        uint256[] memory mb = new uint256[](2);
        mb[0] = 10 ether;
        mb[1] = 10 ether;
        _genesis(ab, mb);

        bytes memory data = abi.encodeCall(RttmPool.setDuesParams, (2 wei, uint256(200), uint256(20)));

        vm.roll(3);
        vm.prank(alice);
        uint256 pid = pool.proposeExternalCall(address(pool), data);

        vm.prank(alice);
        pool.castVote(pid, 1);
        vm.prank(bob);
        pool.castVote(pid, 1);

        vm.roll(block.number + pool.votingPeriodBlocks() + 1);
        pool.execute(pid);

        assertEq(pool.duesAmount(), 2 wei);
        assertEq(pool.duesPeriodSeconds(), 200);
        assertEq(pool.duesGraceSeconds(), 20);
    }

    function test_setTreasuryToken_executesWithDeployedToken() public {
        MockERC20 token2 = new MockERC20();

        vm.roll(1);
        address[] memory ab = new address[](2);
        ab[0] = alice;
        ab[1] = bob;
        uint256[] memory mb = new uint256[](2);
        mb[0] = 5 ether;
        mb[1] = 5 ether;
        _genesis(ab, mb);

        bytes memory data = abi.encodeCall(RttmPool.setTreasuryToken, (IERC20(address(token2))));

        vm.roll(3);
        vm.prank(alice);
        uint256 pid = pool.proposeExternalCall(address(pool), data);

        vm.prank(alice);
        pool.castVote(pid, 1);
        vm.prank(bob);
        pool.castVote(pid, 1);

        vm.roll(block.number + pool.votingPeriodBlocks() + 1);

        _approve(alice, type(uint256).max);
        uint256 aliceShares = pool.balanceOf(alice);
        vm.prank(alice);
        pool.withdraw(aliceShares);
        _approve(bob, type(uint256).max);
        uint256 bobShares = pool.balanceOf(bob);
        vm.prank(bob);
        pool.withdraw(bobShares);

        pool.execute(pid);
        assertEq(address(pool.treasuryToken()), address(token2));
    }

    function test_setDuesParams_directCallReverts() public {
        vm.expectRevert(RttmPool.RttmPool__OnlySelf.selector);
        pool.setDuesParams(1, 1, 0);
    }

    function test_setTreasuryToken_directCallReverts() public {
        vm.expectRevert(RttmPool.RttmPool__OnlySelf.selector);
        pool.setTreasuryToken(IERC20(address(token)));
    }

    function test_fullWithdrawLeavesPoolAndClearsMembership() public {
        address[] memory a = new address[](1);
        a[0] = alice;
        uint256[] memory m = new uint256[](1);
        m[0] = 10 ether;
        _genesis(a, m);

        uint256 before = token.balanceOf(alice);
        vm.prank(alice);
        pool.withdraw(10 ether);

        assertEq(token.balanceOf(alice), before + 10 ether);
        assertEq(pool.balanceOf(alice), 0);
        assertFalse(pool.isMember(alice));
    }

    function test_partialWithdrawBelowMinimumForfeitsRemainder() public {
        address[] memory a = new address[](1);
        a[0] = alice;
        uint256[] memory m = new uint256[](1);
        m[0] = 10 ether;
        _genesis(a, m);

        uint256 shares = pool.balanceOf(alice);
        uint256 withdrawShares = (shares * 8) / 10;

        uint256 before = token.balanceOf(alice);
        vm.prank(alice);
        pool.withdraw(withdrawShares);

        assertEq(pool.balanceOf(alice), 0);
        assertFalse(pool.isMember(alice));

        uint256 payout = token.balanceOf(alice) - before;
        assertApproxEqAbs(token.balanceOf(address(pool)) + payout, 10 ether, 2);
    }

    function test_transferToNonMemberReverts() public {
        address[] memory a = new address[](1);
        a[0] = alice;
        uint256[] memory m = new uint256[](1);
        m[0] = 10 ether;
        _genesis(a, m);

        address stranger = address(0xCAFE);
        vm.prank(alice);
        vm.expectRevert(RttmPool.RttmPool__TransferNotMember.selector);
        pool.transfer(stranger, 1 ether);
    }

    function test_memberCanTransferToMember() public {
        vm.roll(1);
        address[] memory ab = new address[](2);
        ab[0] = alice;
        ab[1] = bob;
        uint256[] memory mb = new uint256[](2);
        mb[0] = 10 ether;
        mb[1] = 5 ether;
        _genesis(ab, mb);

        vm.prank(alice);
        pool.transfer(bob, 2 ether);

        assertEq(pool.balanceOf(bob), 7 ether);
    }

    function test_receive_reverts() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(RttmPool.RttmPool__NativeTokenNotAccepted.selector);
        payable(address(pool)).transfer(1 wei);
    }

    function test_example_encodeCall_setDuesParams() public pure {
        bytes memory data = abi.encodeCall(RttmPool.setDuesParams, (10 * 1e6, uint256(7 days), uint256(1 days)));
        assertGt(data.length, 4);
    }

    function test_direct_join_reverts() public {
        _approve(alice, type(uint256).max);
        vm.prank(alice);
        vm.expectRevert(RttmPool.RttmPool__UseApplyJoin.selector);
        pool.join(10 ether);
    }

    function _proposeFromBob() internal returns (uint256 pid) {
        vm.roll(block.number + 1);
        vm.prank(bob);
        pid = pool.proposeExternalCall(address(token), "");
    }
}
