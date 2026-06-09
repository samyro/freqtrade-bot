# Setup — zero to first deploy

Steps are roughly in the order you'd do them. The whole flow takes about
45 minutes if you've never done it before, 10 minutes once you have.

---

## Step 1 — Create a Kraken API key

See [KRAKEN.md](KRAKEN.md) for screenshots + the exact permission set to grant.
You'll need the API key + secret in step 6.

> **Tip**: create the key with `IP whitelist` set to your VPS IP
> (`72.62.79.28`). Even if the key leaks, only that IP can use it.

---

## Step 2 — Create a new GitHub repo

```bash
cd /Users/lawrence/Documents/Claude/Projects/quant-3rd-lib
git init
git add -A
git commit -m "initial scaffold from claude"

# Create the repo (replace OWNER):
gh repo create OWNER/quant-3rd-lib --private --source=. --remote=origin --push
```

In `helm/freqtrade/values.yaml`, replace `CHANGE-ME-OWNER` with your GitHub
username/org. Commit + push.

---

## Step 3 — Create a GHCR Personal Access Token

The VPS pulls images from GHCR via a `docker-registry` k8s Secret. If you
already did this for algo-trader, you can reuse the same PAT.

1. github.com → Settings → Developer settings → Personal access tokens (classic)
2. New token with scope: `read:packages` only
3. Copy the token — used in Step 5.

---

## Step 4 — Add GitHub Actions secrets/variables

In the new repo's **Settings → Secrets and variables → Actions**:

**Secrets**:
- `VPS_SSH_KEY` — the private SSH key used by the algo-trader workflow (reuse it)

**Variables**:
- `VPS_HOST` → `72.62.79.28`
- `VPS_USER` → `root`

These mirror the algo-trader workflow exactly.

---

## Step 5 — Bootstrap the VPS

SSH to your VPS and run:

```bash
scp scripts/setup-freqtrade-vps.sh root@72.62.79.28:/root/
ssh root@72.62.79.28 "bash /root/setup-freqtrade-vps.sh"
```

The script is interactive. It will:

