/** Per-chain pool deployment. Set via Vite env at build time (see `.env.example`). */
export type Deployment = {
  pool: `0x${string}`;
  /** Optional: block pool was deployed (speeds log queries). */
  fromBlock?: bigint;
};

const zero = "0x0000000000000000000000000000000000000000" as const;

function addr(env: string | undefined): `0x${string}` {
  if (env && env.startsWith("0x") && env.length === 42) return env as `0x${string}`;
  return zero;
}

export const deployments: Record<number, Deployment> = {
  1: {
    pool: addr(import.meta.env.VITE_POOL_MAINNET),
    fromBlock: import.meta.env.VITE_FROM_BLOCK_MAINNET
      ? BigInt(import.meta.env.VITE_FROM_BLOCK_MAINNET)
      : undefined,
  },
  11155111: {
    pool: addr(import.meta.env.VITE_POOL_SEPOLIA),
    fromBlock: import.meta.env.VITE_FROM_BLOCK_SEPOLIA
      ? BigInt(import.meta.env.VITE_FROM_BLOCK_SEPOLIA)
      : undefined,
  },
};

export function deploymentForChain(chainId: number): Deployment | undefined {
  return deployments[chainId];
}
