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
#   export VM_NAME=rttm-indexer
#   export CHAIN_ID=11155111
#   export FROM_BLOCK=0
#   export GIT_REPO_URL=https://github.com/autarkenterprises/rttmdao.git
#   export GIT_BRANCH=master

set -euo pipefail

: "${POOL_ADDRESS:?Export POOL_ADDRESS (0x… pool contract)}"
: "${RPC_URL:?Export RPC_URL (HTTPS RPC endpoint)}"

PROJECT="$(gcloud config get-value project 2>/dev/null)"
[[ -n "$PROJECT" ]] || {
  echo "No gcloud project. Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
}

ZONE="${GCP_ZONE:-us-central1-a}"
VM_NAME="${VM_NAME:-rttm-indexer}"
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

gcloud services enable compute.googleapis.com --project "$PROJECT"

if ! gcloud compute firewall-rules describe rttm-indexer-http --project "$PROJECT" &>/dev/null; then
  gcloud compute firewall-rules create rttm-indexer-http \
    --project "$PROJECT" \
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

if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project "$PROJECT" &>/dev/null; then
  echo "Instance $VM_NAME already exists in $ZONE. Updating metadata & resetting (re-runs startup on reboot)..."
  gcloud compute instances add-metadata "$VM_NAME" --zone="$ZONE" --project "$PROJECT" --metadata="$META"
  echo "To apply startup again: gcloud compute instances reset $VM_NAME --zone=$ZONE"
  exit 0
fi

gcloud compute instances create "$VM_NAME" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --machine-type=e2-micro \
  --tags=rttm-indexer,http-server \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=30GB \
  --metadata-from-file=startup-script="$STARTUP" \
  --metadata="$META"

IP="$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"

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