1. Create the `freqtrade` namespace in k3s
2. Copy the `ghcr-pull-secret` from the algo-trader namespace (or prompt
   you to create one if it doesn't exist)
3. Prompt for Kraken API key, secret, WebUI username + password
4. Auto-generate JWT secret key + WS token
5. Write the `freqtrade-secrets` k8s Secret containing all of the above
6. Install a systemd port-forward unit so `localhost:8090` on the VPS reaches
   the freqtrade WebUI pod (the algo-trader's port-forward on 8919 is untouched)

You'll be prompted for:
- Kraken API key (paste, hidden input)
- Kraken API secret (paste, hidden input)
- WebUI username (e.g. `freqtrader`)
- WebUI password (≥12 chars random, save in your password manager)

---

## Step 6 — Trigger the first deploy

In your local terminal (with `gh` CLI authenticated):

```bash
gh workflow run "CI / Deploy" \
  --field strategy=SampleStrategy \
  --field dry_run_override=true
```

Or from the GitHub web UI: **Actions → CI / Deploy → Run workflow** → leave
defaults (strategy=`SampleStrategy`, dry_run_override=`true`) → Run.

The workflow runs three jobs in sequence (~3 min total):
1. **Lint** — ruff over strategies, jq validates config.json, helm lint
2. **Build** — Docker build + push to `ghcr.io/<owner>/freqtrade-bot:<git-sha>`
3. **Deploy** — `helm upgrade --install freqtrade ...` over SSH

Watch progress in **Actions** tab.

---

## Step 7 — Confirm the pod is up

```bash
ssh root@72.62.79.28 "kubectl -n freqtrade get pods"
```

Expected:
```
NAME                         READY   STATUS    RESTARTS   AGE
freqtrade-7f4cd66b58-xyz12   1/1     Running   0          1m
```

Tail the logs to confirm the bot started in dry-run + connected to Kraken:
```bash
ssh root@72.62.79.28 "kubectl -n freqtrade logs deploy/freqtrade -f"
```

You should see something like:
```
INFO - Using config: /freqtrade/user_data/config.json
INFO - Using config: /freqtrade/user_data/config.secrets.json
INFO - Using exchange kraken
INFO - Strategy SampleStrategy
INFO - Running in dry-run mode. THIS IS NOT REAL TRADING.
INFO - Bot heartbeat
```

If you see `Kraken returned: EAPI:Invalid key`, your API key was wrong —
re-run `scripts/create-secret.sh` to fix.

---

## Step 8 — Access the WebUI

On your laptop:

```bash
ssh -L 8090:localhost:8090 root@72.62.79.28
# Leave that terminal open; in another:
open http://localhost:8090
```

Log in with the username + password you set in Step 5. You'll see freqtrade's
WebUI showing:
- "Simulation" badge (because dry_run=true)
- Open trades (empty initially)
- Wallet balance ($1000 simulated)
- Live ETH/USDT chart

---

## Step 9 — Let it run dry for 3+ days

Don't even *think* about going live until you've watched 3 days of dry-run
behaviour. Check:
- Trade frequency (a 5m strategy should generate maybe 1–5 signals/day)
- Whether trades close at ROI or hit stoploss
- Whether the win rate looks anything like the backtest claimed
- Whether the WS connection to Kraken stays stable (look for reconnect spam
  in the pod logs)

If anything looks off — pod crashes, no signals firing despite price action,
sketchy fills — STOP and investigate before going live.

---

## Step 10 — Going live (when you're ready)

Edit `user_data/config.json`:
```diff
-  "dry_run": true,
+  "dry_run": false,
```

Also confirm `dry_run_wallet` is removed/ignored — live mode uses real wallet
balance from Kraken.

Commit + push, then redeploy:
```bash
git add user_data/config.json
git commit -m "go live"
git push
gh workflow run "CI / Deploy" --field strategy=SampleStrategy --field dry_run_override=false
```

On first live start, the bot will:
1. Query your Kraken wallet balance
2. Cancel any orphan open orders
3. Begin watching for signals on the configured timeframe

Watch the logs carefully for the first hour. The first real fill is when
"Simulation" disappears from the WebUI badge.

---

## Day-to-day operations

```bash
# Check pod status
ssh root@72.62.79.28 "kubectl -n freqtrade get pods"

# Tail logs
ssh root@72.62.79.28 "kubectl -n freqtrade logs deploy/freqtrade -f"

# Restart the bot (picks up new config from the image AND secret rotation)
ssh root@72.62.79.28 "kubectl -n freqtrade rollout restart deployment/freqtrade"

# Rotate Kraken API keys
scp scripts/create-secret.sh root@72.62.79.28:/root/
ssh root@72.62.79.28 "bash /root/create-secret.sh"

# View helm release history (in case you need to roll back)
ssh root@72.62.79.28 "helm history freqtrade -n freqtrade"

# Roll back to a specific git SHA
ssh root@72.62.79.28 "helm upgrade freqtrade /root/helm-freqtrade \
  --namespace freqtrade --set image.tag=<old-sha> --wait"
```

---

## Troubleshooting

**Pod stuck in `ImagePullBackOff`**
GHCR pull secret missing or wrong. Check:
```bash
kubectl -n freqtrade get secret ghcr-pull-secret
```
If missing, re-run `setup-freqtrade-vps.sh`.

**Pod crashing on startup with `Invalid key`**
Kraken API key wrong in the secret. Run `scripts/create-secret.sh` to fix.

**Pod running but no trades**
Open the WebUI → Trades tab. Are signals firing in the logs but rejected by
risk-checks? Or is the strategy genuinely seeing no entry conditions? Check
the `populate_entry_trend` logic against a chart of the last 24h.

**Port-forward systemd unit failing**
```bash
ssh root@72.62.79.28 "systemctl status freqtrade-port-forward"
```
If the unit is failing because the service doesn't exist yet, the first deploy
hasn't completed — wait for it, then `systemctl restart freqtrade-port-forward`.
