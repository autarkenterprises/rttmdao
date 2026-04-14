# GCP indexer VM (free tier)

Runs [`apps/indexer`](../../apps/indexer): a small **Node + viem** service that polls your pool and exposes:

- `GET /health` — liveness + last refresh time  
- `GET /api/snapshot` — JSON snapshot (params, members, proposals tail, recent events)

## Always Free (typical)

- **Machine:** `e2-micro`  
- **Regions:** e.g. `us-central1`, `us-east1`, `us-west1` (confirm current [Free Tier](https://cloud.google.com/free/docs/free-cloud-features#compute) docs)  
- **Disk:** 30 GB standard persistent boot disk stays within common free allowances when you run one small VM.

You still need a **billing account** attached to the project; charges should stay **$0** if you stay within free limits.

## One-time setup

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

Enable billing for the project in Cloud Console if prompted.

## Create the VM

From the repo root:

```bash
chmod +x infra/gcp/setup-vm.sh infra/gcp/startup-indexer.sh

export POOL_ADDRESS=0xYourDeployedPool
export RPC_URL="https://sepolia.infura.io/v3/KEY"   # or Alchemy, etc.

./infra/gcp/setup-vm.sh
```

Optional environment variables are documented in `setup-vm.sh`.

## After boot

Startup logs:

```bash
gcloud compute ssh rttm-indexer --zone=us-central1-a -- sudo tail -f /var/log/rttm-indexer-startup.log
```

Service logs:

```bash
gcloud compute ssh rttm-indexer --zone=us-central1-a -- sudo journalctl -u rttm-indexer -f
```

## Private GitHub repo

The default startup script clones the **public** `autarkenterprises/rttmdao` repo. For a private fork, either:

- make the repo public for deploy, or  
- change `GIT_REPO_URL` / use a deploy token (not covered here—avoid putting tokens in instance metadata).

## Pointing the static site at the indexer

Set a build-time env var in the Pages workflow (or `.env.local`) such as `VITE_INDEXER_URL=http://EXTERNAL_IP:8080` and teach the web app to call `/api/snapshot` when set. (Wire-up can be added in a follow-up.)
