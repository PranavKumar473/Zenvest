"""
Mutual fund data service.
Pulls real fund identity + full daily NAV history from mfapi.in — a free,
public, unauthenticated API that mirrors AMFI's official NAV registry
(the same registrar-linked source Indian MF platforms use). All returns
(1M/3M/6M/1Y/3Y/5Y CAGR, yearly returns, NAV chart series) are computed
directly from that real historical NAV data — nothing here is fabricated.

What's deliberately NOT included: expense ratio, AUM, fund manager,
portfolio holdings/sector breakdown, and star ratings. Those require a
licensed data feed (Value Research, Morningstar, etc.) — mfapi.in doesn't
carry them, and we'd rather omit a field than show a fabricated number.

In-memory TTL cache since daily NAV history for a fund since inception can
be several hundred KB and mfapi.in has no bulk/delta endpoint — refetching
on every request would be slow and needlessly hammer a third-party API.
"""
import time
from datetime import datetime
from typing import Optional

import httpx

MFAPI_BASE = "https://api.mfapi.in/mf"
_CACHE_TTL_SECONDS = 6 * 60 * 60  # 6 hours — NAV updates once/day anyway
_cache: dict[int, tuple[float, dict]] = {}  # scheme_code -> (fetched_at, raw_json)

# Curated real scheme codes (verified against mfapi.in), grouped by the
# same risk-level strings risk_engine.py already uses. Direct-plan growth
# options only, so returns aren't diluted by regular-plan distributor commission.
CURATED_FUNDS: dict[str, list[int]] = {
    "Conservative": [118987, 120608],  # HDFC Corporate Bond Fund, ICICI Pru Short Term Gilt Fund
    "Moderate": [120377, 118968],      # ICICI Pru Balanced Advantage, HDFC Balanced Advantage
    "Aggressive": [118825, 122639, 120503],  # Mirae Asset Large Cap, Parag Parikh Flexi Cap, Axis ELSS Tax Saver
    "Very Aggressive": [125497, 118778],     # SBI Small Cap, Nippon India Small Cap
}


async def _fetch_raw(scheme_code: int) -> Optional[dict]:
    """Fetch (or return cached) raw mfapi.in payload for a scheme code."""
    cached = _cache.get(scheme_code)
    if cached and (time.time() - cached[0]) < _CACHE_TTL_SECONDS:
        return cached[1]

    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(f"{MFAPI_BASE}/{scheme_code}")
            resp.raise_for_status()
            data = resp.json()
    except (httpx.HTTPError, ValueError):
        # Serve stale cache rather than nothing if mfapi.in is briefly down
        return cached[1] if cached else None

    if data.get("status") == "SUCCESS" or data.get("data"):
        _cache[scheme_code] = (time.time(), data)
        return data
    return cached[1] if cached else None


def _parse_nav_series(raw: dict) -> list[tuple[datetime, float]]:
    """mfapi.in returns newest-first as {"date": "DD-MM-YYYY", "nav": "123.4500"}."""
    series = []
    for point in raw.get("data", []):
        try:
            d = datetime.strptime(point["date"], "%d-%m-%Y")
            nav = float(point["nav"])
            series.append((d, nav))
        except (ValueError, KeyError, TypeError):
            continue
    series.sort(key=lambda p: p[0])  # oldest -> newest
    return series


def _nav_on_or_before(series: list[tuple[datetime, float]], target: datetime) -> Optional[float]:
    """Latest NAV at or before `target` (funds don't have NAV every calendar day)."""
    candidate = None
    for d, nav in series:
        if d <= target:
            candidate = nav
        else:
            break
    return candidate


def _pct_return(start: Optional[float], end: Optional[float]) -> Optional[float]:
    if not start or not end or start <= 0:
        return None
    return round(((end - start) / start) * 100, 2)


def _cagr(start: Optional[float], end: Optional[float], years: float) -> Optional[float]:
    if not start or not end or start <= 0 or years <= 0:
        return None
    return round(((end / start) ** (1 / years) - 1) * 100, 2)


