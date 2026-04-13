import { useEffect, useState } from "react";
import { encodeFunctionData, isAddress, isHex, type PublicClient, type WalletClient } from "viem";
import { erc20Abi, rttmPoolAbi } from "../abi";
import { usePoolDeployment } from "../hooks/usePoolAddress";
import { useWeb3 } from "../web3";

export function DaoAppPage() {
  const { pool } = usePoolDeployment();
  const { account, walletClient, publicClient } = useWeb3();
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function run(fn: () => Promise<unknown>) {
    setMsg(null);
    setBusy(true);
    try {
      await fn();
      setMsg("Done.");
    } catch (e: unknown) {
      setMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  if (!pool) {
    return <p className="err">Configure pool address for this chain.</p>;
  }

  if (!account || !walletClient) {
    return <p className="muted">Connect a wallet to submit transactions.</p>;
  }

  return (
    <div>
      <h1>dApp</h1>
      <p className="muted">
        Approve the treasury token for the pool before <code>applyJoin</code>, <code>contribute</code>, or{" "}
        <code>payDues</code>. Amounts are raw integer strings (smallest units).
      </p>
      {busy && <p>Waiting for wallet / confirmation…</p>}
      {msg && <p className="muted">{msg}</p>}

      <div className="card">
        <h2>Treasury token</h2>
        <TreasuryApproveSection pool={pool} run={run} walletClient={walletClient} publicClient={publicClient} />
      </div>

      <div className="card">
        <h2>Genesis (authority only)</h2>
        <p className="muted">
          One-time bootstrap. Each line: <code>0xMember,amountBaseUnits</code>. Same count for both fields.
        </p>
        <GenesisForm pool={pool} run={run} walletClient={walletClient} publicClient={publicClient} />
      </div>

      <div className="card">
        <h2>Membership</h2>
        <ApplyJoinForm pool={pool} run={run} walletClient={walletClient} publicClient={publicClient} />
        <button
          type="button"
          onClick={() =>
            run(async () => {
              const hash = await walletClient.writeContract({
                chain: walletClient.chain,
                account: walletClient.account!,
                address: pool,
                abi: rttmPoolAbi,
                functionName: "withdrawJoinApplication",
              });
              await publicClient.waitForTransactionReceipt({ hash });
            })
          }
        >
          withdrawJoinApplication()
        </button>
      </div>

      <div className="card">
        <h2>Capital & dues</h2>
        <SimpleUintForm
          label="contribute(amount)"
          onSubmit={(v) =>
            run(async () => {
              const hash = await walletClient.writeContract({
                chain: walletClient.chain,
                account: walletClient.account!,
                address: pool,
                abi: rttmPoolAbi,
                functionName: "contribute",
                args: [v],
              });
              await publicClient.waitForTransactionReceipt({ hash });
            })
          }
        />
        <SimpleUintForm
          label="payDues(periods)"
          onSubmit={(v) =>
            run(async () => {
              const hash = await walletClient.writeContract({
                chain: walletClient.chain,
                account: walletClient.account!,
                address: pool,
                abi: rttmPoolAbi,
                functionName: "payDues",
                args: [v],
              });
              await publicClient.waitForTransactionReceipt({ hash });
            })
          }
        />
        <SimpleUintForm
          label="withdraw(shareAmount)"
          onSubmit={(v) =>
            run(async () => {
              const hash = await walletClient.writeContract({
                chain: walletClient.chain,
                account: walletClient.account!,
                address: pool,
                abi: rttmPoolAbi,
                functionName: "withdraw",
                args: [v],
              });
              await publicClient.waitForTransactionReceipt({ hash });
            })
          }
        />
      </div>

      <div className="card">
        <h2>Governance</h2>
        <p className="muted">
          Pool-only functions (<code>setPoolParams</code>, <code>setDuesParams</code>, <code>setTreasuryToken</code>){" "}
          must run via a passed proposal: use the helpers below, then submit the generated calldata with{" "}
          <code>proposeExternalCall(pool, data)</code>.
        </p>
        <SetPoolParamsEncode />
        <SetDuesParamsEncode />
        <SetTreasuryTokenEncode />
        <ExternalProposalForm pool={pool} run={run} walletClient={walletClient} publicClient={publicClient} />
        <AddrForm
          label="proposeApproveJoin(applicant)"
          onSubmit={(a) =>
            run(async () => {
              const hash = await walletClient.writeContract({
                chain: walletClient.chain,
                account: walletClient.account!,
                address: pool,
                abi: rttmPoolAbi,
                functionName: "proposeApproveJoin",
                args: [a as `0x${string}`],
              });
              await publicClient.waitForTransactionReceipt({ hash });
            })
          }
        />
        <AddrForm
          label="proposeRejectJoin(applicant)"
          onSubmit={(a) =>
            run(async () => {
              const hash = await walletClient.writeContract({
                chain: walletClient.chain,
                account: walletClient.account!,
                address: pool,
                abi: rttmPoolAbi,
                functionName: "proposeRejectJoin",
                args: [a as `0x${string}`],
              });
              await publicClient.waitForTransactionReceipt({ hash });
            })
          }
        />
        <CastVoteForm pool={pool} run={run} walletClient={walletClient} publicClient={publicClient} />
        <SimpleUintForm
          label="execute(proposalId)"
          onSubmit={(id) =>
            run(async () => {
              const hash = await walletClient.writeContract({
                chain: walletClient.chain,
                account: walletClient.account!,
                address: pool,
                abi: rttmPoolAbi,
                functionName: "execute",
                args: [id],
              });
              await publicClient.waitForTransactionReceipt({ hash });
            })
          }
        />
      </div>

      <div className="card">
        <h2>Enforcement</h2>
        <AddrForm
          label="kick(member)"
          onSubmit={(a) =>
            run(async () => {
              const hash = await walletClient.writeContract({
                chain: walletClient.chain,
                account: walletClient.account!,
                address: pool,
                abi: rttmPoolAbi,
                functionName: "kick",
                args: [a as `0x${string}`],
              });
              await publicClient.waitForTransactionReceipt({ hash });
            })
          }
        />
      </div>

      <p className="muted">Connected: {account}</p>
    </div>
  );
}

function GenesisForm({
  pool,
  run,
  walletClient,
  publicClient,
}: {
  pool: `0x${string}`;
  run: (fn: () => Promise<unknown>) => Promise<void>;
  walletClient: WalletClient;
  publicClient: PublicClient;
}) {
  const [lines, setLines] = useState("");

  return (
    <div>
      <textarea
        rows={4}
        placeholder={"0xabc...,1000000\n0xdef...,2000000"}
        value={lines}
        onChange={(e) => setLines(e.target.value)}
      />
      <button
        type="button"
        onClick={() =>
          run(async () => {
            const rows = lines
              .split("\n")
              .map((l) => l.trim())
              .filter(Boolean);
            const members: `0x${string}`[] = [];
            const amounts: bigint[] = [];
            for (const row of rows) {
              const [addr, amt] = row.split(",").map((s) => s.trim());
              if (!addr || !isAddress(addr)) throw new Error(`Invalid address in row: ${row}`);
              members.push(addr);
              amounts.push(BigInt(amt));
            }
            const hash = await walletClient.writeContract({
              chain: walletClient.chain,
              account: walletClient.account!,
              address: pool,
              abi: rttmPoolAbi,
              functionName: "completeGenesis",
              args: [members, amounts],
            });
            await publicClient.waitForTransactionReceipt({ hash });
          })
        }
      >
        completeGenesis(members, amounts)
      </button>
    </div>
  );
}

function TreasuryApproveSection({
  pool,
  run,
  walletClient,
  publicClient,
}: {
  pool: `0x${string}`;
  run: (fn: () => Promise<unknown>) => Promise<void>;
  walletClient: WalletClient;
  publicClient: PublicClient;
}) {
  const [amt, setAmt] = useState(
    "115792089237316195423570985008687907853269984665640564039457584007913129639935",
  );
  return (
    <div>
      <label htmlFor="appr-amt">approve(pool, amount)</label>
      <input id="appr-amt" value={amt} onChange={(e) => setAmt(e.target.value)} />
      <button
        type="button"
        onClick={() =>
          run(async () => {
            const treasury = (await publicClient.readContract({
              address: pool,
              abi: rttmPoolAbi,
              functionName: "treasuryToken",
            })) as `0x${string}`;
            const hash = await walletClient.writeContract({
              chain: walletClient.chain,
              account: walletClient.account!,
              address: treasury,
              abi: erc20Abi,
              functionName: "approve",
              args: [pool, BigInt(amt)],
            });
            await publicClient.waitForTransactionReceipt({ hash });
          })
        }
      >
        Approve treasury → pool
      </button>
    </div>
  );
}

function ApplyJoinForm({
  pool,
  run,
  walletClient,
  publicClient,
}: {
  pool: `0x${string}`;
  run: (fn: () => Promise<unknown>) => Promise<void>;
  walletClient: WalletClient;
  publicClient: PublicClient;
}) {
  const [amt, setAmt] = useState("");
  return (
    <div>
      <label htmlFor="aj">applyJoin(amount)</label>
      <input id="aj" placeholder="base units" value={amt} onChange={(e) => setAmt(e.target.value)} />
      <button
        type="button"
        onClick={() => {
          const v = BigInt(amt);
          return run(async () => {
            const hash = await walletClient.writeContract({
              chain: walletClient.chain,
              account: walletClient.account!,
              address: pool,
              abi: rttmPoolAbi,
              functionName: "applyJoin",
              args: [v],
            });
            await publicClient.waitForTransactionReceipt({ hash });
          });
        }}
      >
        Apply
      </button>
    </div>
  );
}

function CastVoteForm({
  pool,
  run,
  walletClient,
  publicClient,
}: {
  pool: `0x${string}`;
  run: (fn: () => Promise<unknown>) => Promise<void>;
  walletClient: WalletClient;
  publicClient: PublicClient;
}) {
  const [proposalId, setProposalId] = useState("");
  const [support, setSupport] = useState<"0" | "1">("1");

  return (
    <div>
      <label>castVote(proposalId, support)</label>
      <input
        placeholder="proposal id"
        value={proposalId}
        onChange={(e) => setProposalId(e.target.value)}
      />
      <select value={support} onChange={(e) => setSupport(e.target.value as "0" | "1")}>
        <option value="1">1 = yes (adds weight)</option>
        <option value="0">0 = no signal (weight not added)</option>
      </select>
      <button
        type="button"
        onClick={() => {
          if (!proposalId) return;
          const id = BigInt(proposalId);
          const s = Number(support) as 0 | 1;
          return run(async () => {
            const hash = await walletClient.writeContract({
              chain: walletClient.chain,
              account: walletClient.account!,
              address: pool,
              abi: rttmPoolAbi,
              functionName: "castVote",
              args: [id, s],
            });
            await publicClient.waitForTransactionReceipt({ hash });
          });
        }}
      >
        castVote
      </button>
    </div>
  );
}

function SimpleUintForm({ label, onSubmit }: { label: string; onSubmit: (v: bigint) => void }) {
  const [v, setV] = useState("");
  return (
    <div>
      <label>{label}</label>
      <input value={v} onChange={(e) => setV(e.target.value)} />
      <button
        type="button"
        onClick={() => {
          if (!v) return;
          onSubmit(BigInt(v));
        }}
      >
        Submit
      </button>
    </div>
  );
}

function AddrForm({ label, onSubmit }: { label: string; onSubmit: (a: string) => void }) {
  const [v, setV] = useState("");
  return (
    <div>
      <label>{label}</label>
      <input value={v} onChange={(e) => setV(e.target.value)} placeholder="0x…" />
      <button
        type="button"
        onClick={() => {
          if (!v.startsWith("0x") || v.length !== 42) return;
          onSubmit(v);
        }}
      >
        Submit
      </button>
    </div>
  );
}

function ExternalProposalForm({
  pool,
  run,
  walletClient,
  publicClient,
}: {
  pool: `0x${string}`;
  run: (fn: () => Promise<unknown>) => Promise<void>;
  walletClient: WalletClient;
  publicClient: PublicClient;
}) {
  const [target, setTarget] = useState<string>(pool);
  const [data, setData] = useState("0x");

  useEffect(() => {
    setTarget(pool);
  }, [pool]);

  return (
    <div>
      <label>proposeExternalCall(target, data)</label>
      <input placeholder="target 0x…" value={target} onChange={(e) => setTarget(e.target.value)} />
      <textarea
        rows={3}
        placeholder="calldata 0x…"
        value={data}
        onChange={(e) => setData(e.target.value)}
      />
      <button
        type="button"
        onClick={() => {
          if (!isHex(data) || !isAddress(target)) return;
          return run(async () => {
            const hash = await walletClient.writeContract({
              chain: walletClient.chain,
              account: walletClient.account!,
              address: pool,
              abi: rttmPoolAbi,
              functionName: "proposeExternalCall",
              args: [target as `0x${string}`, data as `0x${string}`],
            });
            await publicClient.waitForTransactionReceipt({ hash });
          });
        }}
      >
        Propose external call
      </button>
    </div>
  );
}

function SetPoolParamsEncode() {
  const [memberMinimum, setMemberMinimum] = useState("");
  const [joinMinimum, setJoinMinimum] = useState("");
  const [votingPeriodBlocks, setVotingPeriodBlocks] = useState("");
  const [proposalPassBps, setProposalPassBps] = useState("5000");
  const [joinApprovalBps, setJoinApprovalBps] = useState("5000");
  const [out, setOut] = useState("");

  return (
    <div>
      <h3>Encode setPoolParams (governance)</h3>
      <input placeholder="memberMinimum" value={memberMinimum} onChange={(e) => setMemberMinimum(e.target.value)} />
      <input placeholder="joinMinimum" value={joinMinimum} onChange={(e) => setJoinMinimum(e.target.value)} />
      <input
        placeholder="votingPeriodBlocks"
        value={votingPeriodBlocks}
        onChange={(e) => setVotingPeriodBlocks(e.target.value)}
      />
      <input placeholder="proposalPassBps" value={proposalPassBps} onChange={(e) => setProposalPassBps(e.target.value)} />
      <input
        placeholder="joinApprovalBps"
        value={joinApprovalBps}
        onChange={(e) => setJoinApprovalBps(e.target.value)}
      />
      <button
        type="button"
        onClick={() => {
          const data = encodeFunctionData({
            abi: rttmPoolAbi,
            functionName: "setPoolParams",
            args: [
              {
                memberMinimum: BigInt(memberMinimum),
                joinMinimum: BigInt(joinMinimum),
                votingPeriodBlocks: BigInt(votingPeriodBlocks),
                proposalPassBps: BigInt(proposalPassBps),
                joinApprovalBps: BigInt(joinApprovalBps),
              },
            ],
          });
          setOut(data);
        }}
      >
        Generate calldata
      </button>
      {out && (
        <p>
          <code style={{ wordBreak: "break-all" }}>{out}</code>
        </p>
      )}
    </div>
  );
}

function SetDuesParamsEncode() {
  const [duesAmount, setDuesAmount] = useState("");
  const [duesPeriodSeconds, setDuesPeriodSeconds] = useState("");
  const [duesGraceSeconds, setDuesGraceSeconds] = useState("");
  const [out, setOut] = useState("");

  return (
    <div>
      <h3>Encode setDuesParams (governance)</h3>
      <input placeholder="duesAmount" value={duesAmount} onChange={(e) => setDuesAmount(e.target.value)} />
      <input
        placeholder="duesPeriodSeconds"
        value={duesPeriodSeconds}
        onChange={(e) => setDuesPeriodSeconds(e.target.value)}
      />
      <input
        placeholder="duesGraceSeconds"
        value={duesGraceSeconds}
        onChange={(e) => setDuesGraceSeconds(e.target.value)}
      />
      <button
        type="button"
        onClick={() => {
          const data = encodeFunctionData({
            abi: rttmPoolAbi,
            functionName: "setDuesParams",
            args: [BigInt(duesAmount), BigInt(duesPeriodSeconds), BigInt(duesGraceSeconds)],
          });
          setOut(data);
        }}
      >
        Generate calldata
      </button>
      {out && (
        <p>
          <code style={{ wordBreak: "break-all" }}>{out}</code>
        </p>
      )}
    </div>
  );
}

function SetTreasuryTokenEncode() {
  const [token, setToken] = useState("");
  const [out, setOut] = useState("");

  return (
    <div>
      <h3>Encode setTreasuryToken (governance; pool must be empty)</h3>
      <input placeholder="new treasury 0x…" value={token} onChange={(e) => setToken(e.target.value)} />
      <button
        type="button"
        onClick={() => {
          if (!isAddress(token)) return;
          const data = encodeFunctionData({
            abi: rttmPoolAbi,
            functionName: "setTreasuryToken",
            args: [token as `0x${string}`],
          });
          setOut(data);
        }}
      >
        Generate calldata
      </button>
      {out && (
        <p>
          <code style={{ wordBreak: "break-all" }}>{out}</code>
        </p>
      )}
    </div>
  );
}
