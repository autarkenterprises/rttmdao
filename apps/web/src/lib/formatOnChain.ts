/** Human-readable duration for second counts (typical chain time). */
export function formatDurationSeconds(sec: bigint): string {
  const s = sec;
  if (s === 0n) return "0 s";
  if (s % 86400n === 0n) {
    const d = s / 86400n;
    return `${d} day${d === 1n ? "" : "s"} (${sec.toString()} s)`;
  }
  if (s % 3600n === 0n) {
    const h = s / 3600n;
    return `${h} hour${h === 1n ? "" : "s"} (${sec.toString()} s)`;
  }
  if (s % 60n === 0n) {
    const m = s / 60n;
    return `${m} min (${sec.toString()} s)`;
  }
  return `${sec.toString()} s`;
}

/** BPS to percent string (e.g. 5000 -> "50%"). */
export function formatBps(bps: bigint): string {
  const whole = Number(bps) / 100;
  const frac = Number(bps) % 100;
  if (frac === 0) return `${whole}%`;
  return `${(Number(bps) / 100).toFixed(2)}%`;
}
