#!/usr/bin/env bash
# Runs on first boot of the indexer VM (Ubuntu 22.04).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
exec >/var/log/rttm-indexer-startup.log 2>&1

echo "[rttm-indexer] starting bootstrap $(date -Is)"

apt-get update -y
apt-get install -y ca-certificates curl git

# e2-micro is tight on RAM; add swap before npm ci
if ! swapon --show | grep -q swapfile; then
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

MD="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
HDR=(-H "Metadata-Flavor: Google")
POOL_ADDRESS="$(curl -fs "${HDR[@]}" "$MD/POOL_ADDRESS" 2>/dev/null || true)"
RPC_URL="$(curl -fs "${HDR[@]}" "$MD/RPC_URL" 2>/dev/null || true)"
CHAIN_ID="$(curl -fs "${HDR[@]}" "$MD/CHAIN_ID" 2>/dev/null || echo 11155111)"
FROM_BLOCK="$(curl -fs "${HDR[@]}" "$MD/FROM_BLOCK" 2>/dev/null || echo 0)"
GIT_REPO_URL="$(curl -fs "${HDR[@]}" "$MD/GIT_REPO_URL" 2>/dev/null || echo https://github.com/autarkenterprises/rttmdao.git)"
GIT_BRANCH="$(curl -fs "${HDR[@]}" "$MD/GIT_BRANCH" 2>/dev/null || echo master)"
CORS_ORIGIN="$(curl -fs "${HDR[@]}" "$MD/CORS_ORIGIN" 2>/dev/null || echo https://autarkenterprises.github.io)"

rm -rf /opt/rttmdao
git clone --depth 1 --branch "$GIT_BRANCH" "$GIT_REPO_URL" /opt/rttmdao

cd /opt/rttmdao/apps/indexer
npm ci
npm run build

cat >/etc/default/rttm-indexer <<EOF
POOL_ADDRESS=${POOL_ADDRESS}
RPC_URL=${RPC_URL}
CHAIN_ID=${CHAIN_ID}
FROM_BLOCK=${FROM_BLOCK}
PORT=8080
POLL_MS=25000
CORS_ORIGIN=${CORS_ORIGIN}
EOF

install -m0644 /opt/rttmdao/infra/gcp/rttm-indexer.service /etc/systemd/system/rttm-indexer.service
systemctl daemon-reload
systemctl enable rttm-indexer
systemctl restart rttm-indexer

echo "[rttm-indexer] done $(date -Is)"
