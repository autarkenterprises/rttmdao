import { describe, expect, it } from "vitest";
import { formatBps, formatDurationSeconds } from "./formatOnChain";

describe("formatDurationSeconds", () => {
  it("formats whole days", () => {
    expect(formatDurationSeconds(2592000n)).toContain("30 days");
    expect(formatDurationSeconds(2592000n)).toContain("2592000");
  });

  it("formats zero", () => {
    expect(formatDurationSeconds(0n)).toBe("0 s");
  });
});

describe("formatBps", () => {
  it("formats 5000 bps", () => {
    expect(formatBps(5000n)).toBe("50%");
  });
});
