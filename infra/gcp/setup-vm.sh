#!/usr/bin/env bash
# Provision a single e2-micro VM (GCP Always Free eligible in us-central1 / us-east1 / us-west1)
# and open TCP 8080 for the indexer HTTP API.
#
# Prereqs:
#   gcloud auth login
#   gcloud config set project YOUR_PROJECT_ID
#   Billing enabled on the project (required even for free-tier usage)
#
# Usage:
#   export POOL_ADDRESS=0xYourPool
#   export RPC_URL="https://..."   # Sepolia (or other) HTTPS RPC
#   ./infra/gcp/setup-vm.sh
#
# Optional:
#   export GCP_ZONE=us-central1-a
#   export VM_NAME=rttmdao-indexer
#   export CHAIN_ID=11155111
#   export FROM_BLOCK=0
#   export GIT_REPO_URL=https://github.com/autarkenterprises/rttmdao.git
#   export GIT_BRANCH=master
#
# Or create infra/gcp/.env (see infra/gcp/.env.example) — sourced automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

POOL_ADDRESS="${POOL_ADDRESS:-0x0000000000000000000000000000000000000000}"
RPC_URL="${RPC_URL:-https://rpc.sepolia.org}"

if [[ "$POOL_ADDRESS" == "0x0000000000000000000000000000000000000000" ]]; then
  echo "WARNING: POOL_ADDRESS is zero — indexer /api/snapshot will error until you set a real pool (metadata + VM reset, or edit /etc/default/rttm-indexer on the VM)."
fi

PROJECT="$(gcloud config get-value project 2>/dev/null)"
[[ -n "$PROJECT" ]] || {
  echo "No gcloud project. Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
}

ZONE="${GCP_ZONE:-us-central1-a}"
VM_NAME="${VM_NAME:-rttmdao-indexer}"
CHAIN_ID="${CHAIN_ID:-11155111}"
FROM_BLOCK="${FROM_BLOCK:-0}"
GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/autarkenterprises/rttmdao.git}"
GIT_BRANCH="${GIT_BRANCH:-master}"
CORS_ORIGIN="${CORS_ORIGIN:-https://autarkenterprises.github.io}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STARTUP="${ROOT}/infra/gcp/startup-indexer.sh"
[[ -f "$STARTUP" ]] || {
  echo "Missing $STARTUP"
  exit 1
}

gcloud services enable compute.googleapis.com --project "$PROJECT" --quiet

if ! gcloud compute firewall-rules describe rttm-indexer-http --project "$PROJECT" --quiet &>/dev/null; then
  gcloud compute firewall-rules create rttm-indexer-http \
    --project "$PROJECT" \
    --quiet \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:8080 \
    --target-tags=rttm-indexer \
    --description="HTTP JSON indexer for RttM DAO"
else
  echo "Firewall rule rttm-indexer-http already exists"
fi

META="POOL_ADDRESS=${POOL_ADDRESS},RPC_URL=${RPC_URL},CHAIN_ID=${CHAIN_ID},FROM_BLOCK=${FROM_BLOCK}"
META+=",GIT_REPO_URL=${GIT_REPO_URL},GIT_BRANCH=${GIT_BRANCH},CORS_ORIGIN=${CORS_ORIGIN}"

if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT" --quiet &>/dev/null; then
  echo "Instance $VM_NAME already exists in $ZONE. Updating metadata & resetting (re-runs startup on reboot)..."
  gcloud compute instances add-metadata "$VM_NAME" --zone="$ZONE" --project="$PROJECT" --quiet --metadata="$META"
  echo "To apply startup again: gcloud compute instances reset $VM_NAME --zone=$ZONE --project=$PROJECT --quiet"
  exit 0
fi

gcloud compute instances create "$VM_NAME" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --quiet \
  --machine-type=e2-micro \
  --tags=rttm-indexer,http-server \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=30GB \
  --metadata-from-file=startup-script="$STARTUP" \
  --metadata="$META"

IP="$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT" --quiet --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"

echo ""
echo "VM created: $VM_NAME ($ZONE)"
echo "External IP: $IP"
echo "Wait 3–6 minutes for startup (Node install + git clone + npm ci + build)."
echo "Then:"
echo "  curl -sS http://$IP:8080/health"
echo "  curl -sS http://$IP:8080/api/snapshot | head"
echo ""
echo "If health shows an error, SSH in and check:"
echo "  sudo journalctl -u rttm-indexer -f"
echo "  sudo cat /var/log/rttm-indexer-startup.log"
