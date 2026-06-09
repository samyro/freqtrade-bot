#!/usr/bin/env bash
# =============================================================================
# setup-freqtrade-vps.sh  —  One-time VPS bootstrap for the freqtrade bot.
#
# Assumes you already ran setup-vps.sh from the algo-trader repo (k3s, helm,
# UFW, GHCR pull secret are already on the box). This script ONLY:
#
#   1. Creates the `freqtrade` namespace.
#   2. Copies the GHCR pull secret into it (or creates a fresh one if missing).
#   3. Prompts for + writes the freqtrade-secrets Secret (Kraken keys, API auth).
#   4. Installs a systemd port-forward unit so localhost:8090 reaches the pod.
#
# Run as root on the VPS:
#   bash setup-freqtrade-vps.sh
#
# Re-running is safe — every step is idempotent.
# =============================================================================
set -euo pipefail

NAMESPACE="freqtrade"
SECRET_NAME="freqtrade-secrets"
GHCR_PULL_SECRET="ghcr-pull-secret"
PORT="8090"
SERVICE="freqtrade"  # matches helm chart fullname

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "==> Creating namespace '$NAMESPACE'..."
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 \
  || kubectl create namespace "$NAMESPACE"

# ── GHCR pull secret ───────────────────────────────────────────────────────
echo "==> Ensuring GHCR pull secret '$GHCR_PULL_SECRET' exists in '$NAMESPACE'..."
if kubectl -n "$NAMESPACE" get secret "$GHCR_PULL_SECRET" >/dev/null 2>&1; then
  echo "    Already present."
else
  if kubectl -n algo-trader get secret "$GHCR_PULL_SECRET" >/dev/null 2>&1; then
    echo "    Copying from algo-trader namespace..."
    kubectl -n algo-trader get secret "$GHCR_PULL_SECRET" -o yaml \
      | sed "s/namespace: algo-trader/namespace: $NAMESPACE/" \
      | kubectl apply -f -
  else
    echo "    Not found anywhere. Create it manually:"
    echo "      kubectl -n $NAMESPACE create secret docker-registry $GHCR_PULL_SECRET \\"
    echo "        --docker-server=ghcr.io --docker-username=YOUR_GH_USER \\"
    echo "        --docker-password=YOUR_GHCR_PAT"
    exit 1
  fi
fi

# ── freqtrade-secrets Secret ───────────────────────────────────────────────
echo
echo "==> freqtrade-secrets Secret"
if kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  read -r -p "    Secret '$SECRET_NAME' already exists. Overwrite? [y/N] " yn
  if [[ ! "$yn" =~ ^[Yy]$ ]]; then
    echo "    Keeping existing secret."
    skip_secret=1
  fi
fi

if [[ -z "${skip_secret:-}" ]]; then
  echo "    Paste each value when prompted. Inputs are NOT echoed."
  read -r -s -p "    Kraken API key: " KRAKEN_KEY; echo
  read -r -s -p "    Kraken API secret: " KRAKEN_SECRET; echo
  read -r -p "    WebUI username (e.g. 'freqtrader'): " WEBUI_USER
  read -r -s -p "    WebUI password (>=12 chars, random): " WEBUI_PASS; echo
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

  echo "    Secret '$SECRET_NAME' written. JWT + WS token generated automatically."
  echo "    WebUI login: $WEBUI_USER / <as entered>"
fi

# ── port-forward systemd unit ──────────────────────────────────────────────
echo
echo "==> Installing port-forward systemd unit (localhost:$PORT → svc/$SERVICE)..."
UNIT=/etc/systemd/system/freqtrade-port-forward.service
cat > "$UNIT" <<UNITEOF
[Unit]
Description=kubectl port-forward freqtrade WebUI to localhost:$PORT
After=k3s.service
Wants=k3s.service

[Service]
Type=simple
Environment=KUBECONFIG=/etc/rancher/k3s/k3s.yaml
ExecStart=/usr/local/bin/kubectl port-forward -n $NAMESPACE svc/$SERVICE $PORT:$PORT --address 127.0.0.1
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable freqtrade-port-forward.service
systemctl restart freqtrade-port-forward.service
echo "    Unit installed + started. Status:"
systemctl --no-pager --lines=3 status freqtrade-port-forward.service || true

cat <<DONE

==> Done.

Next steps:
  1. Trigger the GitHub Actions workflow to build + deploy:
       gh workflow run "CI / Deploy" --field strategy=SampleStrategy
  2. Watch the deploy:
       kubectl -n $NAMESPACE get pods -w
  3. From your laptop, open an SSH tunnel and visit the WebUI:
       ssh -L $PORT:localhost:$PORT root@\$VPS
       open http://localhost:$PORT
DONE
