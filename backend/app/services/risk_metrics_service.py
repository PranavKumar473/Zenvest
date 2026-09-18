"""
Risk-adjusted performance metrics — Sharpe, Sortino, Alpha, Beta, volatility.
Computed directly from real NAV history (mutual_fund_service) and real
benchmark index history (benchmark_service). No fabricated inputs: any
metric that can't be computed from real data (e.g. Alpha/Beta for a debt
fund, which isn't benchmarked against an equity index) comes back as None
rather than a guessed number.
"""
import statistics
from datetime import datetime
from typing import Optional

from app.config import get_settings
from app.services.benchmark_service import get_benchmark_monthly_returns

settings = get_settings()


def _monthly_returns_from_nav(series: list[tuple[datetime, float]]) -> list[tuple[str, float]]:
    """Month-over-month NAV returns, keyed by 'YYYY-MM' so they can be
    aligned against a benchmark series that may have different exact dates."""
    if len(series) < 2:
        return []

    by_month: dict[str, float] = {}
    for d, nav in series:
        key = f"{d.year:04d}-{d.month:02d}"
        by_month[key] = nav  # last NAV seen in that month

    months = sorted(by_month.keys())
    returns = []
    for i in range(1, len(months)):
        prev = by_month[months[i - 1]]
        curr = by_month[months[i]]
        if prev > 0:
            returns.append((months[i], (curr - prev) / prev))
    return returns


def _volatility_annualized(monthly_returns: list[float]) -> Optional[float]:
    if len(monthly_returns) < 3:
        return None
    monthly_std = statistics.pstdev(monthly_returns)
    return round(monthly_std * (12 ** 0.5) * 100, 2)


def _sharpe_ratio(monthly_returns: list[float]) -> Optional[float]:
    if len(monthly_returns) < 3:
        return None
    mean_monthly = statistics.mean(monthly_returns)
    std_monthly = statistics.pstdev(monthly_returns)
    if std_monthly == 0:
        return None
    annual_return = mean_monthly * 12
    annual_std = std_monthly * (12 ** 0.5)
    return round((annual_return - settings.RISK_FREE_RATE_ANNUAL) / annual_std, 2)


def _sortino_ratio(monthly_returns: list[float]) -> Optional[float]:
    if len(monthly_returns) < 3:
        return None
    mean_monthly = statistics.mean(monthly_returns)
    downside = [r for r in monthly_returns if r < 0]
    if len(downside) < 2:
        return None
    downside_std = statistics.pstdev(downside)
    if downside_std == 0:
        return None
    annual_return = mean_monthly * 12
    annual_downside_std = downside_std * (12 ** 0.5)
    return round((annual_return - settings.RISK_FREE_RATE_ANNUAL) / annual_downside_std, 2)


def _alpha_beta(
    fund_returns_by_month: dict[str, float], benchmark_returns: list[float], benchmark_months: list[str]
) -> tuple[Optional[float], Optional[float]]:
    """CAPM Alpha/Beta via simple linear regression, aligned by calendar month."""
    bench_by_month = dict(zip(benchmark_months, benchmark_returns))
    common_months = sorted(set(fund_returns_by_month) & set(bench_by_month))
    if len(common_months) < 6:
        return None, None

    x = [bench_by_month[m] for m in common_months]  # benchmark returns
    y = [fund_returns_by_month[m] for m in common_months]  # fund returns

    mean_x = statistics.mean(x)
    mean_y = statistics.mean(y)
    covariance = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y)) / len(x)
    variance_x = sum((xi - mean_x) ** 2 for xi in x) / len(x)

    if variance_x == 0:
        return None, None

    beta = covariance / variance_x
    fund_annual_return = mean_y * 12
    bench_annual_return = mean_x * 12
    rf = settings.RISK_FREE_RATE_ANNUAL
    alpha = fund_annual_return - (rf + beta * (bench_annual_return - rf))

    return round(alpha * 100, 2), round(beta, 2)


async def compute_risk_metrics(
    nav_series: list[tuple[datetime, float]], category_key: Optional[str]
) -> dict:
    """
    Returns: {volatility, sharpe_ratio, sortino_ratio, alpha, beta}.
    Any field is None if there isn't enough real data to compute it —
    never a placeholder or estimate.
    """
    monthly = _monthly_returns_from_nav(nav_series)
    monthly_values = [r for _, r in monthly]

    result = {
        "volatility_annualized": _volatility_annualized(monthly_values),
        "sharpe_ratio": _sharpe_ratio(monthly_values),
        "sortino_ratio": _sortino_ratio(monthly_values),
        "alpha": None,
        "beta": None,
        "benchmark_used": None,
    }

    if category_key:
        bench_returns = await get_benchmark_monthly_returns(category_key)
        if bench_returns and len(monthly) >= 6:
            # benchmark_service returns returns without month keys; rebuild
            # aligned month keys the same way it derives them (5y monthly range).
            from app.services.benchmark_service import CATEGORY_BENCHMARKS, _fetch_index_series

            symbol = CATEGORY_BENCHMARKS.get(category_key)
            if symbol:
                bench_series = await _fetch_index_series(symbol)
                if bench_series:
                    bench_by_month_level: dict[str, float] = {}
                    for d, level in bench_series:
                        bench_by_month_level[f"{d.year:04d}-{d.month:02d}"] = level
                    bench_months_sorted = sorted(bench_by_month_level.keys())
                    bench_month_returns = []
                    bench_month_keys = []
                    for i in range(1, len(bench_months_sorted)):
                        prev = bench_by_month_level[bench_months_sorted[i - 1]]
                        curr = bench_by_month_level[bench_months_sorted[i]]
                        if prev > 0:
                            bench_month_returns.append((curr - prev) / prev)
                            bench_month_keys.append(bench_months_sorted[i])

                    fund_by_month = dict(monthly)
                    alpha, beta = _alpha_beta(fund_by_month, bench_month_returns, bench_month_keys)
                    result["alpha"] = alpha
                    result["beta"] = beta
                    if alpha is not None:
                        result["benchmark_used"] = symbol

    return result
