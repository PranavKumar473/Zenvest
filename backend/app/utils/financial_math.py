"""
Financial mathematics utilities.
Implements XIRR (Newton-Raphson) and CAGR calculations for portfolio analytics.
"""

from datetime import date, datetime
from typing import Optional


def calculate_cagr(
    initial_value: float,
    final_value: float,
    start_date: date,
    end_date: Optional[date] = None,
) -> Optional[float]:
    """
    Calculate Compound Annual Growth Rate (CAGR).
    
    CAGR = (Final Value / Initial Value)^(1/years) - 1
    
    Returns the CAGR as a percentage (e.g., 12.5 for 12.5%).
    Returns None if calculation is not possible.
    """
    if end_date is None:
        end_date = date.today()

    if initial_value <= 0 or final_value <= 0:
        return None

    days = (end_date - start_date).days
    if days <= 0:
        return None

    years = days / 365.25

    try:
        cagr = (final_value / initial_value) ** (1 / years) - 1
        return round(cagr * 100, 2)
    except (ZeroDivisionError, OverflowError, ValueError):
        return None


def calculate_xirr(
    cash_flows: list[dict],
    current_value: float,
    current_date: Optional[date] = None,
    max_iterations: int = 200,
    tolerance: float = 1e-7,
) -> Optional[float]:
    """
    Calculate Extended Internal Rate of Return (XIRR) using Newton-Raphson method.
    
    cash_flows: List of dicts with "date" (ISO string or date) and "amount" (negative for investments)
    current_value: Current portfolio value (positive, treated as final cash flow)
    current_date: Date for current value; defaults to today
    
    Returns XIRR as a percentage (e.g., 15.3 for 15.3%).
    Returns None if calculation fails to converge.
    """
    if not cash_flows or current_value <= 0:
        return None

    if current_date is None:
        current_date = date.today()

    # Parse and prepare cash flows
    flows: list[tuple[date, float]] = []
    for cf in cash_flows:
        cf_date = cf["date"]
        if isinstance(cf_date, str):
            cf_date = datetime.fromisoformat(cf_date).date()
        flows.append((cf_date, float(cf["amount"])))

    # Add current value as final positive cash flow
    flows.append((current_date, current_value))

    if len(flows) < 2:
        return None

    # Sort by date
    flows.sort(key=lambda x: x[0])
    base_date = flows[0][0]

    def npv(rate: float) -> float:
        """Net present value at given rate."""
        result = 0.0
        for d, amount in flows:
            years = (d - base_date).days / 365.25
            result += amount / ((1 + rate) ** years)
        return result

    def npv_derivative(rate: float) -> float:
        """Derivative of NPV with respect to rate."""
        result = 0.0
        for d, amount in flows:
            years = (d - base_date).days / 365.25
            if years == 0:
                continue
            result -= years * amount / ((1 + rate) ** (years + 1))
        return result

    # Newton-Raphson iteration
    rate = 0.1  # Initial guess of 10%

    for _ in range(max_iterations):
        f_val = npv(rate)
        f_deriv = npv_derivative(rate)

        if abs(f_deriv) < 1e-12:
            # Derivative too small, try a different starting point
            rate += 0.05
            continue

        new_rate = rate - f_val / f_deriv

        # Guard against extreme values
        if new_rate < -0.99:
            new_rate = -0.99
        elif new_rate > 10.0:
            new_rate = 10.0

        if abs(new_rate - rate) < tolerance:
            return round(new_rate * 100, 2)

        rate = new_rate

    return None  # Failed to converge


def calculate_simple_return(
    initial_value: float, current_value: float
) -> float:
    """
    Calculate simple return percentage.
    Returns percentage (e.g., 25.0 for 25%).
    """
    if initial_value <= 0:
        return 0.0
    return round(((current_value - initial_value) / initial_value) * 100, 2)