def _compute_returns(series: list[tuple[datetime, float]]) -> dict:
    if not series:
        return {}
    latest_date, latest_nav = series[-1]

    def months_ago(n):
        # Approximate month arithmetic is fine here — we're locating the
        # nearest trading-day NAV, not doing calendar-exact accounting.
        year = latest_date.year
        month = latest_date.month - n
        while month <= 0:
            month += 12
            year -= 1
        try:
            return latest_date.replace(year=year, month=month)
        except ValueError:
            return latest_date.replace(year=year, month=month, day=28)

    def years_ago(n):
        try:
            return latest_date.replace(year=latest_date.year - n)
        except ValueError:
            return latest_date.replace(year=latest_date.year - n, day=28)

    nav_1m = _nav_on_or_before(series, months_ago(1))
    nav_3m = _nav_on_or_before(series, months_ago(3))
    nav_6m = _nav_on_or_before(series, months_ago(6))
    nav_1y = _nav_on_or_before(series, years_ago(1))
    nav_3y = _nav_on_or_before(series, years_ago(3))
    nav_5y = _nav_on_or_before(series, years_ago(5))
    inception_nav = series[0][1]
    inception_date = series[0][0]
    years_since_inception = (latest_date - inception_date).days / 365.25

    return {
        "nav": latest_nav,
        "nav_date": latest_date.date().isoformat(),
        "returns_1m": _pct_return(nav_1m, latest_nav),
        "returns_3m": _pct_return(nav_3m, latest_nav),
        "returns_6m": _pct_return(nav_6m, latest_nav),
        "returns_1y": _pct_return(nav_1y, latest_nav) if nav_1y else None,
        "returns_3y": _cagr(nav_3y, latest_nav, 3) if nav_3y else None,
        "returns_5y": _cagr(nav_5y, latest_nav, 5) if nav_5y else None,
        "returns_since_inception": _cagr(inception_nav, latest_nav, years_since_inception)
        if years_since_inception >= 1 else _pct_return(inception_nav, latest_nav),
        "inception_date": inception_date.date().isoformat(),
    }


def _yearly_returns(series: list[tuple[datetime, float]], num_years: int = 5) -> list[dict]:
    """Calendar-year returns for the last `num_years` full/partial years — real, computable
    from NAV history alone, and a much stronger trust signal than a single 3Y CAGR headline."""
    if not series:
        return []
    latest_year = series[-1][0].year
    by_year: dict[int, list[float]] = {}
    for d, nav in series:
        by_year.setdefault(d.year, []).append(nav)

    results = []
    for year in range(latest_year - num_years + 1, latest_year + 1):
        navs = by_year.get(year)
        if not navs:
            continue
        year_start = _nav_on_or_before(series, datetime(year, 1, 1)) or navs[0]
        year_end = navs[-1]
        pct = _pct_return(year_start, year_end)
        if pct is not None:
            results.append({"year": year, "return_pct": pct})
    return results


def _chart_series(series: list[tuple[datetime, float]], years: int = 3, max_points: int = 120) -> list[dict]:
    """Downsampled NAV series for the line chart — full daily history since
    inception can be 5000+ points, which is both slow to transfer and
    pointless to render at mobile screen width."""
    if not series:
        return []
    cutoff = series[-1][0].replace(year=series[-1][0].year - years) if series[-1][0].year - years > 1 else series[0][0]
    windowed = [p for p in series if p[0] >= cutoff] or series
    step = max(1, len(windowed) // max_points)
    sampled = windowed[::step]
    if sampled[-1] != windowed[-1]:
        sampled.append(windowed[-1])
    return [{"date": d.date().isoformat(), "nav": nav} for d, nav in sampled]


async def get_fund_detail(scheme_code: int) -> Optional[dict]:
    raw = await _fetch_raw(scheme_code)
    if not raw:
        return None
    series = _parse_nav_series(raw)
    meta = raw.get("meta", {})
    return {
        "scheme_code": scheme_code,
        "name": meta.get("scheme_name"),
        "fund_house": meta.get("fund_house"),
        "category": meta.get("scheme_category"),
        "scheme_type": meta.get("scheme_type"),
        "isin": meta.get("isin_growth"),
        **_compute_returns(series),
        "yearly_returns": _yearly_returns(series),
        "nav_chart": _chart_series(series),
        "data_source": "mfapi.in (AMFI-linked NAV registry)",
    }


async def get_suggestions_for_risk_level(risk_level: str) -> list[dict]:
    """Lightweight summaries (no full NAV history) for the scheme cards on
    the advisor screen — matches the shape risk_engine.SCHEMES entries used
    to have (name/category/type/etc.) so the existing Flutter card renders
    unchanged, plus real computed return fields."""
    codes = CURATED_FUNDS.get(risk_level, [])
    results = []
    for code in codes:
        raw = await _fetch_raw(code)
        if not raw:
            continue
        series = _parse_nav_series(raw)
        if not series:
            continue
        meta = raw.get("meta", {})
        returns = _compute_returns(series)
        results.append({
            "type": "mf",
            "scheme_code": code,
            "name": meta.get("scheme_name"),
            "fund_house": meta.get("fund_house"),
            "category": meta.get("scheme_category"),
            "nav": returns.get("nav"),
            "returns_1y": returns.get("returns_1y"),
            "returns_3y": returns.get("returns_3y"),
            "returns_5y": returns.get("returns_5y"),
            "highlight": f"{meta.get('fund_house', 'Fund house')} · {meta.get('scheme_category', '')}",
        })
    return results
