# RttM pool DAO

Foundry project implementing **`RttmPool`**: a member-governed **ERC20 treasury** with **dues**, **kick** for delinquency, **minimum-stake** rules, and **snapshot-based** strict-majority governance.

## Web app (GitHub Pages)

**Live site:** [https://autarkenterprises.github.io/rttmdao/](https://autarkenterprises.github.io/rttmdao/)

The Vite app (State / dApp / About) is built by [`.github/workflows/pages.yml`](.github/workflows/pages.yml). Set `VITE_POOL_SEPOLIA` / `VITE_POOL_MAINNET` and optional `VITE_BASE` (e.g. `/rttmdao/` for this URL) in GitHub Actions secrets/variables.

### If the site returns 404

1. In the repo, open **Settings → Pages**. Under **Build and deployment**, set **Source** to **GitHub Actions** (not “Deploy from a branch”). Without this, the workflow never publishes a site and `github.io/.../rttmdao/` stays 404.
2. Open **Actions** and confirm **Deploy GitHub Pages** completed successfully (green). Re-run via **Run workflow** if needed (`workflow_dispatch` is enabled).
3. Optional: set repository variable **`VITE_BASE`** to `/rttmdao/` if you change the repo name (the workflow defaults to `/rttmdao/` when the variable is unset).

## Documentation

- **[DAO reference](./docs/DAO.md)** — features, configuration, governance, examples (including Polymarket-style proposals), and whether votes require redeploying contracts.
- **[Future work](./docs/FUTURE.md)** — proposal builder helper (planned).

## Quick start

```shell
forge build
forge test
```

## Indexer (optional GCP VM)

The [`apps/indexer`](./apps/indexer) service exposes `GET /api/snapshot` (pool params, members, proposals, events) for dashboards or future static-site integration. To run it on a free-tier **`e2-micro`** VM, see [`infra/gcp/README.md`](./infra/gcp/README.md) and run [`infra/gcp/setup-vm.sh`](./infra/gcp/setup-vm.sh) after `gcloud auth login`.

## Deploy

**Sepolia defaults (Ethereum testnet):**

- **Treasury token:** Circle **USDC** on Sepolia is `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` ([Circle USDC addresses](https://developers.circle.com/stablecoins/usdc-contract-addresses)). The deploy script uses this if **`TREASURY_TOKEN`** is unset.
- **RPC:** Public Sepolia endpoint **`https://rpc.sepolia.org`** is the default in `config/pool.defaults.json` and in the web app when `VITE_RPC_SEPOLIA` is unset.

Set `TREASURY_TOKEN` only if you want a different ERC20. See `script/DeployRttmPool.s.sol` for other env vars. **Never commit private keys.**

```shell
export SEPOLIA_RPC_URL=https://rpc.sepolia.org
forge script script/DeployRttmPool.s.sol:DeployRttmPool \
  --rpc-url "$SEPOLIA_RPC_URL" --broadcast
```

## Foundry

https://book.getfoundry.sh/
