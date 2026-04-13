// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title RttmPool
/// @notice Member-governed ERC20 treasury with genesis bootstrap, gated join applications, configurable BPS
///         vote thresholds, and governable pool parameters.
contract RttmPool is ERC20, ERC20Permit, ERC20Votes, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum JoinAppStatus {
        None,
        Pending
    }

    enum ProposalKind {
        ExternalCall,
        ApproveJoin,
        RejectJoin
    }

    struct PoolParams {
        uint256 memberMinimum;
        uint256 joinMinimum;
        uint256 votingPeriodBlocks;
        uint256 proposalPassBps;
        uint256 joinApprovalBps;
    }

    struct Proposal {
        ProposalKind kind;
        address proposer;
        address target;
        bytes data;
        address applicant;
        uint48 snapshot;
        uint256 votingDeadline;
        uint256 yesVotes;
        uint256 thresholdBps;
        bool executed;
    }

    error RttmPool__NotMember();
    error RttmPool__AlreadyMember();
    error RttmPool__JoinBelowMinimum(uint256 sent, uint256 minimum);
    error RttmPool__TransferNotMember();
    error RttmPool__ZeroShares();
    error RttmPool__ProposalNotFound();
    error RttmPool__VotingClosed();
    error RttmPool__AlreadyVoted();
    error RttmPool__ProposalNotPassed();
    error RttmPool__AlreadyExecuted();
    error RttmPool__DuesNotCurrent();
    error RttmPool__NotKickable();
    error RttmPool__DuesPaymentMismatch(uint256 sent, uint256 expected);
    error RttmPool__InvalidDuesParams();
    error RttmPool__OnlySelf();
    error RttmPool__NonEmptyPool();
    error RttmPool__ZeroAddress();
    error RttmPool__NativeTokenNotAccepted();
    error RttmPool__UseApplyJoin();
    error RttmPool__GenesisAlreadyCompleted();
    error RttmPool__NotGenesisAuthority();
    error RttmPool__InvalidGenesis();
    error RttmPool__NoJoinApplication();
    error RttmPool__InvalidBps();
    error RttmPool__InvalidPoolParams();

    event Joined(address indexed member, uint256 assets, uint256 sharesMinted);
    event JoinApplied(address indexed applicant, uint256 amount, uint256 totalPending);
    event JoinApplicationWithdrawn(address indexed applicant, uint256 refunded);
    event JoinApproved(address indexed applicant, uint256 assets, uint256 sharesMinted);
    event JoinRejected(address indexed applicant, uint256 refunded);
    event Contributed(address indexed member, uint256 assets, uint256 sharesMinted);
    event Withdrawn(address indexed member, uint256 sharesBurned, uint256 assetsSent);
    event Expelled(address indexed member, uint256 sharesForfeited);
    event DuesPaid(address indexed member, uint256 periods, uint256 amountPaid, uint64 newPaidUntil);
    event DuesParamsUpdated(uint256 duesAmount, uint256 duesPeriodSeconds, uint256 duesGraceSeconds);
    event TreasuryTokenUpdated(address indexed newToken);
    event PoolParamsUpdated(
        uint256 memberMinimum,
        uint256 joinMinimum,
        uint256 votingPeriodBlocks,
        uint256 proposalPassBps,
        uint256 joinApprovalBps
    );
    event MemberKicked(address indexed member, address indexed caller);
    event GenesisCompleted(uint256 memberCount);
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalKind kind,
        address indexed ref,
        uint48 snapshot,
        uint256 votingDeadline,
        uint256 thresholdBps
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, uint8 support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);

    address public immutable genesisAuthority;

    uint256 public memberMinimum;
    uint256 public joinMinimum;
    uint256 public votingPeriodBlocks;
    /// @notice Yes-weight must satisfy `yesVotes * 10_000 > supply * proposalPassBps` (strict fraction).
    uint256 public proposalPassBps;
    /// @notice Same inequality for approve/reject join proposals using `joinApprovalBps`.
    uint256 public joinApprovalBps;

    IERC20 public treasuryToken;

    uint256 public duesAmount;
    uint256 public duesPeriodSeconds;
    uint256 public duesGraceSeconds;

    mapping(address => uint64) public duesPaidUntil;
    mapping(address => bool) public isMember;
    mapping(address => JoinAppStatus) public joinApplicationStatus;
    mapping(address => uint256) public pendingJoinDeposit;

    uint8 private _genesisCompleted;

    Proposal[] private _proposals;
    mapping(uint256 proposalId => mapping(address => bool)) private _hasVoted;

    constructor(
        string memory name_,
        string memory symbol_,
        IERC20 treasuryToken_,
        address genesisAuthority_,
        uint256 memberMinimum_,
        uint256 joinMinimum_,
        uint256 votingPeriodBlocks_,
        uint256 proposalPassBps_,
        uint256 joinApprovalBps_,
        uint256 duesAmount_,
        uint256 duesPeriodSeconds_,
        uint256 duesGraceSeconds_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (address(treasuryToken_) == address(0)) revert RttmPool__ZeroAddress();
        if (genesisAuthority_ == address(0)) revert RttmPool__ZeroAddress();
        genesisAuthority = genesisAuthority_;
        treasuryToken = treasuryToken_;
        _setPoolParams(
            memberMinimum_,
            joinMinimum_,
            votingPeriodBlocks_,
            proposalPassBps_,
            joinApprovalBps_
        );
        _validateAndSetDuesParams(duesAmount_, duesPeriodSeconds_, duesGraceSeconds_);
    }

    /// @notice One-time bootstrap: pulls tokens from each address (must have approved pool) and mints shares.
    function completeGenesis(address[] calldata members, uint256[] calldata amounts) external nonReentrant {
        if (_genesisCompleted != 0) revert RttmPool__GenesisAlreadyCompleted();
        if (msg.sender != genesisAuthority) revert RttmPool__NotGenesisAuthority();
        uint256 n = members.length;
        if (n == 0 || n != amounts.length) revert RttmPool__InvalidGenesis();

        for (uint256 i; i < n; ++i) {
            address a = members[i];
            uint256 amt = amounts[i];
            if (a == address(0)) revert RttmPool__InvalidGenesis();
            if (isMember[a]) revert RttmPool__AlreadyMember();
            if (joinApplicationStatus[a] != JoinAppStatus.None) revert RttmPool__InvalidGenesis();
            if (amt < joinMinimum) revert RttmPool__JoinBelowMinimum(amt, joinMinimum);

            treasuryToken.safeTransferFrom(a, address(this), amt);
            isMember[a] = true;
            if (_duesEnabled()) {
                duesPaidUntil[a] = SafeCast.toUint64(block.timestamp + duesPeriodSeconds);
            }
            _mintSharesForAccount(a, amt);
            emit Joined(a, amt, balanceOf(a));
        }
        _genesisCompleted = 1;
        emit GenesisCompleted(n);
    }

    /// @notice Non-members deposit a pending amount; membership requires `proposeApproveJoin` + vote.
    function applyJoin(uint256 amount) external nonReentrant {
        if (_genesisCompleted == 0) revert RttmPool__InvalidGenesis();
        if (isMember[msg.sender]) revert RttmPool__AlreadyMember();
        if (amount == 0) revert RttmPool__JoinBelowMinimum(0, joinMinimum);

        treasuryToken.safeTransferFrom(msg.sender, address(this), amount);
        pendingJoinDeposit[msg.sender] += amount;
        joinApplicationStatus[msg.sender] = JoinAppStatus.Pending;
        emit JoinApplied(msg.sender, amount, pendingJoinDeposit[msg.sender]);
    }

    function withdrawJoinApplication() external nonReentrant {
        if (joinApplicationStatus[msg.sender] != JoinAppStatus.Pending) revert RttmPool__NoJoinApplication();
        uint256 p = pendingJoinDeposit[msg.sender];
        pendingJoinDeposit[msg.sender] = 0;
        joinApplicationStatus[msg.sender] = JoinAppStatus.None;
        treasuryToken.safeTransfer(msg.sender, p);
        emit JoinApplicationWithdrawn(msg.sender, p);
    }

    /// @dev Deprecated entrypoint; use `applyJoin`.
    function join(uint256) external pure {
        revert RttmPool__UseApplyJoin();
    }

    function contribute(uint256 amount) external nonReentrant {
        if (!isMember[msg.sender]) revert RttmPool__NotMember();
        if (amount == 0) return;
        treasuryToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 shares = _mintSharesForDeposit(amount);
        emit Contributed(msg.sender, amount, shares);
    }

    function payDues(uint256 periods) external nonReentrant {
        if (!isMember[msg.sender]) revert RttmPool__NotMember();
        if (!_duesEnabled()) revert RttmPool__InvalidDuesParams();
        if (periods == 0) revert RttmPool__InvalidDuesParams();

        uint256 expected = periods * duesAmount;
        treasuryToken.safeTransferFrom(msg.sender, address(this), expected);

        uint256 base = duesPaidUntil[msg.sender];
        if (base < block.timestamp) {
            base = block.timestamp;
        }
        uint256 newUntil = base + periods * duesPeriodSeconds;
        duesPaidUntil[msg.sender] = SafeCast.toUint64(newUntil);

        _mintSharesForDeposit(expected);
        emit DuesPaid(msg.sender, periods, expected, duesPaidUntil[msg.sender]);
    }

    function kick(address member) external {
        if (!isMember[member]) revert RttmPool__NotMember();
        if (!_isKickableDelinquent(member)) revert RttmPool__NotKickable();
        uint256 bal = balanceOf(member);
        _burnAllSharesAndClearMember(member);
        if (bal > 0) {
            emit Expelled(member, bal);
        }
        emit MemberKicked(member, msg.sender);
    }

    receive() external payable {
        revert RttmPool__NativeTokenNotAccepted();
    }

    fallback() external payable {
        revert RttmPool__NativeTokenNotAccepted();
    }

    function setTreasuryToken(IERC20 newToken) external {
        if (msg.sender != address(this)) revert RttmPool__OnlySelf();
        if (address(newToken) == address(0)) revert RttmPool__ZeroAddress();
        if (totalSupply() != 0) revert RttmPool__NonEmptyPool();
        if (treasuryToken.balanceOf(address(this)) != 0) revert RttmPool__NonEmptyPool();
        treasuryToken = newToken;
        emit TreasuryTokenUpdated(address(newToken));
    }

    function setDuesParams(uint256 newDuesAmount, uint256 newDuesPeriodSeconds, uint256 newDuesGraceSeconds) external {
        if (msg.sender != address(this)) revert RttmPool__OnlySelf();
        _validateAndSetDuesParams(newDuesAmount, newDuesPeriodSeconds, newDuesGraceSeconds);
        emit DuesParamsUpdated(newDuesAmount, newDuesPeriodSeconds, newDuesGraceSeconds);
    }

    /// @notice Updates minimums, voting window, and vote thresholds (self-call via governance only).
    function setPoolParams(PoolParams calldata p) external {
        if (msg.sender != address(this)) revert RttmPool__OnlySelf();
        _setPoolParams(
            p.memberMinimum, p.joinMinimum, p.votingPeriodBlocks, p.proposalPassBps, p.joinApprovalBps
        );
        emit PoolParamsUpdated(
            p.memberMinimum, p.joinMinimum, p.votingPeriodBlocks, p.proposalPassBps, p.joinApprovalBps
        );
    }

    function proposalCount() external view returns (uint256) {
        return _proposals.length;
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        if (proposalId >= _proposals.length) revert RttmPool__ProposalNotFound();
        return _proposals[proposalId];
    }

    function genesisCompleted() external view returns (bool) {
        return _genesisCompleted != 0;
    }

    function assetsOf(address account) public view returns (uint256) {
        return _convertToAssets(balanceOf(account));
    }

    function isDuesCurrent(address member) public view returns (bool) {
        if (!_duesEnabled()) return true;
        return block.timestamp <= duesPaidUntil[member];
    }

    function proposeExternalCall(address target, bytes calldata data) external returns (uint256 proposalId) {
        proposalId = _createProposal(ProposalKind.ExternalCall, target, data, address(0));
    }

    function proposeApproveJoin(address applicant) external returns (uint256 proposalId) {
        if (joinApplicationStatus[applicant] != JoinAppStatus.Pending) revert RttmPool__NoJoinApplication();
        proposalId = _createProposal(ProposalKind.ApproveJoin, address(0), new bytes(0), applicant);
    }

    function proposeRejectJoin(address applicant) external returns (uint256 proposalId) {
        if (joinApplicationStatus[applicant] != JoinAppStatus.Pending) revert RttmPool__NoJoinApplication();
        proposalId = _createProposal(ProposalKind.RejectJoin, address(0), new bytes(0), applicant);
    }

    function castVote(uint256 proposalId, uint8 support) external {
        if (!isDuesCurrent(msg.sender)) revert RttmPool__DuesNotCurrent();
        if (proposalId >= _proposals.length) revert RttmPool__ProposalNotFound();
        Proposal storage p = _proposals[proposalId];
        if (block.number > p.votingDeadline) revert RttmPool__VotingClosed();
        if (_hasVoted[proposalId][msg.sender]) revert RttmPool__AlreadyVoted();

        _hasVoted[proposalId][msg.sender] = true;

        uint256 weight = getPastVotes(msg.sender, p.snapshot);
        if (support == 1) {
            p.yesVotes += weight;
        }
        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    function execute(uint256 proposalId) external nonReentrant {
        if (proposalId >= _proposals.length) revert RttmPool__ProposalNotFound();
        Proposal storage p = _proposals[proposalId];
        _validateAndMarkExecuted(proposalId, p);
        _dispatchProposal(p);
    }

    function _validateAndMarkExecuted(uint256 proposalId, Proposal storage p) internal {
        if (p.executed) revert RttmPool__AlreadyExecuted();
        if (block.number <= p.votingDeadline) revert RttmPool__VotingClosed();
        uint256 supplyAt = getPastTotalSupply(p.snapshot);
        if (supplyAt == 0 || !_passesBps(p.yesVotes, supplyAt, p.thresholdBps)) {
            revert RttmPool__ProposalNotPassed();
        }
        p.executed = true;
        emit ProposalExecuted(proposalId);
    }

    function _dispatchProposal(Proposal storage p) internal {
        ProposalKind k = p.kind;
        if (k == ProposalKind.ExternalCall) {
            Address.functionCall(p.target, p.data);
        } else if (k == ProposalKind.ApproveJoin) {
            _approveJoin(p.applicant);
        } else {
            _rejectJoin(p.applicant);
        }
    }

    function withdraw(uint256 shareAmount) external nonReentrant {
        if (!isMember[msg.sender]) revert RttmPool__NotMember();
        if (shareAmount == 0) revert RttmPool__ZeroShares();

        uint256 s0 = balanceOf(msg.sender);
        if (shareAmount > s0) revert RttmPool__ZeroShares();

        uint256 balanceBefore = treasuryToken.balanceOf(address(this));
        uint256 supplyBefore = totalSupply();

        uint256 payout = Math.mulDiv(shareAmount, balanceBefore, supplyBefore);
        uint256 s1 = s0 - shareAmount;
        uint256 balanceAfterPayout = balanceBefore - payout;
        uint256 supplyAfterBurn = supplyBefore - shareAmount;
        uint256 remainingValue =
            s1 == 0 || supplyAfterBurn == 0 ? 0 : Math.mulDiv(s1, balanceAfterPayout, supplyAfterBurn);

        _burn(msg.sender, shareAmount);
        treasuryToken.safeTransfer(msg.sender, payout);
        emit Withdrawn(msg.sender, shareAmount, payout);

        if (s1 > 0 && remainingValue < memberMinimum) {
            uint256 forfeitShares = balanceOf(msg.sender);
            if (forfeitShares > 0) {
                _burnAllSharesAndClearMember(msg.sender);
                emit Expelled(msg.sender, forfeitShares);
            }
        }

        if (balanceOf(msg.sender) == 0) {
            isMember[msg.sender] = false;
        }
    }

    function _createProposal(ProposalKind kind, address target, bytes memory data, address applicant)
        internal
        returns (uint256 proposalId)
    {
        if (!isMember[msg.sender]) revert RttmPool__NotMember();
        if (!isDuesCurrent(msg.sender)) revert RttmPool__DuesNotCurrent();
        require(block.number >= 2, "rttm: snapshot");
        uint48 snapshot = uint48(block.number - 1);
        uint256 deadline = block.number + votingPeriodBlocks;

        uint256 thr = kind == ProposalKind.ExternalCall ? proposalPassBps : joinApprovalBps;

        proposalId = _proposals.length;
        _proposals.push(
            Proposal({
                kind: kind,
                proposer: msg.sender,
                target: target,
                data: data,
                applicant: applicant,
                snapshot: snapshot,
                votingDeadline: deadline,
                yesVotes: 0,
                thresholdBps: thr,
                executed: false
            })
        );

        address ref = kind == ProposalKind.ExternalCall ? target : applicant;
        emit ProposalCreated(proposalId, msg.sender, kind, ref, snapshot, deadline, thr);
    }

    function _passesBps(uint256 yesVotes, uint256 supply, uint256 bps) internal pure returns (bool) {
        return yesVotes != 0 && yesVotes * 10_000 > supply * bps;
    }

    function _approveJoin(address applicant) internal {
        if (joinApplicationStatus[applicant] != JoinAppStatus.Pending) revert RttmPool__NoJoinApplication();
        uint256 dep = pendingJoinDeposit[applicant];
        if (dep < joinMinimum) revert RttmPool__JoinBelowMinimum(dep, joinMinimum);

        pendingJoinDeposit[applicant] = 0;
        joinApplicationStatus[applicant] = JoinAppStatus.None;

        isMember[applicant] = true;
        if (_duesEnabled()) {
            duesPaidUntil[applicant] = SafeCast.toUint64(block.timestamp + duesPeriodSeconds);
        }
        uint256 sh = _mintSharesForAccount(applicant, dep);
        emit JoinApproved(applicant, dep, sh);
        emit Joined(applicant, dep, sh);
    }

    function _rejectJoin(address applicant) internal {
        if (joinApplicationStatus[applicant] != JoinAppStatus.Pending) revert RttmPool__NoJoinApplication();
        uint256 dep = pendingJoinDeposit[applicant];
        pendingJoinDeposit[applicant] = 0;
        joinApplicationStatus[applicant] = JoinAppStatus.None;
        treasuryToken.safeTransfer(applicant, dep);
        emit JoinRejected(applicant, dep);
    }

    function _setPoolParams(
        uint256 memberMinimum_,
        uint256 joinMinimum_,
        uint256 votingPeriodBlocks_,
        uint256 proposalPassBps_,
        uint256 joinApprovalBps_
    ) internal {
        if (joinMinimum_ < memberMinimum_) revert RttmPool__InvalidPoolParams();
        if (votingPeriodBlocks_ == 0) revert RttmPool__InvalidPoolParams();
        if (proposalPassBps_ == 0 || proposalPassBps_ >= 10_000) revert RttmPool__InvalidBps();
        if (joinApprovalBps_ == 0 || joinApprovalBps_ >= 10_000) revert RttmPool__InvalidBps();
        memberMinimum = memberMinimum_;
        joinMinimum = joinMinimum_;
        votingPeriodBlocks = votingPeriodBlocks_;
        proposalPassBps = proposalPassBps_;
        joinApprovalBps = joinApprovalBps_;
    }

    function _duesEnabled() internal view returns (bool) {
        return duesAmount > 0 && duesPeriodSeconds > 0;
    }

    function _isKickableDelinquent(address member) internal view returns (bool) {
        if (!_duesEnabled()) return false;
        return block.timestamp > uint256(duesPaidUntil[member]) + duesGraceSeconds;
    }

    function _validateAndSetDuesParams(uint256 amount_, uint256 periodSeconds_, uint256 graceSeconds_) internal {
        bool on = amount_ > 0 && periodSeconds_ > 0;
        bool off = amount_ == 0 && periodSeconds_ == 0;
        if (!on && !off) revert RttmPool__InvalidDuesParams();
        duesAmount = amount_;
        duesPeriodSeconds = periodSeconds_;
        duesGraceSeconds = graceSeconds_;
    }

    function _burnAllSharesAndClearMember(address member) internal {
        uint256 bal = balanceOf(member);
        if (bal > 0) {
            _burn(member, bal);
        }
        isMember[member] = false;
    }

    function _mintSharesForDeposit(uint256 assets) internal returns (uint256 shares) {
        return _mintSharesForAccount(msg.sender, assets);
    }

    function _mintSharesForAccount(address to, uint256 assets) internal returns (uint256 shares) {
        uint256 supply = totalSupply();
        uint256 poolBalance = treasuryToken.balanceOf(address(this));
        if (supply == 0) {
            shares = assets;
        } else {
            shares = Math.mulDiv(assets, supply, poolBalance - assets);
        }
        _mint(to, shares);
        return shares;
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        return Math.mulDiv(shares, treasuryToken.balanceOf(address(this)), supply);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        if (from != address(0) && to != address(0) && !isMember[to]) {
            revert RttmPool__TransferNotMember();
        }
        super._update(from, to, value);
        if (from == address(0) && to != address(0) && delegates(to) == address(0)) {
            _delegate(to, to);
        }
    }

    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
