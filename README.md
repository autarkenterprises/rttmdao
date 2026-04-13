# RttM pool DAO

Foundry project implementing **`RttmPool`**: a member-governed **ERC20 treasury** with **dues**, **kick** for delinquency, **minimum-stake** rules, and **snapshot-based** strict-majority governance.

## Web app (GitHub Pages)

**Live site:** [https://autarkenterprises.github.io/rttmdao/](https://autarkenterprises.github.io/rttmdao/)

The Vite app (State / dApp / About) is built by [`.github/workflows/pages.yml`](.github/workflows/pages.yml). Set `VITE_POOL_SEPOLIA` / `VITE_POOL_MAINNET` and optional `VITE_BASE` (e.g. `/rttmdao/` for this URL) in GitHub Actions secrets/variables.

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
