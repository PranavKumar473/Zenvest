"""
Risk Appetite Engine.
Maps 10 behavioral assessment answers to a risk profile with recommended asset allocation.
"""


# 10-question behavioral assessment for investment risk profiling
RISK_QUESTIONS = [
    {
        "id": 1,
        "question": "If your investment dropped 20% in a week, what would you do?",
        "options": [
            {"text": "Sell everything immediately", "score": 0},
            {"text": "Sell some to reduce risk", "score": 1},
            {"text": "Hold and wait for recovery", "score": 2},
            {"text": "Buy more at a lower price", "score": 3},
        ],
    },
    {
        "id": 2,
        "question": "How long can you keep your money invested without needing it?",
        "options": [
            {"text": "Less than 1 year", "score": 0},
            {"text": "1 to 3 years", "score": 1},
            {"text": "3 to 7 years", "score": 2},
            {"text": "More than 7 years", "score": 3},
        ],
    },
    {
        "id": 3,
        "question": "What is your primary financial goal?",
        "options": [
            {"text": "Preserving my capital", "score": 0},
            {"text": "Earning steady income with some growth", "score": 1},
            {"text": "Growing my wealth over time", "score": 2},
            {"text": "Maximizing returns, even with high risk", "score": 3},
        ],
    },
    {
        "id": 4,
        "question": "How do you react to financial news about market volatility?",
        "options": [
            {"text": "It makes me very anxious", "score": 0},
            {"text": "I get concerned but stay calm", "score": 1},
            {"text": "I see it as part of the cycle", "score": 2},
            {"text": "I see opportunities to invest", "score": 3},
        ],
    },
    {
        "id": 5,
        "question": "What percentage of your monthly income can you invest?",
        "options": [
            {"text": "Less than 10%", "score": 0},
            {"text": "10% to 20%", "score": 1},
            {"text": "20% to 40%", "score": 2},
            {"text": "More than 40%", "score": 3},
        ],
    },
    {
        "id": 6,
        "question": "How would you describe your investment experience?",
        "options": [
            {"text": "No experience at all", "score": 0},
            {"text": "I've used FDs and savings schemes", "score": 1},
            {"text": "I've invested in mutual funds and bonds", "score": 2},
            {"text": "I actively trade stocks and derivatives", "score": 3},
        ],
    },
    {
        "id": 7,
        "question": "Which scenario appeals to you most for a ₹1,00,000 investment?",
        "options": [
            {"text": "Guaranteed ₹1,06,000 in 1 year", "score": 0},
            {"text": "50% chance of ₹1,12,000 or ₹1,02,000", "score": 1},
            {"text": "50% chance of ₹1,25,000 or ₹95,000", "score": 2},
            {"text": "50% chance of ₹1,50,000 or ₹80,000", "score": 3},
        ],
    },
    {
        "id": 8,
        "question": "How many months of expenses do you have as emergency savings?",
        "options": [
            {"text": "Less than 1 month", "score": 0},
            {"text": "1 to 3 months", "score": 1},
            {"text": "3 to 6 months", "score": 2},
            {"text": "More than 6 months", "score": 3},
        ],
    },
    {
        "id": 9,
        "question": "If a trusted friend recommended a high-risk, high-reward investment, you would:",
        "options": [
            {"text": "Politely decline", "score": 0},
            {"text": "Research and invest a small amount", "score": 1},
            {"text": "Invest a moderate amount after research", "score": 2},
            {"text": "Invest significantly — you trust the opportunity", "score": 3},
        ],
    },
    {
        "id": 10,
        "question": "What best describes your current financial obligations?",
        "options": [
            {"text": "Heavy EMIs and dependent family members", "score": 0},
            {"text": "Moderate EMIs with some dependents", "score": 1},
            {"text": "Minimal obligations, some savings", "score": 2},
            {"text": "No debt, strong savings, no dependents", "score": 3},
        ],
    },
]

