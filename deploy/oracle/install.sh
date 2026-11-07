#!/usr/bin/env bash
# Deploy FreeLLMAPI ONLY on an already-provisioned Ubuntu ARM64 OCI host.
# No OCI resources are created. Existing services and volumes are never pruned.
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPLOY_DIR="$ROOT/deploy/oracle"
COMPOSE="$DEPLOY_DIR/compose.yaml"
ENVFILE="$DEPLOY_DIR/.env"
PROJECT="helaili-freellmapi"
REQUIRED_FREE_BYTES=$((3 * 1024 * 1024 * 1024))

echo "OCI_FREELLMAPI: checking existing host"
if [ "$(uname -m)" != "aarch64" ]; then
  echo "STOP: this installer targets an ARM64 (aarch64) OCI host" >&2
  exit 20
fi
for cmd in docker sudo openssl curl ss df awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "STOP: missing prerequisite $cmd" >&2
    exit 21
  fi
done
if ! sudo -n docker info >/dev/null 2>&1; then
  echo "STOP: noninteractive privileged Docker access is unavailable" >&2
  exit 22
fi
if ! sudo -n docker compose version >/dev/null 2>&1; then
  echo "STOP: Docker Compose is unavailable" >&2
  exit 23
fi
if [ -n "$(sudo -n docker ps -aq --filter "label=com.docker.compose.project=$PROJECT")" ]; then
  echo "STOP: existing $PROJECT deployment detected. Do not overwrite it automatically." >&2
  exit 24
fi
if ss -H -ltn | awk '{print $4}' | grep -Eq ':3001$'; then
  echo "STOP: TCP port 3001 is in use by another service" >&2
  exit 25
fi
FREE_BYTES="$(df -PB1 / | awk 'NR == 2 {print $4}')"
echo "OCI_FREELLMAPI: free root filesystem bytes = $FREE_BYTES"
if [ "$FREE_BYTES" -lt "$REQUIRED_FREE_BYTES" ]; then
  echo "STOP: need at least 3 GiB free before pulling images; no changes made" >&2
  exit 75
fi
if [ ! -f "$ENVFILE" ]; then
  KEY="$(openssl rand -hex 32)"
  printf 'ENCRYPTION_KEY=%s\nPORT=3001\n' "$KEY" > "$ENVFILE"
  unset KEY
  chmod 600 "$ENVFILE"
  echo "OCI_FREELLMAPI: generated an encryption key locally; value not logged"
else
  if ! grep -Eq '^ENCRYPTION_KEY=[0-9A-Fa-f]{64}$' "$ENVFILE"; then
    echo "STOP: existing env file has no valid ENCRYPTION_KEY; refusing to overwrite" >&2
    exit 26
  fi
  echo "OCI_FREELLMAPI: using existing local encryption key"
fi
echo "OCI_FREELLMAPI: downloading official arm64 image"
sudo -n docker compose -p "$PROJECT" -f "$COMPOSE" pull freellmapi
echo "OCI_FREELLMAPI: starting isolated service (127.0.0.1:3001)"
sudo -n docker compose -p "$PROJECT" -f "$COMPOSE" up -d --no-build freellmapi

READY=0
for attempt in $(seq 1 60); do
  if curl --fail --silent --show-error --max-time 2 http://127.0.0.1:3001/api/ping >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 2
done
if [ "$READY" -ne 1 ]; then
  echo "STOP: container started but HTTP health check failed; inspect Docker logs manually" >&2
  sudo -n docker compose -p "$PROJECT" -f "$COMPOSE" ps || true
  exit 27
fi
sudo -n docker compose -p "$PROJECT" -f "$COMPOSE" ps
echo "OCI_FREELLMAPI_OK: http://127.0.0.1:3001 (server loopback only)"
