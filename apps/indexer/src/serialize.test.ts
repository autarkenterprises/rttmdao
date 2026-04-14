import { describe, expect, it } from "vitest";
import { jsonSafe } from "./serialize";

describe("jsonSafe", () => {
  it("stringifies bigint fields as strings", () => {
    const s = jsonSafe({ n: 1n, x: "a" });
    expect(s).toBe('{"n":"1","x":"a"}');
  });
});