# Risk level definitions with asset allocation recommendations
RISK_PROFILES = {
    "conservative": {
        "min_score": 0,
        "max_score": 25,
        "level": "Conservative",
        "description": (
            "You prefer stability and capital preservation over high returns. "
            "Your portfolio prioritizes fixed-income instruments and low-risk assets, "
            "with minimal exposure to market volatility."
        ),
        "allocation": {
            "fixed_deposit": 45,
            "bonds": 25,
            "mutual_fund": 20,
            "stocks": 5,
            "gold": 5,
        },
    },
    "moderate": {
        "min_score": 26,
        "max_score": 50,
        "level": "Moderate",
        "description": (
            "You seek a balanced approach between growth and safety. "
            "Your portfolio blends equity and debt instruments to achieve steady "
            "growth while maintaining a reasonable risk cushion."
        ),
        "allocation": {
            "fixed_deposit": 25,
            "bonds": 20,
            "mutual_fund": 30,
            "stocks": 15,
            "gold": 10,
        },
    },
    "aggressive": {
        "min_score": 51,
        "max_score": 75,
        "level": "Aggressive",
        "description": (
            "You are comfortable with market volatility and prioritize wealth growth. "
            "Your portfolio has significant equity exposure with limited fixed-income "
            "instruments, designed for long-term capital appreciation."
        ),
        "allocation": {
            "fixed_deposit": 10,
            "bonds": 10,
            "mutual_fund": 30,
            "stocks": 40,
            "gold": 10,
        },
    },
    "very_aggressive": {
        "min_score": 76,
        "max_score": 100,
        "level": "Very Aggressive",
        "description": (
            "You pursue maximum returns and are unfazed by significant short-term losses. "
            "Your portfolio is equity-heavy with minimal safety allocation, suited for "
            "experienced investors with a very long time horizon."
        ),
        "allocation": {
            "fixed_deposit": 5,
            "bonds": 5,
            "mutual_fund": 25,
            "stocks": 55,
            "gold": 10,
        },
    },
}

# Asset class explanations for the "Why" tiles
ASSET_EXPLANATIONS = {
    "fixed_deposit": {
        "name": "Fixed Deposits",
        "icon": "shield",
        "why": (
            "Fixed deposits provide guaranteed returns with zero market risk. "
            "They serve as the safety net in your portfolio, offering predictable "
            "income and capital preservation. Current FD rates in India range from "
            "6.5% to 7.5% for 1-3 year tenures."
        ),
    },
    "bonds": {
        "name": "Government & Corporate Bonds",
        "icon": "account_balance",
        "why": (
            "Bonds provide regular coupon payments and are less volatile than stocks. "
            "Government securities (G-Secs) carry sovereign guarantee, while AAA-rated "
            "corporate bonds offer slightly higher yields. They balance income "
            "with moderate capital appreciation."
        ),
    },
    "mutual_fund": {
        "name": "Mutual Funds",
        "icon": "pie_chart",
        "why": (
            "Mutual funds offer professional management and diversification across "
            "hundreds of securities. SIPs (Systematic Investment Plans) enable rupee-cost "
            "averaging, reducing timing risk. Equity mutual funds have historically "
            "delivered 12-15% CAGR over 10+ years in India."
        ),
    },
    "stocks": {
        "name": "Direct Equity (Stocks)",
        "icon": "trending_up",
        "why": (
            "Direct equity offers the highest growth potential for long-term wealth "
            "creation. Historically, Nifty 50 has delivered ~12% CAGR over 20 years. "
            "Stocks provide ownership in companies and benefit from economic growth, "
            "but require careful selection and patience through volatility."
        ),
    },
    "gold": {
        "name": "Gold (Digital/SGBs)",
        "icon": "diamond",
        "why": (
            "Gold acts as a hedge against inflation and currency depreciation. "
            "Sovereign Gold Bonds (SGBs) provide 2.5% annual interest plus "
            "capital gains. Gold tends to move inversely to equity markets, "
            "providing portfolio diversification and stability during crises."
        ),
    },
}


