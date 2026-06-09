# Kraken API setup

Step-by-step for creating an API key that freqtrade can use safely.

## 1. Account prerequisites

- Account in good standing (verified, no pending KYC issues)
- 2FA enabled (Google Authenticator preferred over SMS)
- Funded wallet — for live trading, you need spot USDT (or whatever
  `stake_currency` you set in `config.json`)

## 2. Create the API key

1. Log in to <https://www.kraken.com>
2. Top right → **Settings** → **API**
3. Click **Add Key**
4. Set these permissions (and **only** these):

| Permission | Enable? | Why |
|---|---|---|
| Query Funds | ✅ | Read wallet balance |
| Query Open Orders & Trades | ✅ | See current state |
| Query Closed Orders & Trades | ✅ | History for analytics |
| Query Ledger Entries | ✅ | Required for some freqtrade fee accounting |
| Create & Modify Orders | ✅ | Place trades |
| Cancel/Close Orders | ✅ | Required to clean up unfilled limit orders |
| Deposit Funds | ❌ | NOT needed; leave OFF |
| Withdraw Funds | ❌ | **NEVER enable** — a leaked key with withdraw permission empties your account |
| Query Earn Strategies | ❌ | Not needed |
| Edit Earn Allocations | ❌ | Not needed |
| Allocate Funds to Earn | ❌ | Not needed |

5. Under **Key Permissions Restrictions**:
   - **Expiration**: set to ~6 months from now. Force rotation reminder.
   - **IP Address Restrictions**: enter your VPS IP (`72.62.79.28`). This is
     the single most important safety setting — even if the key leaks, it
     only works from your VPS.
   - **Order Types**: leave all enabled
   - **Asset class restrictions**: optional (e.g., spot only)

6. Click **Generate Key**.
7. Copy the **API Key** and **Private Key (Secret)** immediately — Kraken
   only shows the secret once. Paste them into your password manager.

## 3. Test the key locally before putting it on the VPS

This catches typos and permission mistakes before they cost you a failed
deploy:

```bash
cd ft_userdata    # the local freqtrade scratch directory
cat > config.test.json <<EOF
{
  "exchange": {
    "name": "kraken",
    "key": "YOUR_API_KEY",
    "secret": "YOUR_SECRET"
  }
}
EOF

docker run --rm -it \
  -v "$(pwd):/freqtrade/user_data" \
  freqtradeorg/freqtrade:stable \
  test-pairlist \
  -c /freqtrade/user_data/config.test.json \
  --quote USDT

# Then delete the test config
shred -u config.test.json
```

If you see a list of pairs, the key works.

If you see `EAPI:Invalid key` — the key/secret pair is wrong (typo or
copy/paste error). Regenerate.

If you see `EAPI:Permission denied` — you missed one of the required
permissions above. Edit the key in Kraken settings, don't regenerate.

## 4. Add the key to the VPS

```bash
ssh root@72.62.79.28 "bash /root/setup-freqtrade-vps.sh"
# (or scripts/create-secret.sh if the secret already exists)
```

The script prompts for the key + secret with hidden input. Paste them.

## 5. Kraken-specific quirks freqtrade handles for you

- **Pair format**: Kraken uses `XBT` instead of `BTC` internally; freqtrade
  + CCXT translate `BTC/USDT` → `XBT/USDT` automatically.
- **Minimum order sizes**: Kraken enforces per-pair minimums (e.g. 0.0001 BTC,
  0.002 ETH). If your `stake_amount` is too small to meet the minimum,
  freqtrade refuses to place the order. Default unlimited stake with $1000+
  wallet is well above the minimums.
- **Maker vs taker fees**: Kraken's spot Pro fees start at 0.16%/0.26%
  (maker/taker) and decrease with 30-day volume. Freqtrade reports both
  legs' fees in the round-trip P&L. If your strategy churns, fees matter a lot.
- **API rate limits**: Kraken has tier-based rate limits (Starter / Intermediate /
  Pro). Freqtrade auto-throttles via CCXT. If you see `EAPI:Rate limit` in
  logs, your strategy is hammering the API — bump throttle or reduce
  `process_throttle_secs` in config.

## 6. Rotation hygiene

- **Every 6 months**: generate a fresh key, run `create-secret.sh`, delete
  the old one in Kraken settings.
- **Immediately**: rotate if you suspect your VPS was compromised, your
  laptop disk was lost, or the key was ever copy-pasted anywhere insecure.
