#!/usr/bin/env bash
# =============================================================================
# create-secret.sh  —  Rotate the freqtrade-secrets Secret without redeploying.
#
# Run as root on the VPS. After this finishes the deployment auto-restarts
# (the checksum/secret annotation on the pod template changes when the Secret
# is replaced via helm upgrade — but for a direct kubectl apply, you need
# to bounce the pod manually; see the final command this script prints).
# =============================================================================
set -euo pipefail

NAMESPACE="freqtrade"
SECRET_NAME="freqtrade-secrets"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "==> Rotating $SECRET_NAME in namespace $NAMESPACE"
read -r -s -p "    Kraken API key: " KRAKEN_KEY; echo
read -r -s -p "    Kraken API secret: " KRAKEN_SECRET; echo
read -r -p "    WebUI username: " WEBUI_USER
read -r -s -p "    WebUI password: " WEBUI_PASS; echo
JWT_KEY=$(openssl rand -hex 32)
WS_TOKEN=$(openssl rand -hex 16)

TMP=$(mktemp)
cat > "$TMP" <<JSON
{
  "exchange": {
    "key": "$KRAKEN_KEY",
    "secret": "$KRAKEN_SECRET"
  },
  "api_server": {
    "username": "$WEBUI_USER",
    "password": "$WEBUI_PASS",
    "jwt_secret_key": "$JWT_KEY",
    "ws_token": "$WS_TOKEN"
  }
}
JSON

kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-file=config.secrets.json="$TMP" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "$TMP"

echo "==> Secret updated. Restarting deployment to pick up new keys..."
kubectl -n "$NAMESPACE" rollout restart deployment/freqtrade
kubectl -n "$NAMESPACE" rollout status deployment/freqtrade --timeout=120s
echo "==> Done."
