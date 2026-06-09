# Strategy iteration playbook

How to find, test, and deploy community strategies without losing money.

## The discipline

For any new strategy:

```
1. Find it       → grep the community repo
2. Backtest      → 12 months historical, look at Sharpe + max-drawdown
3. Dry-run       → 3-7 days on the VPS, compare to backtest
4. Tiny live     → 1 stake-unit max, 1 week
5. Full live     → only if 3 + 4 looked sane
```

Anyone skipping steps 2-4 ends up funding the community.

## Step 1 — Find a strategy

Sources, in order of trustworthiness:

1. **Freqtrade's own template** (`freqtrade/templates/sample_strategy.py`) —
   well-commented reference; no real edge but a clean starting point.
2. **`freqtrade/freqtrade-strategies` repo, `berlinguyinca/` folder** —
   one of the older contributors; strategies tend to be well-formed.
3. **`berlinguyinca/trading-signal-server` and similar** — older indie projects.
4. **Random Medium articles / YouTube tutorials** — be skeptical; most
   show backtests on cherry-picked windows.

Hard avoid:
- Any strategy claiming >50% annual returns in backtests (almost always overfit)
- Strategies with no published backtest results
- "AI/ML" strategies you don't understand the inputs to (overfit risk × 10)

## Step 2 — Download a strategy file

Example: BbandRsi (a Bollinger + RSI mean-reversion strategy):

```bash
cd /Users/lawrence/Documents/Claude/Projects/quant-3rd-lib
curl -L -o user_data/strategies/BbandRsi.py \
  https://raw.githubusercontent.com/freqtrade/freqtrade-strategies/main/user_data/strategies/berlinguyinca/BbandRsi.py
```

Open the file and check:
- The class name (this is what you pass to `--strategy`)
- The `timeframe` attribute (must match your config or you'll get a mismatch warning)
- The `minimal_roi` and `stoploss` defaults — do they make sense?
- Any external `import` that isn't `talib`/`pandas`/`numpy`/`freqtrade.*`
  (rare imports may need pip-installed via a Dockerfile change)

## Step 3 — Backtest locally

You need ~3 months of historical data first. Download via freqtrade:

```bash
docker run --rm -it \
  -v "$(pwd)/user_data:/freqtrade/user_data" \
  freqtradeorg/freqtrade:stable \
  download-data \
    --exchange kraken \
    --pairs ETH/USDT \
    --timeframes 5m \
    --days 180
```

Then run the backtest:

```bash
docker run --rm -it \
  -v "$(pwd)/user_data:/freqtrade/user_data" \
  freqtradeorg/freqtrade:stable \
  backtesting \
    --strategy BbandRsi \
    --config /freqtrade/user_data/config.json \
    --timerange 20260101-20260601 \
    --export trades
```

The output table will show:
- Total trades
- Win rate
- Total profit (absolute + %)
- Max drawdown
- Avg duration
- Sharpe / Sortino / Calmar

Reject any strategy with:
- Sharpe < 1.0 (anything below this is roughly random)
- Max drawdown > 25% (you won't psychologically survive it live)
- < 30 total trades in 6 months (too few data points to trust)
- Win rate > 80% combined with high churn (this is overfitting)

## Step 4 — Dry-run on the VPS

Once a strategy passes backtest, deploy it in dry-run mode:

```bash
gh workflow run "CI / Deploy" \
  --field strategy=BbandRsi \
  --field dry_run_override=true
```

The deployment is automatic. Wait ~3 minutes, then watch logs:
```bash
ssh root@72.62.79.28 "kubectl -n freqtrade logs deploy/freqtrade -f"
```

What you're checking for over the next 3-7 days:

| Sign | Reaction |
|---|---|
| Trades fire at roughly the backtested frequency | ✓ |
| Win rate ±10% of backtest | ✓ |
| Avg PnL per trade within 50% of backtest | ✓ |
| Pod restarts mid-run | ✗ check liveness probe + WS reconnect |
| No trades at all | ✗ strategy's entry conditions don't fire on current market — wait 24h+ |
| Trade frequency 5×+ backtest | ✗ likely a config mismatch (timeframe? stake?) |

## Step 5 — Tiny live

If dry-run looked sane, flip to live with the smallest stake possible:

```diff
# user_data/config.json
-  "dry_run": true,
+  "dry_run": false,
-  "stake_amount": "unlimited",
+  "stake_amount": 25,
   "max_open_trades": 1,
```

Commit + deploy. Watch every fill for the first 2-3 days. Look at:
- Fill price vs signal price (slippage — should be small on Kraken liquidity)
- Real fees vs backtest assumption (Kraken takes 0.16-0.26%; the backtester
  defaults to 0.05% which understates churn)
- Real WS uptime (if Kraken drops a lot, freqtrade falls back to REST polling)

## Step 6 — Full live

After 1+ week of tiny live with no surprises, bump stake:

```diff
-  "stake_amount": 25,
+  "stake_amount": "unlimited",
```

Commit + deploy. Set yourself a calendar reminder to review performance after
30 days. If real PnL is < 50% of what the backtest predicted, the strategy
was overfit — switch back to dry-run and try another.

## Swapping strategies without redeploying the image

Once strategies are baked into the image, you can switch between any of them
without rebuilding:

```bash
gh workflow run "CI / Deploy" --field strategy=BBRSI_v2 --field dry_run_override=true
```

The workflow will build a fresh image (in case you've changed any code) but
the main effect is `--set strategy=BBRSI_v2` in the helm upgrade. Pod
restarts, picks up the new class name, off it goes.

## When a strategy is bleeding money in live

Don't "give it time to recover." That's the gambler's fallacy.

If the strategy has lost more than your "give-up threshold" (e.g. 15% of
allocated capital), do this:

1. Close all open positions: WebUI → Trades → click each open trade → Close
2. Stop the strategy: `kubectl -n freqtrade scale deploy/freqtrade --replicas=0`
3. Investigate: pull the backtest, compare actual vs predicted trade-by-trade
4. Decide: retune, replace, or abandon
5. Resume only after you understand what went wrong
