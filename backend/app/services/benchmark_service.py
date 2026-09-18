"""
Benchmark index data service.
Real historical index levels (Nifty 50 / Nifty Midcap 150 / Nifty Smallcap
250 / Nifty 500) from Yahoo Finance's public chart endpoint — free, no API
key, used for real Alpha/Beta computation against each fund's category
benchmark. No fabricated data: if a benchmark can't be fetched, Alpha/Beta
for that fund are simply omitted rather than guessed.
"""
import time
from datetime import datetime
from typing import Optional
from urllib.parse import quote

import httpx

YAHOO_CHART_BASE = "https://query1.finance.yahoo.com/v8/finance/chart"
_CACHE_TTL_SECONDS = 6 * 60 * 60
_cache: dict[str, tuple[float, list[tuple[datetime, float]]]] = {}

# Maps our internal category buckets to the closest tracked NSE index.
CATEGORY_BENCHMARKS: dict[str, str] = {
    "large_cap": "^NSEI",           # Nifty 50
    "flexi_cap": "^CRSLDX",         # Nifty 500
    "mid_cap": "^NSEMDCP50",        # Nifty Midcap 50 (closest free-tracked proxy)
    "small_cap": "^CRSLDX",         # Nifty 500 (no free small-cap index ticker on Yahoo)
    "elss": "^CRSLDX",
    "hybrid": "^CRSLDX",
    "debt": None,                   # Debt funds aren't benchmarked against equity indices
}


async def _fetch_index_series(symbol: str) -> Optional[list[tuple[datetime, float]]]:
    cached = _cache.get(symbol)
    if cached and (time.time() - cached[0]) < _CACHE_TTL_SECONDS:
        return cached[1]

    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(
                f"{YAHOO_CHART_BASE}/{quote(symbol)}",
                params={"range": "5y", "interval": "1mo"},
                headers={"User-Agent": "Mozilla/5.0"},
            )
            resp.raise_for_status()
            data = resp.json()
    except (httpx.HTTPError, ValueError):
        return cached[1] if cached else None

    try:
        result = data["chart"]["result"][0]
        timestamps = result["timestamp"]
        closes = result["indicators"]["quote"][0]["close"]
    except (KeyError, IndexError, TypeError):
        return cached[1] if cached else None

    series = [
        (datetime.fromtimestamp(ts), close)
        for ts, close in zip(timestamps, closes)
        if close is not None
    ]
    if not series:
        return cached[1] if cached else None

    _cache[symbol] = (time.time(), series)
    return series


def _monthly_returns(series: list[tuple[datetime, float]]) -> list[float]:
    """Simple month-over-month % returns from a level series."""
    returns = []
    for i in range(1, len(series)):
        prev = series[i - 1][1]
        curr = series[i][1]
        if prev > 0:
            returns.append((curr - prev) / prev)
    return returns


async def get_benchmark_monthly_returns(category_key: str) -> Optional[list[float]]:
    """Monthly return series for the benchmark matching a fund category bucket."""
    symbol = CATEGORY_BENCHMARKS.get(category_key)
    if not symbol:
        return None
    series = await _fetch_index_series(symbol)
    if not series or len(series) < 12:
        return None
    return _monthly_returns(series)
