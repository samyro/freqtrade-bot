"""Sample strategy bundled with freqtrade — copy + adapt this as a starting point.

This file is a near-verbatim copy of freqtrade's reference template at
freqtrade/templates/sample_strategy.py. It's a minimal MACD + Bollinger + RSI
strategy with no edge of its own — it exists to PROVE the deployment works
end-to-end (image builds, pod runs, WebUI responds, bot connects to Kraken,
dry-run trades execute).

After your first successful dry-run, replace this with a real community
strategy from https://github.com/freqtrade/freqtrade-strategies, or build
your own. See ../../docs/STRATEGIES.md.
"""
# pylint: disable=missing-class-docstring, missing-function-docstring
import numpy as np  # noqa
import pandas as pd  # noqa
from pandas import DataFrame
from datetime import datetime  # noqa
from typing import Optional, Union  # noqa

from freqtrade.strategy import IStrategy
import talib.abstract as ta  # noqa
import freqtrade.vendor.qtpylib.indicators as qtpylib


class SampleStrategy(IStrategy):
    """Strategy class for the freqtrade bot."""

    INTERFACE_VERSION = 3

    # Can this strategy go short?
    can_short: bool = False

    # Minimal ROI table — exit at +1% within 60 min, +2.5% within 30 min,
    # +5% within 20 min, otherwise exit on bearish signal.
    minimal_roi = {
        "60": 0.01,
        "30": 0.025,
        "20": 0.05,
        "0": 0.10,
    }

    # Hard stop-loss at 10% below entry.
    stoploss = -0.10

    # Trailing stop — disabled by default. Enable to lock in profit as it grows.
    trailing_stop = False

    # Optimal timeframe for the strategy (matches config.json).
    timeframe = "5m"

    # Run "populate_indicators" only for new candle (faster backtest).
    process_only_new_candles = True

    # These values can be overridden in the config.
    use_exit_signal = True
    exit_profit_only = False
    ignore_roi_if_entry_signal = False

    # Number of candles the strategy requires before producing valid signals.
    startup_candle_count: int = 30

    # Optional order type mapping.
    order_types = {
        "entry": "limit",
        "exit": "limit",
        "stoploss": "market",
        "stoploss_on_exchange": False,
    }

    order_time_in_force = {
        "entry": "GTC",
        "exit": "GTC",
    }

    plot_config = {
        "main_plot": {
            "tema": {},
            "sar": {"color": "white"},
        },
        "subplots": {
            "MACD": {
                "macd": {"color": "blue"},
                "macdsignal": {"color": "orange"},
            },
            "RSI": {
                "rsi": {"color": "red"},
            },
        },
    }

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        # ── RSI ──────────────────────────────────────────────────────────
        dataframe["rsi"] = ta.RSI(dataframe)

        # ── MACD ─────────────────────────────────────────────────────────
        macd = ta.MACD(dataframe)
        dataframe["macd"] = macd["macd"]
        dataframe["macdsignal"] = macd["macdsignal"]
        dataframe["macdhist"] = macd["macdhist"]

        # ── Bollinger Bands ──────────────────────────────────────────────
        bollinger = qtpylib.bollinger_bands(
            qtpylib.typical_price(dataframe), window=20, stds=2,
        )
        dataframe["bb_lowerband"] = bollinger["lower"]
        dataframe["bb_middleband"] = bollinger["mid"]
        dataframe["bb_upperband"] = bollinger["upper"]
        dataframe["bb_percent"] = (
            (dataframe["close"] - dataframe["bb_lowerband"])
            / (dataframe["bb_upperband"] - dataframe["bb_lowerband"])
        )
        dataframe["bb_width"] = (
            (dataframe["bb_upperband"] - dataframe["bb_lowerband"])
            / dataframe["bb_middleband"]
        )

        # ── TEMA (Triple EMA) ────────────────────────────────────────────
        dataframe["tema"] = ta.TEMA(dataframe, timeperiod=9)

        # ── Parabolic SAR ────────────────────────────────────────────────
        dataframe["sar"] = ta.SAR(dataframe)

        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (
                (qtpylib.crossed_above(dataframe["rsi"], 30))
                & (dataframe["tema"] <= dataframe["bb_middleband"])
                & (dataframe["tema"] > dataframe["tema"].shift(1))
                & (dataframe["volume"] > 0)
            ),
            "enter_long",
        ] = 1
        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (
                (qtpylib.crossed_above(dataframe["rsi"], 70))
                & (dataframe["tema"] > dataframe["bb_middleband"])
                & (dataframe["tema"] < dataframe["tema"].shift(1))
                & (dataframe["volume"] > 0)
            ),
            "exit_long",
        ] = 1
        return dataframe
