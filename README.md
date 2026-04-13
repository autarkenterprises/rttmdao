# RttM pool DAO

Foundry project implementing **`RttmPool`**: a member-governed **ERC20 treasury** with **dues**, **kick** for delinquency, **minimum-stake** rules, and **snapshot-based** strict-majority governance.

## Documentation

- **[DAO reference](./docs/DAO.md)** — features, configuration, governance, examples (including Polymarket-style proposals), and whether votes require redeploying contracts.
- **[Future work](./docs/FUTURE.md)** — proposal builder helper (planned).

## Quick start

```shell
forge build
forge test
```

## Deploy

Set `TREASURY_TOKEN` to your ERC20 (e.g. USDC). See `script/DeployRttmPool.s.sol` for env vars.

```shell
forge script script/DeployRttmPool.s.sol:DeployRttmPool --rpc-url <RPC_URL> --broadcast
```

## Foundry

https://book.getfoundry.sh/
