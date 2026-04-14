/** JSON.stringify that preserves bigints as decimal strings. */
export function jsonSafe(value: unknown): string {
  return JSON.stringify(value, (_, v) => (typeof v === "bigint" ? v.toString() : v));
}