def calculate_risk_score(answers: list[int]) -> int:
    """
    Calculate risk score from 10 assessment answers.
    Each answer is scored 0-3, normalized to 0-100 scale.
    
    Args:
        answers: List of 10 integers (0-3)
    
    Returns:
        Risk score as integer (0-100)
    """
    if len(answers) != 10:
        raise ValueError("Exactly 10 answers are required")

    # Weighted scoring: certain questions matter more
    weights = [1.2, 1.0, 1.0, 0.8, 0.9, 0.8, 1.3, 1.0, 0.8, 1.2]
    
    raw_score = sum(a * w for a, w in zip(answers, weights))
    max_possible = sum(3 * w for w in weights)
    
    # Normalize to 0-100
    normalized = int((raw_score / max_possible) * 100)
    return max(0, min(100, normalized))


def get_risk_profile(score: int) -> dict:
    """
    Map a risk score to a full risk profile with allocation recommendations.
    
    Args:
        score: Risk score (0-100)
    
    Returns:
        Dict with level, description, allocation, and asset explanations
    """
    for key, profile in RISK_PROFILES.items():
        if profile["min_score"] <= score <= profile["max_score"]:
            return {
                "score": score,
                "level": profile["level"],
                "description": profile["description"],
                "recommended_allocation": profile["allocation"],
                "asset_explanations": ASSET_EXPLANATIONS,
            }

    # Fallback (should never reach)
    return get_risk_profile(50)


def get_questions() -> list[dict]:
    """Return the full list of risk assessment questions."""
    return RISK_QUESTIONS


