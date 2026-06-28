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
