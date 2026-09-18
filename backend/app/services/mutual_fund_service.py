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

# Curated real scheme codes (verified against mfapi.in). This is a hand-
# maintained catalog, NOT the full ~37,600-scheme mfapi.in universe — that
# API has no category filter and no bulk categorized endpoint, so listing
# literally every scheme would mean one HTTP call per scheme just to learn
# its category. This catalog is the pragmatic, honest middle ground: real
# funds, real data, organized into a real category taxonomy, sized to grow
# by adding entries rather than by an infeasible full-universe crawl.
#
# Each entry: scheme_code, display category, category_key (drives both the
# directory grouping AND the benchmark used for Alpha/Beta), risk_level
# (backward-compat with risk_engine.py's allocation-driven suggestions).
FundCatalogEntry = dict  # {code, category, category_key, risk_level}

# Every (code, name, house) pair below was individually verified against
# the live mfapi.in detail endpoint before being added here — a scheme code
# typo would silently attach real return data to the WRONG fund name, which
# is exactly the kind of error this catalog exists to prevent.
FUND_CATALOG: list[FundCatalogEntry] = [
    # Equity — Large Cap
    {"code": 118825, "category": "Equity — Large Cap", "category_key": "large_cap", "risk_level": "Moderate"},  # Mirae Asset Large Cap Fund
    {"code": 118834, "category": "Equity — Large & Mid Cap", "category_key": "large_cap", "risk_level": "Moderate"},  # Mirae Asset Large & Midcap Fund
    # Equity — Flexi Cap
    {"code": 122639, "category": "Equity — Flexi Cap", "category_key": "flexi_cap", "risk_level": "Aggressive"},  # Parag Parikh Flexi Cap Fund
    {"code": 118955, "category": "Equity — Flexi Cap", "category_key": "flexi_cap", "risk_level": "Aggressive"},  # HDFC Flexi Cap Fund
    {"code": 112090, "category": "Equity — Flexi Cap", "category_key": "flexi_cap", "risk_level": "Aggressive"},  # Kotak Flexicap Fund
    # Equity — ELSS (Tax Saving)
    {"code": 120503, "category": "Equity — ELSS", "category_key": "elss", "risk_level": "Aggressive"},  # Axis ELSS Tax Saver Fund
    {"code": 120847, "category": "Equity — ELSS", "category_key": "elss", "risk_level": "Aggressive"},  # quant ELSS Tax Saver Fund
    # Equity — Mid Cap
    {"code": 125307, "category": "Equity — Mid Cap", "category_key": "mid_cap", "risk_level": "Aggressive"},  # PGIM India Midcap Fund
    # Equity — Small Cap
    {"code": 125497, "category": "Equity — Small Cap", "category_key": "small_cap", "risk_level": "Very Aggressive"},  # SBI Small Cap Fund
    {"code": 118778, "category": "Equity — Small Cap", "category_key": "small_cap", "risk_level": "Very Aggressive"},  # Nippon India Small Cap Fund
    # Hybrid — Balanced Advantage
    {"code": 120377, "category": "Hybrid — Balanced Advantage", "category_key": "hybrid", "risk_level": "Conservative"},  # ICICI Pru Balanced Advantage Fund
    {"code": 118968, "category": "Hybrid — Balanced Advantage", "category_key": "hybrid", "risk_level": "Conservative"},  # HDFC Balanced Advantage Fund
    # Debt — Corporate Bond
    {"code": 118987, "category": "Debt — Corporate Bond", "category_key": "debt", "risk_level": "Conservative"},  # HDFC Corporate Bond Fund
    # Debt — Gilt
    {"code": 120608, "category": "Debt — Gilt", "category_key": "debt", "risk_level": "Conservative"},  # ICICI Pru Short Term Gilt Fund
]

# Legacy shape kept for any caller still using the old risk-level-keyed
# lookup (risk_engine.get_scheme_suggestions).
CURATED_FUNDS: dict[str, list[int]] = {}
for _entry in FUND_CATALOG:
    CURATED_FUNDS.setdefault(_entry["risk_level"], [])
    if _entry["code"] not in CURATED_FUNDS[_entry["risk_level"]]:
        CURATED_FUNDS[_entry["risk_level"]].append(_entry["code"])

