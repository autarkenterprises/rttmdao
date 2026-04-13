import { describe, expect, it } from "vitest";
import { passesBps } from "./bps";

describe("passesBps", () => {
  it("requires strictly more than threshold fraction", () => {
    expect(passesBps(6n, 10n, 5000n)).toBe(true);
    expect(passesBps(5n, 10n, 5000n)).toBe(false);
    expect(passesBps(5n, 10n, 5001n)).toBe(false);
    expect(passesBps(0n, 10n, 1n)).toBe(false);
  });
});
