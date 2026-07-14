"""
Smart Budget Calculator — Zenvest
Blends 4 financial frameworks into a single personalized budget suggestion.

Frameworks used:
  1. 50/30/20 Rule     — Elizabeth Warren (All Your Worth)
  2. 70/20/10 Rule     — Jim Rohn (7 Strategies for Wealth & Happiness)
  3. Pay Yourself First — David Bach (The Automatic Millionaire)
  4. Zero-Based Budget — Dave Ramsey (Total Money Makeover)

The final suggestion is a weighted average of all four, adjusted by:
  - User age group  (from onboarding)
  - Income bracket  (from onboarding)
  - Risk profile    (from risk assessment)
"""

from app.models.user import User

# ── Income bracket midpoints in INR per month ────────────────────────────────
# These convert the string brackets from onboarding into numeric values.
INCOME_MIDPOINTS: dict[str, float] = {
    "0-5L":   25_000.0,   # ~2.08L/year → 25K/month (midpoint)
    "5-10L":  62_500.0,   # ~7.5L/year  → 62.5K/month
    "10-25L": 145_833.0,  # ~17.5L/year → 1.46L/month
    "25-50L": 312_500.0,  # ~37.5L/year → 3.13L/month
    "50L+":   500_000.0,  # conservative floor for 50L+
}

# ── Age group → savings floor percentage ─────────────────────────────────────
# Based on David Bach's Pay Yourself First principle, adjusted for India.
SAVINGS_FLOOR_BY_AGE: dict[str, float] = {
    "18-25": 0.15,   # Building first habit — 15% floor
    "26-35": 0.20,   # Peak earning growth — 20% floor
    "36-45": 0.25,   # Wealth accumulation phase — 25%
    "46-60": 0.30,   # Pre-retirement — 30% floor
    "60+":   0.30,   # Conservative preservation
}

# ── Risk profile → how aggressive the budget skews toward savings ─────────────
# Conservative savers get a higher savings push, less on wants.
RISK_SAVINGS_MODIFIER: dict[str, float] = {
    "Conservative": 0.05,   # Add 5% more to savings floor
    "Moderate":     0.00,   # No change
    "Aggressive":  -0.02,   # Slightly less savings floor (trust future income growth)
}

# ── Zero-Based envelope proportions (within spendable pool) ───────────────────
# These match Indian urban spending patterns for 25–35 earners.
ENVELOPE_RATIOS: dict[str, float] = {
    "food":          0.22,
    "bills":         0.25,
    "transport":     0.12,
    "shopping":      0.13,
    "entertainment": 0.08,
    "health":        0.08,
    "other":         0.12,
}

# ── Category classification for 50/30/20 ────────────────────────────────────
NEEDS_CATEGORIES  = {"bills", "transport", "health"}
WANTS_CATEGORIES  = {"food", "shopping", "entertainment", "other"}


from typing import Optional

def _get_monthly_income(user: User, real_income: Optional[float] = None) -> float:
    """Extract numeric monthly income from user's income_bracket string or real credit transactions."""
    if real_income is not None and real_income > 0:
        return real_income
    bracket = (user.income_bracket or "0-5L").strip()
    return INCOME_MIDPOINTS.get(bracket, 25_000.0)


def _get_savings_floor_pct(user: User) -> float:
    """Get savings floor % based on age + risk profile."""
    age_group = (user.age_group or "26-35").strip()
    base = SAVINGS_FLOOR_BY_AGE.get(age_group, 0.20)

    # Adjust by risk profile if available
    risk_level = "Moderate"
    if user.risk_profile and isinstance(user.risk_profile, dict):
        risk_level = user.risk_profile.get("level", "Moderate")

    modifier = RISK_SAVINGS_MODIFIER.get(risk_level, 0.0)
    return min(max(base + modifier, 0.10), 0.40)   # Clamp between 10% and 40%


def _framework_50_30_20(income: float, savings_pct: float) -> dict[str, float]:
    """
    50/30/20 Rule — Warren.
    Returns per-category monthly limit.
    Needs = 50%, Wants = 30% (savings handled separately as floor).
    """
    needs_pool  = income * 0.50
    wants_pool  = income * 0.30

    # Distribute needs pool equally across needs categories
    needs_per_cat = needs_pool / len(NEEDS_CATEGORIES)
    # Distribute wants pool equally across wants categories
    wants_per_cat = wants_pool / len(WANTS_CATEGORIES)

    result = {}
    for cat in NEEDS_CATEGORIES:
        result[cat] = needs_per_cat
    for cat in WANTS_CATEGORIES:
        result[cat] = wants_per_cat
    return result


