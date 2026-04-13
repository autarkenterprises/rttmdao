/** Mirrors `RttmPool._passesBps`: strict fraction of supply (BPS denominator 10_000). */
export function passesBps(yesVotes: bigint, supply: bigint, thresholdBps: bigint): boolean {
  if (yesVotes === 0n) return false;
  return yesVotes * 10_000n > supply * thresholdBps;
}
