import { useCallback, useEffect, useState } from "react";
import { formatUnits } from "viem";
import { erc20Abi, rttmPoolAbi } from "../abi";
import { usePoolDeployment } from "../hooks/usePoolAddress";
import { useWeb3 } from "../web3";

const KINDS = ["ExternalCall", "ApproveJoin", "RejectJoin"] as const;

type ProposalView = {
  kind: number;
  proposer: `0x${string}`;
  target: `0x${string}`;
  applicant: `0x${string}`;
  snapshot: bigint;
  votingDeadline: bigint;
  yesVotes: bigint;
  thresholdBps: bigint;
  executed: boolean;
};

type MemberRow = {
  address: `0x${string}`;
  isMember: boolean;
  shares: bigint;
  assets: bigint;
};

export function DaoStatePage() {
  const { pool, fromBlock } = usePoolDeployment();
  const { publicClient, account } = useWeb3();
  const [events, setEvents] = useState<{ name: string; args: string }[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const [treasury, setTreasury] = useState<`0x${string}` | undefined>();
  const [decimals, setDecimals] = useState(18);
  const [sym, setSym] = useState<string>("");
  const [proposalCount, setProposalCount] = useState<bigint | undefined>();
  const [myShares, setMyShares] = useState<bigint | undefined>();
  const [myAssets, setMyAssets] = useState<bigint | undefined>();
  const [proposalRows, setProposalRows] = useState<{ id: number; p: ProposalView }[]>([]);
  const [poolParams, setPoolParams] = useState<{
    genesisAuthority: `0x${string}`;
    genesisCompleted: boolean;
    memberMinimum: bigint;
    joinMinimum: bigint;
    votingPeriodBlocks: bigint;
    proposalPassBps: bigint;
    joinApprovalBps: bigint;
    duesAmount: bigint;
    duesPeriodSeconds: bigint;
    duesGraceSeconds: bigint;
  } | null>(null);
  const [memberRows, setMemberRows] = useState<MemberRow[]>([]);

  const refreshReads = useCallback(async () => {
    if (!pool) return;
    const t = (await publicClient.readContract({
      address: pool,
      abi: rttmPoolAbi,
      functionName: "treasuryToken",
    })) as `0x${string}`;
    setTreasury(t);
    if (t !== "0x0000000000000000000000000000000000000000") {
      const d = await publicClient.readContract({
        address: t,
        abi: erc20Abi,
        functionName: "decimals",
      });
      setDecimals(Number(d));
      const s = await publicClient.readContract({
        address: t,
        abi: erc20Abi,
        functionName: "symbol",
      });
      setSym(s);
    }
    const pc = await publicClient.readContract({
      address: pool,
      abi: rttmPoolAbi,
      functionName: "proposalCount",
    });
    setProposalCount(pc as bigint);

    const [
      genesisAuthority,
      genesisCompleted,
      memberMinimum,
      joinMinimum,
      votingPeriodBlocks,
      proposalPassBps,
      joinApprovalBps,
      duesAmount,
      duesPeriodSeconds,
      duesGraceSeconds,
    ] = await Promise.all([
      publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "genesisAuthority",
      }),
      publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "genesisCompleted",
      }),
      publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "memberMinimum",
      }),
      publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "joinMinimum",
      }),
      publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "votingPeriodBlocks",
      }),
      publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "proposalPassBps",
      }),
      publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "joinApprovalBps",
      }),
      publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "duesAmount",
      }),
      publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "duesPeriodSeconds",
      }),
      publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "duesGraceSeconds",
      }),
    ]);

    setPoolParams({
      genesisAuthority: genesisAuthority as `0x${string}`,
      genesisCompleted: genesisCompleted as boolean,
      memberMinimum: memberMinimum as bigint,
      joinMinimum: joinMinimum as bigint,
      votingPeriodBlocks: votingPeriodBlocks as bigint,
      proposalPassBps: proposalPassBps as bigint,
      joinApprovalBps: joinApprovalBps as bigint,
      duesAmount: duesAmount as bigint,
      duesPeriodSeconds: duesPeriodSeconds as bigint,
      duesGraceSeconds: duesGraceSeconds as bigint,
    });

    if (account) {
      const sh = await publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "balanceOf",
        args: [account],
      });
      setMyShares(sh as bigint);
      const as = await publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "assetsOf",
        args: [account],
      });
      setMyAssets(as as bigint);
    } else {
      setMyShares(undefined);
      setMyAssets(undefined);
    }

    const cnt = Number(pc as bigint);
    if (cnt === 0) {
      setProposalRows([]);
      return;
    }
    const out: { id: number; p: ProposalView }[] = [];
    for (let i = Math.max(0, cnt - 10); i < cnt; i++) {
      const raw = await publicClient.readContract({
        address: pool,
        abi: rttmPoolAbi,
        functionName: "getProposal",
        args: [BigInt(i)],
      });
      const p = raw as ProposalView;
      out.push({ id: i, p });
    }
    setProposalRows(out);
  }, [pool, publicClient, account]);

  const refresh = useCallback(async () => {
    if (!pool) return;
    setLoading(true);
    setErr(null);
    try {
      await refreshReads();
      const evs = await publicClient.getContractEvents({
        address: pool,
        abi: rttmPoolAbi,
        fromBlock: fromBlock ?? 0n,
        toBlock: "latest",
      });
      const rows = evs.slice(-200).map((e) => ({
        name: e.eventName,
        args: JSON.stringify(e.args, (_, v) => (typeof v === "bigint" ? v.toString() : v)),
      }));
      setEvents(rows.reverse());

      const joined = new Set<string>();
      for (const e of evs) {
        if (e.eventName !== "Joined") continue;
        const a = (e.args as { member?: `0x${string}` }).member;
        if (a) joined.add(a.toLowerCase());
      }
      const addrs = [...joined].slice(0, 80) as `0x${string}`[];
      const mrows: MemberRow[] = await Promise.all(
        addrs.map(async (addr) => {
          const [isMem, bal, ast] = await Promise.all([
            publicClient.readContract({
              address: pool,
              abi: rttmPoolAbi,
              functionName: "isMember",
              args: [addr],
            }),
            publicClient.readContract({
              address: pool,
              abi: rttmPoolAbi,
              functionName: "balanceOf",
              args: [addr],
            }),
            publicClient.readContract({
              address: pool,
              abi: rttmPoolAbi,
              functionName: "assetsOf",
              args: [addr],
            }),
          ]);
          return {
            address: addr,
            isMember: isMem as boolean,
            shares: bal as bigint,
            assets: ast as bigint,
          };
        }),
      );
      setMemberRows(
        mrows.sort((a, b) => (a.shares === b.shares ? 0 : a.shares > b.shares ? -1 : 1)),
      );
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [pool, fromBlock, publicClient, refreshReads]);

  useEffect(() => {
    void refresh();
    const t = setInterval(() => void refresh(), 25_000);
    return () => clearInterval(t);
  }, [refresh]);

  return (
    <div>
      <h1>State of the DAO</h1>
      <p className="muted">
        Live view from the public RPC (last ~200 events). Set <code>VITE_FROM_BLOCK_*</code> for faster log queries.
      </p>
      {pool && (
        <div className="card">
          <h2>Pool</h2>
          <p>
            <code>{pool}</code>
          </p>
          <p>
            Treasury: <code>{treasury}</code> {sym ? `(${sym})` : ""}
          </p>
          <p>Proposals (count): {proposalCount?.toString() ?? "…"}</p>
          {account && (
            <p>
              Your shares: {myShares?.toString() ?? "…"} — treasury claim (~):{" "}
              {myAssets !== undefined ? formatUnits(myAssets, decimals) : "…"} {sym}
            </p>
          )}
          <button type="button" disabled={loading} onClick={() => void refresh()}>
            {loading ? "Refreshing…" : "Refresh now"}
          </button>
          {err && <p className="err">{err}</p>}
        </div>
      )}
      {pool && poolParams && (
        <div className="card">
          <h2>Parameters (on-chain)</h2>
          <p>
            Genesis authority: <code>{poolParams.genesisAuthority}</code> — completed:{" "}
            {poolParams.genesisCompleted ? "yes" : "no"}
          </p>
          <ul>
            <li>
              memberMinimum / joinMinimum (base units): {poolParams.memberMinimum.toString()} /{" "}
              {poolParams.joinMinimum.toString()}
            </li>
            <li>votingPeriodBlocks: {poolParams.votingPeriodBlocks.toString()}</li>
            <li>
              proposalPassBps / joinApprovalBps: {poolParams.proposalPassBps.toString()} /{" "}
              {poolParams.joinApprovalBps.toString()} (pass if yes*10000 &gt; supply*bps)
            </li>
            <li>
              dues: amount {poolParams.duesAmount.toString()}, periodSeconds {poolParams.duesPeriodSeconds.toString()},
              graceSeconds {poolParams.duesGraceSeconds.toString()}
            </li>
          </ul>
        </div>
      )}
      {pool && (
        <div className="card">
          <h2>Members (from Joined events)</h2>
          <p className="muted">
            Addresses seen in <code>Joined</code> logs (max 80); current row is a live read of{" "}
            <code>isMember</code>, shares, and treasury claim.
          </p>
          {memberRows.length === 0 ? (
            <p className="muted">No Joined events in range.</p>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>address</th>
                  <th>member</th>
                  <th>shares</th>
                  <th>assets (~)</th>
                </tr>
              </thead>
              <tbody>
                {memberRows.map((m) => (
                  <tr key={m.address}>
                    <td>
                      <code>{m.address}</code>
                    </td>
                    <td>{m.isMember ? "yes" : "no"}</td>
                    <td>{m.shares.toString()}</td>
                    <td>
                      {formatUnits(m.assets, decimals)} {sym}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
      <div className="card">
        <h2>Recent events (indexer)</h2>
        <table>
          <thead>
            <tr>
              <th>Event</th>
              <th>Args</th>
            </tr>
          </thead>
          <tbody>
            {events.map((r, i) => (
              <tr key={`${r.name}-${i}`}>
                <td>{r.name}</td>
                <td style={{ wordBreak: "break-all", fontSize: "0.75rem" }}>{r.args}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="card">
        <h2>Proposal snapshot</h2>
        {!pool || !proposalCount || proposalCount === 0n ? (
          <p className="muted">No proposals yet.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>id</th>
                <th>kind</th>
                <th>ref</th>
                <th>deadline</th>
                <th>yes</th>
                <th>bps</th>
                <th>done</th>
              </tr>
            </thead>
            <tbody>
              {proposalRows.map(({ id, p }) => {
                const k = Number(p.kind);
                const ref =
                  k === 0 ? p.target : p.applicant;
                return (
                <tr key={id}>
                  <td>{id}</td>
                  <td>{KINDS[k] ?? k}</td>
                  <td>
                    <code style={{ fontSize: "0.75rem" }}>{ref}</code>
                  </td>
                  <td>{p.votingDeadline.toString()}</td>
                  <td>{p.yesVotes.toString()}</td>
                  <td>{p.thresholdBps.toString()}</td>
                  <td>{p.executed ? "yes" : "no"}</td>
                </tr>
              );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
