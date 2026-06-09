# Strategies

Drop strategy class files here. Each file is a Python module containing one or
more classes that subclass `freqtrade.strategy.IStrategy`. The deployed image
gets the strategy you specify via `--set strategy=<ClassName>` at helm-upgrade
time (or via the GitHub Actions workflow input).

## Adding a community strategy

1. Browse <https://github.com/freqtrade/freqtrade-strategies/tree/main/user_data/strategies>.
2. Download a single `.py` file (e.g. `BbandRsi.py` from the `berlinguyinca/` folder).
3. Drop it in this directory:
   ```bash
   curl -L -o BbandRsi.py \
     https://raw.githubusercontent.com/freqtrade/freqtrade-strategies/main/user_data/strategies/berlinguyinca/BbandRsi.py
   ```
4. **Backtest it locally first** (never deploy untested code):
   ```bash
   cd ../..   # back to repo root
   docker run --rm -it \
     -v "$(pwd)/user_data:/freqtrade/user_data" \
     freqtradeorg/freqtrade:stable \
     backtesting \
       --strategy BbandRsi \
       --config /freqtrade/user_data/config.json \
       --timerange 20260301-20260601
   ```
5. **Dry-run on the VPS** by redeploying with the new strategy:
   ```bash
   gh workflow run "CI / Deploy" --field strategy=BbandRsi --field dry_run_override=true
   ```
   Watch logs for 3+ days. Verify trade frequency, win rate, and avg PnL look
   like the backtest claimed.
6. **Only then** flip `dry_run` to `false` in `config.json`, commit, and redeploy.

## Quality warning

Most strategies in the community repo are overfit on a specific 6-month
window. Don't put real money on one without:
- Backtesting on at least the last 12 months
- Looking at the drawdown chart (not just total return)
- Computing Sharpe / Sortino (use `freqtrade backtesting --export trades`
  then analyse with the notebook in `ft_userdata/user_data/notebooks/`)
- Dry-running for at least 3 days

## What's in here by default

- `SampleStrategy.py` — freqtrade's canonical reference template. Trades on
  RSI/MACD/Bollinger confluence. No real edge, exists to prove the deployment
  pipeline works.
