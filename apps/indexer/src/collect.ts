import { createPublicClient, defineChain, http, type Abi, type PublicClient } from "viem";
import { erc20Abi } from "./erc20.js";
import { loadPoolAbi } from "./loadAbi.js";

export type IndexerSnapshot = {
  chainId: number;
  pool: `0x${string}`;
  updatedAt: string;
  error?: string;
  treasury?: `0x${string}`;
  treasurySymbol?: string;
  treasuryDecimals?: number;
  proposalCount?: string;
  poolParams?: Record<string, string | boolean>;
  proposals?: Array<Record<string, unknown>>;
  members?: Array<Record<string, string | boolean>>;
  events?: Array<{ name: string; args: string }>;
};

export function makeClient(rpcUrl: string, chainId: number): PublicClient {
  const chain = defineChain({
    id: chainId,
    name: "custom",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl] } },
  });
  return createPublicClient({ chain, transport: http(rpcUrl) });
}

export async function collectSnapshot(opts: {
  client: PublicClient;
  pool: `0x${string}`;
  fromBlock: bigint;
  abi: Abi;
  maxMembers?: number;
  maxEvents?: number;
  proposalTail?: number;
}): Promise<IndexerSnapshot> {
  const {
    client,
    pool,
    fromBlock,
    abi,
    maxMembers = 80,
    maxEvents = 200,
    proposalTail = 10,
  } = opts;

  const chainId = client.chain?.id ?? 0;
  const base: IndexerSnapshot = {
    chainId,
    pool,
    updatedAt: new Date().toISOString(),
  };

  try {
    const treasury = (await client.readContract({
      address: pool,
      abi,
      functionName: "treasuryToken",
    })) as `0x${string}`;
    base.treasury = treasury;

    let decimals = 18;
    let sym = "";
    if (treasury !== "0x0000000000000000000000000000000000000000") {
      const d = await client.readContract({
        address: treasury,
        abi: erc20Abi,
        functionName: "decimals",
      });
      decimals = Number(d);
      sym = await client.readContract({
        address: treasury,
        abi: erc20Abi,
        functionName: "symbol",
      });
    }
    base.treasuryDecimals = decimals;
    base.treasurySymbol = sym;

    const pc = await client.readContract({
      address: pool,
      abi,
      functionName: "proposalCount",
    });
    base.proposalCount = (pc as bigint).toString();

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
      client.readContract({ address: pool, abi, functionName: "genesisAuthority" }),
      client.readContract({ address: pool, abi, functionName: "genesisCompleted" }),
      client.readContract({ address: pool, abi, functionName: "memberMinimum" }),
      client.readContract({ address: pool, abi, functionName: "joinMinimum" }),
      client.readContract({ address: pool, abi, functionName: "votingPeriodBlocks" }),
      client.readContract({ address: pool, abi, functionName: "proposalPassBps" }),
      client.readContract({ address: pool, abi, functionName: "joinApprovalBps" }),
      client.readContract({ address: pool, abi, functionName: "duesAmount" }),
      client.readContract({ address: pool, abi, functionName: "duesPeriodSeconds" }),
      client.readContract({ address: pool, abi, functionName: "duesGraceSeconds" }),
    ]);

    base.poolParams = {
      genesisAuthority: String(genesisAuthority),
      genesisCompleted: genesisCompleted as boolean,
      memberMinimum: (memberMinimum as bigint).toString(),
      joinMinimum: (joinMinimum as bigint).toString(),
      votingPeriodBlocks: (votingPeriodBlocks as bigint).toString(),
      proposalPassBps: (proposalPassBps as bigint).toString(),
      joinApprovalBps: (joinApprovalBps as bigint).toString(),
      duesAmount: (duesAmount as bigint).toString(),
      duesPeriodSeconds: (duesPeriodSeconds as bigint).toString(),
      duesGraceSeconds: (duesGraceSeconds as bigint).toString(),
    };

    const cnt = Number(pc as bigint);
    const proposals: Array<Record<string, unknown>> = [];
    if (cnt > 0) {
      for (let i = Math.max(0, cnt - proposalTail); i < cnt; i++) {
        const raw = await client.readContract({
          address: pool,
          abi,
          functionName: "getProposal",
          args: [BigInt(i)],
        });
        const p = raw as {
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
        proposals.push({
          id: i,
          kind: p.kind,
          proposer: p.proposer,
          target: p.target,
          applicant: p.applicant,
          snapshot: p.snapshot.toString(),
          votingDeadline: p.votingDeadline.toString(),
          yesVotes: p.yesVotes.toString(),
          thresholdBps: p.thresholdBps.toString(),
          executed: p.executed,
        });
      }
    }
    base.proposals = proposals;

    const evs = await client.getContractEvents({
      address: pool,
      abi,
      fromBlock,
      toBlock: "latest",
    });
    const tail = evs.slice(-maxEvents);
    base.events = tail.map((e) => ({
      name: e.eventName,
      args: JSON.stringify(e.args, (_, v) => (typeof v === "bigint" ? v.toString() : v)),
    }));

    const joined = new Set<string>();
    for (const e of evs) {
      if (e.eventName !== "Joined") continue;
      const a = (e.args as { member?: `0x${string}` }).member;
      if (a) joined.add(a.toLowerCase());
    }
    const addrs = [...joined].slice(0, maxMembers) as `0x${string}`[];
    const members: Array<Record<string, string | boolean>> = [];
    for (const addr of addrs) {
      const [isMem, bal, ast] = await Promise.all([
        client.readContract({ address: pool, abi, functionName: "isMember", args: [addr] }),
        client.readContract({ address: pool, abi, functionName: "balanceOf", args: [addr] }),
        client.readContract({ address: pool, abi, functionName: "assetsOf", args: [addr] }),
      ]);
      members.push({
        address: addr,
        isMember: isMem as boolean,
        shares: (bal as bigint).toString(),
        assets: (ast as bigint).toString(),
      });
    }
    members.sort((a, b) => {
      const x = BigInt(String(b.shares));
      const y = BigInt(String(a.shares));
      if (x > y) return 1;
      if (x < y) return -1;
      return 0;
    });
    base.members = members;
  } catch (e) {
    base.error = e instanceof Error ? e.message : String(e);
  }

  return base;
}

export async function collectFromEnv(): Promise<IndexerSnapshot> {
  const rpcUrl = process.env.RPC_URL ?? "";
  const pool = (process.env.POOL_ADDRESS ?? "") as `0x${string}`;
  const chainId = Number(process.env.CHAIN_ID ?? "11155111");
  const fromBlock = BigInt(process.env.FROM_BLOCK ?? "0");

  if (!rpcUrl || !pool.startsWith("0x") || pool.length !== 42) {
    return {
      chainId,
      pool: pool || "0x0000000000000000000000000000000000000000",
      updatedAt: new Date().toISOString(),
      error: "Missing or invalid RPC_URL / POOL_ADDRESS",
    };
  }

  const client = makeClient(rpcUrl, chainId);
  const abi = loadPoolAbi();
  return collectSnapshot({ client, pool, fromBlock, abi });
}