async def get_scheme_suggestions(risk_level: str, allocation: dict, user) -> dict:
    """
    Returns specific scheme recommendations per asset class,
    with exact monthly investment amounts based on savings floor.
    Mutual fund suggestions use real, live-computed data (see
    mutual_fund_service.py) — every other asset class stays as curated
    demo data.
    """
    from app.services.budget_calculator import _get_monthly_income, _get_savings_floor_pct
    from app.services.mutual_fund_service import get_suggestions_for_risk_level
    income = _get_monthly_income(user)
    savings_pct = _get_savings_floor_pct(user)
    monthly_investable = income * savings_pct  # e.g. ₹20,000

    # Schemes database — curated, real Indian schemes with key metrics
    SCHEMES = {
        "fixed_deposit": {
            "Conservative": [
                {
                    "name": "SBI Fixed Deposit",
                    "tenure": "1–3 years",
                    "interest_rate": "6.8% p.a.",
                    "min_amount": 1000,
                    "highlight": "Sovereign-backed safety. Best for 2–3 year goals.",
                    "type": "fd"
                },
                {
                    "name": "HDFC Bank FD",
                    "tenure": "1–2 years",
                    "interest_rate": "7.10% p.a.",
                    "min_amount": 5000,
                    "highlight": "Highest among large private banks for 15-month tenure.",
                    "type": "fd"
                },
            ],
            "Moderate": [
                {
                    "name": "HDFC Bank FD (15 months)",
                    "tenure": "15 months",
                    "interest_rate": "7.25% p.a.",
                    "min_amount": 5000,
                    "highlight": "Sweet spot for moderate investors — better rate, short lock-in.",
                    "type": "fd"
                },
            ],
            "Aggressive": [
                {
                    "name": "Small Finance Bank FD (Jana Bank)",
                    "tenure": "1 year",
                    "interest_rate": "8.25% p.a.",
                    "min_amount": 1000,
                    "highlight": "Higher yield for small portion of FD allocation. DICGC insured.",
                    "type": "fd"
                },
            ],
            "Very Aggressive": [
                {
                    "name": "RBL Bank FD",
                    "tenure": "1 year",
                    "interest_rate": "8.10% p.a.",
                    "min_amount": 1000,
                    "highlight": "Minimal FD allocation. Use for pure safety buffer only.",
                    "type": "fd"
                },
            ],
        },
        "bonds": {
            "Conservative": [
                {
                    "name": "RBI Floating Rate Savings Bond",
                    "tenure": "7 years",
                    "interest_rate": "8.05% p.a. (floating)",
                    "min_amount": 1000,
                    "highlight": "Sovereign guarantee. Interest rate resets every 6 months.",
                    "type": "bond"
                },
                {
                    "name": "HDFC AAA Corporate Bond",
                    "tenure": "3 years",
                    "interest_rate": "7.60% p.a.",
                    "min_amount": 10000,
                    "highlight": "Highest credit rating corporate bond. Quarterly interest payout.",
                    "type": "bond"
                },
            ],
            "Moderate": [
                {
                    "name": "Bharat Bond ETF (April 2032)",
                    "tenure": "Till 2032",
                    "interest_rate": "~7.5% target yield",
                    "min_amount": 1000,
                    "highlight": "PSU bond basket via ETF. Liquid on exchange. AAA-only holdings.",
                    "type": "bond"
                },
            ],
            "Aggressive": [
                {
                    "name": "Bharat Bond ETF (April 2030)",
                    "tenure": "Till 2030",
                    "interest_rate": "~7.4% target yield",
                    "min_amount": 1000,
                    "highlight": "Shorter duration for aggressive investors who want bond allocation.",
                    "type": "bond"
                },
            ],
            "Very Aggressive": [
                {
                    "name": "Bharat Bond ETF (April 2030)",
                    "tenure": "Till 2030",
                    "interest_rate": "~7.4% target yield",
                    "min_amount": 1000,
                    "highlight": "Minimal bond exposure. Treat as pure capital preservation slice.",
                    "type": "bond"
                },
            ],
        },
        "mutual_fund": {
            "Conservative": [
                {
                    "name": "HDFC Short Duration Fund",
                    "category": "Debt - Short Duration",
                    "returns_3yr": "7.2% CAGR",
                    "sharpe_ratio": 1.02,
                    "expense_ratio": "0.38%",
                    "min_sip": 500,
                    "highlight": "Low volatility debt fund. Ideal for 2-3 year horizon.",
                    "type": "mf"
                },
                {
                    "name": "SBI Balanced Advantage Fund",
                    "category": "Hybrid - Dynamic Asset Allocation",
                    "returns_3yr": "13.1% CAGR",
                    "sharpe_ratio": 1.31,
                    "expense_ratio": "0.89%",
                    "min_sip": 500,
                    "highlight": "Dynamically shifts between equity and debt. Capital protection focus.",
                    "type": "mf"
                },
            ],
            "Moderate": [
                {
                    "name": "Mirae Asset Large Cap Fund",
                    "category": "Equity - Large Cap",
                    "returns_3yr": "16.4% CAGR",
                    "sharpe_ratio": 1.48,
                    "expense_ratio": "0.54%",
                    "min_sip": 1000,
                    "highlight": "Top-rated large cap. Consistent alpha over Nifty 100 benchmark.",
                    "type": "mf"
                },
                {
                    "name": "Parag Parikh Flexi Cap Fund",
                    "category": "Equity - Flexi Cap",
                    "returns_3yr": "19.2% CAGR",
                    "sharpe_ratio": 1.62,
                    "expense_ratio": "0.63%",
                    "min_sip": 1000,
                    "highlight": "India + global exposure. Low overlap with other funds. Low beta.",
                    "type": "mf"
                },
            ],
            "Aggressive": [
                {
                    "name": "Quant Small Cap Fund",
                    "category": "Equity - Small Cap",
                    "returns_3yr": "33.1% CAGR",
                    "sharpe_ratio": 1.79,
                    "expense_ratio": "0.62%",
                    "min_sip": 1000,
                    "highlight": "Highest return small cap. High volatility — requires 5+ year horizon.",
                    "type": "mf"
                },
                {
                    "name": "Axis Midcap Fund",
                    "category": "Equity - Mid Cap",
                    "returns_3yr": "21.8% CAGR",
                    "sharpe_ratio": 1.54,
                    "expense_ratio": "0.51%",
                    "min_sip": 500,
                    "highlight": "Consistent mid cap performer. Quality-focused stock selection.",
                    "type": "mf"
                },
            ],
            "Very Aggressive": [
                {
                    "name": "Nippon India Small Cap Fund",
                    "category": "Equity - Small Cap",
                    "returns_3yr": "29.4% CAGR",
                    "sharpe_ratio": 1.72,
                    "expense_ratio": "0.69%",
                    "min_sip": 100,
                    "highlight": "Largest small cap AUM. Diversified across 100+ small cap stocks.",
                    "type": "mf"
                },
                {
                    "name": "HDFC Defence Fund",
                    "category": "Equity - Thematic/Sectoral",
                    "returns_3yr": "41.2% CAGR",
                    "sharpe_ratio": 1.91,
                    "expense_ratio": "0.70%",
                    "min_sip": 100,
                    "highlight": "High conviction India defence sector bet. High risk, high reward.",
                    "type": "mf"
                },
            ],
        },
        "stocks": {
            # Demo data as requested — same for all risk levels
            "_all": [
                {
                    "name": "Reliance Industries Ltd (NSE: RELIANCE)",
                    "sector": "Diversified Conglomerate",
                    "current_price": "₹2,891",
                    "52w_range": "₹2,220 – ₹3,218",
                    "pe_ratio": 27.4,
                    "market_cap": "₹19.6L Cr",
                    "highlight": "India's largest company by market cap. Energy, Retail, Telecom.",
                    "type": "stock",
                    "demo": True
                },
                {
                    "name": "HDFC Bank Ltd (NSE: HDFCBANK)",
                    "sector": "Private Banking",
                    "current_price": "₹1,742",
                    "52w_range": "₹1,363 – ₹1,880",
                    "pe_ratio": 18.6,
                    "market_cap": "₹13.2L Cr",
                    "highlight": "India's largest private bank. Consistently profitable with strong NIM.",
                    "type": "stock",
                    "demo": True
                },
                {
                    "name": "Infosys Ltd (NSE: INFY)",
                    "sector": "IT Services",
                    "current_price": "₹1,623",
                    "52w_range": "₹1,358 – ₹1,953",
                    "pe_ratio": 24.1,
                    "market_cap": "₹6.8L Cr",
                    "highlight": "Top-tier IT exporter. Strong free cash flow. Dollar revenue hedge.",
                    "type": "stock",
                    "demo": True
                },
            ],
        },
        "gold": {
            "_all": [
                {
                    "name": "Sovereign Gold Bond (SGB) 2023–24",
                    "type": "sgb",
                    "interest_rate": "2.5% p.a. + capital gains",
                    "tenure": "8 years (exit after 5)",
                    "min_units": "1 gram",
                    "highlight": "Government-issued. Tax-free capital gains on maturity. Best gold option.",
                },
                {
                    "name": "Nippon India ETF Gold BeES",
                    "type": "etf",
                    "ticker": "GOLDBEES",
                    "expense_ratio": "0.79%",
                    "returns_3yr": "15.2% CAGR",
                    "min_units": "1 unit (~₹590)",
                    "highlight": "Most liquid gold ETF on NSE. Tracks domestic gold prices directly.",
                },
                {
                    "name": "HDFC Gold Fund (FoF)",
                    "type": "mf",
                    "returns_3yr": "14.8% CAGR",
                    "expense_ratio": "0.54%",
                    "min_sip": 500,
                    "highlight": "Gold via mutual fund SIP. No Demat needed. Good for monthly investors.",
                },
            ],
        },
    }

    result = {}
    for asset_type, pct in allocation.items():
        amount_for_asset = monthly_investable * (pct / 100)

        # Get schemes for this risk level
        if asset_type == "mutual_fund":
            schemes = await get_suggestions_for_risk_level(risk_level)
            if not schemes:
                # mfapi.in unreachable — fall back to curated demo data
                # rather than showing an empty mutual funds section.
                schemes = [
                    {**s, "demo": True}
                    for s in SCHEMES.get("mutual_fund", {}).get(risk_level, [])
                ]
        elif asset_type in ["stocks", "gold"]:
            schemes = SCHEMES.get(asset_type, {}).get("_all", [])
        else:
            schemes = SCHEMES.get(asset_type, {}).get(risk_level, [])

        # Split the amount across schemes equally
        per_scheme = amount_for_asset / len(schemes) if schemes else 0
        per_scheme = round(per_scheme / 100) * 100  # round to ₹100

        result[asset_type] = {
            "total_amount": amount_for_asset,
            "schemes": [
                {**s, "suggested_amount": per_scheme}
                for s in schemes
            ]
        }

    return result
