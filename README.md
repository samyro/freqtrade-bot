# quant-3rd-lib

Deployment scaffolding for running **[freqtrade](https://github.com/freqtrade/freqtrade)**
on the same k3s VPS that hosts the algo-trader project. Same CI/CD pattern,
different namespace + image + port.

This repo does NOT fork freqtrade — it builds a thin Docker overlay on top of
`freqtradeorg/freqtrade:stable` that adds:
- Our `config.json` (Kraken, ETH/USDT, 5m, dry-run by default)
- Strategy files from `user_data/strategies/`
- Helm chart + GitHub Actions CI/CD identical in shape to `algo-trader/`

## Quick links

- [`docs/SETUP.md`](docs/SETUP.md) — zero → first deploy, step by step
- [`docs/KRAKEN.md`](docs/KRAKEN.md) — Kraken API key creation + safety settings
- [`docs/STRATEGIES.md`](docs/STRATEGIES.md) — how to find, test, and roll new community strategies
- [`user_data/strategies/`](user_data/strategies/) — your strategy files live here

## Repo layout

```
.
├── Dockerfile                  # FROM freqtradeorg/freqtrade:stable + overlay
├── helm/freqtrade/             # k3s deployment chart (same shape as algo-trader)
├── .github/workflows/deploy.yml  # manual CI: lint → build → push GHCR → helm upgrade
├── scripts/
│   ├── setup-freqtrade-vps.sh  # one-time VPS bootstrap (run as root on VPS)
│   └── create-secret.sh        # rotate Kraken API keys without rebuilding image
├── user_data/
│   ├── config.json             # main freqtrade config (committed, no secrets)
│   ├── config.secrets.example.json   # template for the k8s Secret
│   └── strategies/
│       └── SampleStrategy.py   # starter strategy
├── docs/                       # setup + Kraken + strategy iteration docs
└── ft_userdata/                # freqtrade quickstart output (local backtest sandbox; gitignored)
```

## Hard safety rules baked into this repo

1. **`dry_run: true` by default** in `config.json`. The bot will not place real
   orders until you explicitly flip this to `false`, commit, and redeploy.
2. **Secrets never in git.** API keys live in `config.secrets.json`, mounted
   from a k8s Secret created interactively by `setup-freqtrade-vps.sh`. The
   example file in this repo has placeholder values only.
3. **Manual deploys only.** The GitHub Actions workflow is `workflow_dispatch`
   (no auto-deploy on push). Flipping a strategy in production is a deliberate act.
4. **Recreate-not-RollingUpdate** deployment strategy. Only one pod can hold the
   sqlite RWO lock, so we replace, never overlap.

## Sibling project

The `algo-trader/` project (your OKX-SWAP custom bot) lives in the
`quant-lab/algo-trader/` directory and uses:
- Namespace: `algo-trader`
- WebUI port: `8919`
- Image: `ghcr.io/<owner>/algo-trader`

This freqtrade deploy uses:
- Namespace: `freqtrade`
- WebUI port: `8090`
- Image: `ghcr.io/<owner>/freqtrade-bot`

The two coexist on the same VPS, same k3s cluster, no port or namespace conflicts.
