# RttM pool DAO — documentation

This repository implements a **member-governed ERC20 treasury** (`RttmPool`). Members hold **vote-weighted shares** (OpenZeppelin `ERC20Votes`). **Governance proposals** snapshot voting power at `block.number - 1` and pass only if yes-weight beats a **configurable BPS fraction** of **total supply at that snapshot** (strict inequality; see below).

---

## Lifecycle: factory, genesis, and joins

### Deploy (`RttmPoolFactory`)

1. **`createPool(DeployConfig)`** deploys a new `RttmPool` with constructor parameters taken from config (see [Parameters](#parameters-full-accounting)).
2. The factory records **`poolCreator[pool] = msg.sender`**.
3. **`completeGenesisFor(pool, members[], amounts[])`** may **only** be called by that creator. It forwards to **`pool.completeGenesis`**, which pulls treasury tokens (each member must **`approve` the pool**) and mints initial shares.

This two-step flow exists so members can approve the newly deployed pool address **before** genesis pulls run.

### After genesis

- **`applyJoin(amount)`** (non-members): ERC20 pull into **`pendingJoinDeposit`**; status **`Pending`**.
- **`withdrawJoinApplication()`**: refunds pending deposit and clears the application.
- **`proposeApproveJoin(applicant)`** / **`proposeRejectJoin(applicant)`**: members create proposals; on execution, the pool either **mints shares** (approve) or **refunds** (reject). Join proposals use **`joinApprovalBps`** snapshotted at proposal creation.
- The legacy **`join(uint256)`** entrypoint **always reverts** (`RttmPool__UseApplyJoin`).

---

## Treasury, shares, and accounting

- **Single `treasuryToken` (ERC20)** at a time; all amounts are **base units** (e.g. USDC **6** decimals).
- **`contribute(amount)`**: members deposit; shares minted pro-rata to pool NAV.
- **`withdraw(shareAmount)`**: burns shares, sends treasury tokens. If a **partial** withdrawal leaves a **non-zero** stake whose **token value** is **below `memberMinimum`**, the **remainder is forfeited** (shares burned, tokens stay in the pool).
- **Plain ETH** to the pool **reverts**.

---

## Dues and enforcement

- **`duesAmount`**, **`duesPeriodSeconds`**, **`duesGraceSeconds`**: if `duesAmount > 0` and `duesPeriodSeconds > 0`, dues are **on**; setting **both** to **zero** disables dues.
- **`payDues(periods)`**: pulls `periods * duesAmount`, extends **`duesPaidUntil`**, mints shares like a contribution.
- **Proposal and vote**: require **`isDuesCurrent`** (paid through `block.timestamp`, or dues disabled).
- **`kick(member)`** (permissionless): if dues are enabled and `block.timestamp > duesPaidUntil[member] + duesGraceSeconds`, burns shares and removes membership.

---

## Governance and voting thresholds

### Proposal kinds

| Kind | Created by | `execute` behavior |
|------|------------|-------------------|
| **ExternalCall** | `proposeExternalCall(target, data)` | `Address.functionCall(target, data)` (no native `value`) |
| **ApproveJoin** | `proposeApproveJoin(applicant)` | Internal `_approveJoin` |
| **RejectJoin** | `proposeRejectJoin(applicant)` | Internal `_rejectJoin` |

### BPS pass rule (all kinds)

At execution time, let `supply = getPastTotalSupply(snapshot)` and `yesVotes` be the accumulated yes weight. The proposal passes only if:

```text
yesVotes * 10_000 > supply * thresholdBps
```

and `yesVotes != 0`.

- **`thresholdBps`** is stored **per proposal** when it is created:
  - **ExternalCall** → current **`proposalPassBps`**.
  - **ApproveJoin** / **RejectJoin** → current **`joinApprovalBps`**.

So later governance can change BPS for **new** proposals; **existing** proposals keep their snapshotted threshold.

Valid BPS values: **`1 … 9999`** (strictly between 0% and 100%). **`5000`** means strictly **more than 50%** of supply at snapshot.

### Voting

- **`castVote(proposalId, support)`**: only **`support == 1`** adds weight; **`0`** records participation without adding yes weight.
- **`execute(proposalId)`**: after **`block.number > votingDeadline`**, checks the BPS rule and dispatches.

---

## Parameters: full accounting

### Immutable for the deployment (constructor / factory config)

| Parameter | Role |
|-----------|------|
| **`name_`**, **`symbol_`** | ERC20 name/symbol for pool shares |
| **`treasuryToken`** (initial) | First ERC20 treasury asset |
| **`genesisAuthority`** | Sole caller allowed for **`completeGenesis`** (factory creator uses **`completeGenesisFor`**) |

### Storage parameters — initial values from constructor; **revisable by governance** via self-call

These live in storage and are updated **only** when **`msg.sender == address(this)`** (i.e. after a **passed** `ExternalCall` proposal into the pool):

| Parameter | Meaning | Updater on-chain |
|-----------|---------|------------------|
| **`memberMinimum`** | Minimum economic stake (treasury base units) after partial withdraw | **`setPoolParams`** |
| **`joinMinimum`** | Minimum deposit for genesis seat and for **approved** join; must be ≥ `memberMinimum` | **`setPoolParams`** |
| **`votingPeriodBlocks`** | Blocks from proposal block until voting closes | **`setPoolParams`** |
| **`proposalPassBps`** | BPS threshold for **new** external-call proposals | **`setPoolParams`** |
| **`joinApprovalBps`** | BPS threshold for **new** approve/reject-join proposals | **`setPoolParams`** |
| **`duesAmount`**, **`duesPeriodSeconds`**, **`duesGraceSeconds`** | Dues schedule and kick grace | **`setDuesParams`** |
| **`treasuryToken`** | Pointer to ERC20 treasury | **`setTreasuryToken`** |

**`setTreasuryToken`** guards: **`totalSupply() == 0`** and **`treasuryToken.balanceOf(pool) == 0`**.

### Per-member / per-proposal (not “DAO config” in the governance doc sense)

| Item | Notes |
|------|------|
| **`isMember`**, **`balanceOf`**, **`delegates`**, checkpoints | Standard ERC20 + `ERC20Votes` |
| **`duesPaidUntil`** | Per-member dues horizon |
| **`joinApplicationStatus`**, **`pendingJoinDeposit`** | Join pipeline |
| **`_proposals[]`**, **`_hasVoted`** | Proposal state |

### How to change each revisable parameter

1. Build calldata for **`setPoolParams`**, **`setDuesParams`**, or **`setTreasuryToken`** (the web dApp includes encoders).
2. **`proposeExternalCall(address(pool), data)`** — voting uses **`proposalPassBps`** snapshotted at create time.
3. After the deadline, **`execute`** runs the call on the pool; the pool updates storage and emits **`PoolParamsUpdated`**, **`DuesParamsUpdated`**, or **`TreasuryTokenUpdated`**.

**Changing BPS or minimums does not require a new deployment.** A new deployment is only needed for a different **`genesisAuthority`**, different immutable bytecode, or a fresh pool instance.

---

## Default configuration

See **`config/pool.defaults.json`**: USDC-6-oriented defaults (e.g. **10 USDC** minimums and per-period dues), **`proposalPassBps`** and **`joinApprovalBps`** at **`5000`** (strictly greater than 50%), and documented BPS semantics.

---

## Front end and indexing

- **`apps/web`**: Vite + React + viem; network toggle (Sepolia / mainnet) and **`VITE_POOL_*`** / **`VITE_RPC_*`** / optional **`VITE_FROM_BLOCK_*`** (narrows log fetches).
- **State page**: client-side “indexer” via **`getContractEvents`** plus live **`readContract`** for parameters, recent proposals, and members inferred from **`Joined`** events (RPC limits apply; not a substitute for a dedicated indexer service at scale).

---

## Tests and scripts

- Contracts: `src/RttmPool.sol`, `src/RttmPoolFactory.sol`
- Tests: `test/RttmPool*.sol`, `test/RttmPoolFactory.t.sol`
- Deploy: `script/DeployRttmPool.s.sol`