def _framework_70_20_10(income: float) -> dict[str, float]:
    """
    70/20/10 Rule — Jim Rohn.
    70% living expenses distributed across all categories by envelope ratios.
    """
    living_pool = income * 0.70
    return {cat: living_pool * ratio for cat, ratio in ENVELOPE_RATIOS.items()}


def _framework_pay_yourself_first(income: float, savings_pct: float) -> dict[str, float]:
    """
    Pay Yourself First — David Bach.
    Subtract savings floor first, distribute remainder across categories.
    Remaining is split 60% needs / 40% wants.
    """
    spendable = income * (1 - savings_pct)
    needs_pool = spendable * 0.60
    wants_pool = spendable * 0.40

    needs_per_cat = needs_pool / len(NEEDS_CATEGORIES)
    wants_per_cat = wants_pool / len(WANTS_CATEGORIES)

    result = {}
    for cat in NEEDS_CATEGORIES:
        result[cat] = needs_per_cat
    for cat in WANTS_CATEGORIES:
        result[cat] = wants_per_cat
    return result


def _framework_zero_based(income: float, savings_pct: float) -> dict[str, float]:
    """
    Zero-Based Budget — Dave Ramsey.
    Every rupee assigned. Savings taken first, then envelope system.
    """
    spendable = income * (1 - savings_pct)
    return {cat: spendable * ratio for cat, ratio in ENVELOPE_RATIOS.items()}


def calculate_suggested_budgets(user: User, real_income: Optional[float] = None) -> dict[str, float]:
    """
    Main public function. Returns a dict of {category: suggested_monthly_limit}.

    Blends all four frameworks using a weighted average:
      - 50/30/20:          weight 25%
      - 70/20/10:          weight 20%
      - Pay Yourself First: weight 30%  (highest weight — most suited for India)
      - Zero-Based:         weight 25%

    Then normalizes the blended values so their sum exactly equals the spendable income.
    Results are rounded to the nearest ₹100 for UX clarity.
    Minimum floor for any category: ₹500/month (to avoid unrealistic zeroes).
    """
    income       = _get_monthly_income(user, real_income)
    savings_pct  = _get_savings_floor_pct(user)
    spendable    = income * (1 - savings_pct)

    fw1 = _framework_50_30_20(income, savings_pct)
    fw2 = _framework_70_20_10(income)
    fw3 = _framework_pay_yourself_first(income, savings_pct)
    fw4 = _framework_zero_based(income, savings_pct)

    categories = list(ENVELOPE_RATIOS.keys())
    raw_blended: dict[str, float] = {}

    for cat in categories:
        raw_blended[cat] = (
            fw1.get(cat, 0) * 0.25 +
            fw2.get(cat, 0) * 0.20 +
            fw3.get(cat, 0) * 0.30 +
            fw4.get(cat, 0) * 0.25
        )

    # NORMALIZE: scale all categories so they sum to exactly spendable
    raw_total = sum(raw_blended.values())
    if raw_total > 0:
        normalized = {
            cat: (amount / raw_total) * spendable
            for cat, amount in raw_blended.items()
        }
    else:
        normalized = {cat: spendable / len(categories) for cat in categories}

    # Round to nearest ₹100, then fix rounding drift on the largest category
    rounded = {cat: round(amt / 100) * 100 for cat, amt in normalized.items()}
    drift = spendable - sum(rounded.values())
    largest_cat = max(rounded, key=rounded.get)
    rounded[largest_cat] += round(drift / 100) * 100

    # Enforce ₹500 floor per category — if any category is below floor,
    # deduct the difference from the largest category to compensate
    for cat in rounded:
        if rounded[cat] < 500:
            deficit = 500 - rounded[cat]
            rounded[cat] = 500
            rounded[largest_cat] = max(500, rounded[largest_cat] - deficit)

    return rounded


def get_framework_breakdown(user: User, real_income: Optional[float] = None) -> dict:
    """
    Returns all four framework outputs + the blend for UI explanation.
    Used by the 'How was this calculated?' detail sheet in the Flutter app.
    """
    income      = _get_monthly_income(user, real_income)
    savings_pct = _get_savings_floor_pct(user)

    return {
        "monthly_income_used":       income,
        "savings_floor_percentage":  round(savings_pct * 100, 1),
        "age_group":                 user.age_group or "26-35",
        "risk_level":                (user.risk_profile or {}).get("level", "Moderate"),
        "frameworks": {
            "50_30_20_warren":           _framework_50_30_20(income, savings_pct),
            "70_20_10_rohn":             _framework_70_20_10(income),
            "pay_yourself_first_bach":   _framework_pay_yourself_first(income, savings_pct),
            "zero_based_ramsey":         _framework_zero_based(income, savings_pct),
        },
        "blended_suggestion": calculate_suggested_budgets(user, real_income),
    }
