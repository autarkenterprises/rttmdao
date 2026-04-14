import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Abi } from "viem";

const dir = dirname(fileURLToPath(import.meta.url));

export function loadPoolAbi(): Abi {
  return JSON.parse(readFileSync(join(dir, "rttmPoolAbi.json"), "utf8")) as Abi;
}
