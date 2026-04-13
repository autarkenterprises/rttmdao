# Future work

## Proposal builder helper

**Task:** Find or implement an off-chain (or small on-chain) **proposal builder** that:

- Encodes `target` + `calldata` for common DAO actions (treasury `transfer`, `approve`, known protocol routers, batched calls).
- Validates decimals (e.g. USDC 6), slippage / `minOut`, and chain-specific contract addresses before submission.
- Optionally wraps multi-step flows (e.g. `approve` + `swap`) behind a single `target` via multicall or a dedicated “spell” contract.

The core `RttmPool` only accepts one low-level call per `execute`; a helper reduces mistakes when members author governance payloads by hand.
