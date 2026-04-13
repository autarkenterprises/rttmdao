import { describe, expect, it } from "vitest";
import { encodeFunctionData } from "viem";
import { rttmPoolAbi } from "../abi";

describe("governance calldata helpers", () => {
  it("encodes setPoolParams tuple for viem proposals", () => {
    const data = encodeFunctionData({
      abi: rttmPoolAbi,
      functionName: "setPoolParams",
      args: [
        {
          memberMinimum: 1n,
          joinMinimum: 2n,
          votingPeriodBlocks: 3n,
          proposalPassBps: 5000n,
          joinApprovalBps: 5001n,
        },
      ],
    });
    expect(data.startsWith("0x")).toBe(true);
    expect(data.length).toBeGreaterThan(10);
  });

  it("encodes setDuesParams", () => {
    const data = encodeFunctionData({
      abi: rttmPoolAbi,
      functionName: "setDuesParams",
      args: [100n, 200n, 300n],
    });
    expect(data.startsWith("0x")).toBe(true);
  });

  it("encodes setTreasuryToken", () => {
    const data = encodeFunctionData({
      abi: rttmPoolAbi,
      functionName: "setTreasuryToken",
      args: ["0x0000000000000000000000000000000000000001"],
    });
    expect(data.startsWith("0x")).toBe(true);
  });
});