CATALOG_BY_CODE: dict[int, FundCatalogEntry] = {e["code"]: e for e in FUND_CATALOG}


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
    nav_10y = _nav_on_or_before(series, years_ago(10))
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
        "returns_10y": _cagr(nav_10y, latest_nav, 10) if nav_10y else None,
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
    catalog_entry = CATALOG_BY_CODE.get(scheme_code)

    from app.services.risk_metrics_service import compute_risk_metrics
    risk_metrics = await compute_risk_metrics(
        series, catalog_entry["category_key"] if catalog_entry else None
    )

    return {
        "scheme_code": scheme_code,
        "name": meta.get("scheme_name"),
        "fund_house": meta.get("fund_house"),
        "category": meta.get("scheme_category"),
        "scheme_type": meta.get("scheme_type"),
        "isin": meta.get("isin_growth"),
        **_compute_returns(series),
        "yearly_returns": _yearly_returns(series, num_years=10),
        "nav_chart": _chart_series(series),
        "risk_metrics": risk_metrics,
        # Deliberately omitted (no free/licensed source): AUM, expense_ratio,
        # sector/asset allocation breakdown, fund manager. The frontend shows
        # an explicit "not available" state for these rather than a fabricated
        # number — see FundDetailScreen's data-source disclosure banner.
        "unavailable_fields": ["aum", "expense_ratio", "sector_allocation", "fund_manager"],
        "data_source": "mfapi.in (AMFI-linked NAV registry) + NSE index data (risk metrics benchmark)",
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


async def get_fund_directory() -> list[dict]:
    """
    Categorized directory tree for browsing the catalog — Equity (Large/Mid/
    Small/Flexi/ELSS) -> Hybrid -> Debt, per fund_house.py's real category
    taxonomy. Lightweight: fetches meta+latest NAV per fund (cached), not
    full history, since a browse list doesn't need the NAV chart.
    """
    import asyncio

    async def _summary(entry: FundCatalogEntry) -> Optional[dict]:
        raw = await _fetch_raw(entry["code"])
        if not raw:
            return None
        series = _parse_nav_series(raw)
        if not series:
            return None
        meta = raw.get("meta", {})
        returns = _compute_returns(series)
        return {
            "scheme_code": entry["code"],
            "name": meta.get("scheme_name"),
            "fund_house": meta.get("fund_house"),
            "nav": returns.get("nav"),
            "returns_1y": returns.get("returns_1y"),
            "returns_3y": returns.get("returns_3y"),
        }

    summaries = await asyncio.gather(*[_summary(e) for e in FUND_CATALOG])

    by_category: dict[str, list[dict]] = {}
    for entry, summary in zip(FUND_CATALOG, summaries):
        if summary is None:
            continue
        by_category.setdefault(entry["category"], []).append(summary)

    # Stable, investor-familiar ordering: equity risk ladder, then hybrid, then debt.
    category_order = [
        "Equity — Large Cap", "Equity — Large & Mid Cap", "Equity — Flexi Cap",
        "Equity — ELSS", "Equity — Mid Cap", "Equity — Small Cap",
        "Hybrid — Balanced Advantage",
        "Debt — Corporate Bond", "Debt — Gilt",
    ]
    return [
        {"category": cat, "funds": by_category[cat]}
        for cat in category_order
        if cat in by_category
    ]


def _percentile_rank(value: float, all_values: list[float]) -> float:
    """0-100 rank of `value` within `all_values` (higher value = higher rank)."""
    if len(all_values) <= 1:
        return 50.0
    below_or_equal = sum(1 for v in all_values if v <= value)
    return (below_or_equal - 1) / (len(all_values) - 1) * 100


async def get_top5_recommendations(risk_level: Optional[str] = None) -> list[dict]:
    """
    Ranks the catalog (optionally filtered to a risk level) by a composite
    percentile score across real, computed metrics only: 3Y return (falls
    back to 1Y for younger funds), Sharpe ratio, Sortino ratio, and Alpha —
    each fund scored on whichever of these it actually has data for, with
    weight redistributed proportionally rather than penalizing funds for a
    metric that genuinely doesn't apply (e.g. Alpha for a debt fund).
    Expense Ratio is intentionally excluded — no real data source for it.
    """
    import asyncio

    candidates = [e for e in FUND_CATALOG if not risk_level or e["risk_level"] == risk_level]
    if not candidates:
        candidates = FUND_CATALOG

    async def _scored(entry: FundCatalogEntry) -> Optional[dict]:
        detail = await get_fund_detail(entry["code"])
        if not detail:
            return None
        rm = detail.get("risk_metrics") or {}
        primary_return = detail.get("returns_3y") if detail.get("returns_3y") is not None else detail.get("returns_1y")
        return {
            "detail": detail,
            "entry": entry,
            "metrics": {
                "return": primary_return,
                "sharpe": rm.get("sharpe_ratio"),
                "sortino": rm.get("sortino_ratio"),
                "alpha": rm.get("alpha"),
            },
        }

    scored = [s for s in await asyncio.gather(*[_scored(e) for e in candidates]) if s is not None]
    if not scored:
        return []

    weights = {"return": 35, "sharpe": 25, "sortino": 20, "alpha": 20}
    pools = {
        k: [s["metrics"][k] for s in scored if s["metrics"][k] is not None]
        for k in weights
    }

    for s in scored:
        total_weight = 0.0
        weighted_sum = 0.0
        for k, w in weights.items():
            v = s["metrics"][k]
            if v is None or len(pools[k]) <= 1:
                continue
            weighted_sum += _percentile_rank(v, pools[k]) * w
            total_weight += w
        s["composite_score"] = round(weighted_sum / total_weight, 1) if total_weight > 0 else 0.0

    scored.sort(key=lambda s: s["composite_score"], reverse=True)
    top5 = scored[:5]

    return [
        {
            "scheme_code": s["entry"]["code"],
            "name": s["detail"]["name"],
            "fund_house": s["detail"]["fund_house"],
            "category": s["entry"]["category"],
            "composite_score": s["composite_score"],
            "returns_1y": s["detail"].get("returns_1y"),
            "returns_3y": s["detail"].get("returns_3y"),
            "sharpe_ratio": s["metrics"]["sharpe"],
            "sortino_ratio": s["metrics"]["sortino"],
            "alpha": s["metrics"]["alpha"],
            "beta": (s["detail"].get("risk_metrics") or {}).get("beta"),
            "ranking_basis": "Percentile-ranked composite of real 3Y/1Y return, Sharpe, Sortino, "
                             "and Alpha (where computable). Expense Ratio and AUM are not included "
                             "in scoring — no free/licensed data source for them.",
        }
        for s in top5
    ]
