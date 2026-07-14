"""
Seed data script.
Populates the database with realistic mock data for development and demos.
"""

import asyncio
import random

from datetime import datetime, date, timedelta, timezone

from app.database import AsyncSessionLocal, init_db
from app.models.user import User
from app.models.budget import Budget
from app.models.transaction import Transaction
from app.models.portfolio import Portfolio
from app.services.auth_service import hash_password
from app.services.risk_engine import calculate_risk_score, get_risk_profile


# Transaction vendors by category
VENDORS = {
    "food": [
        ("Swiggy", 250, 800),
        ("Zomato", 200, 700),
        ("BigBasket", 500, 2500),
        ("Starbucks", 350, 600),
        ("Dominos", 300, 900),
        ("Local Restaurant", 150, 500),
    ],
    "bills": [
        ("Jio Prepaid", 239, 999),
        ("Electricity Bill", 800, 3500),
        ("Netflix", 199, 649),
        ("Amazon Prime", 179, 1499),
        ("Water Bill", 200, 600),
        ("Internet - Airtel", 599, 1499),
    ],
    "shopping": [
        ("Amazon India", 500, 5000),
        ("Flipkart", 300, 8000),
        ("Myntra", 800, 3000),
        ("Decathlon", 1000, 5000),
        ("Nykaa", 400, 2500),
    ],
    "entertainment": [
        ("BookMyShow", 200, 800),
        ("Spotify", 119, 179),
        ("PlayStation Store", 500, 4000),
        ("Kindle", 99, 500),
        ("PVR Cinemas", 250, 600),
    ],
    "transport": [
        ("Ola", 100, 500),
        ("Uber", 120, 600),
        ("Metro Card", 200, 500),
        ("Petrol - HP", 1000, 4000),
        ("Rapido", 50, 200),
    ],
    "health": [
        ("Apollo Pharmacy", 200, 1500),
        ("1mg", 150, 1000),
        ("Gym Membership", 1500, 3000),
        ("Dr. Consultation", 500, 1500),
    ],
}


async def seed():
    """Run the seeder."""
    await init_db()

    async with AsyncSessionLocal() as db:
        # --- 1. Create demo user ---
        demo_answers = [2, 3, 2, 2, 2, 1, 2, 2, 1, 2]
        risk_score = calculate_risk_score(demo_answers)

        user = User(
            name="Pranav Kumar",
            email="pranav@financialclarity.app",
            hashed_password=hash_password("DemoPass@2026"),
            age_group="26-35",
            income_bracket="10-25L",
            onboarding_completed=True,
            goals=["retirement", "home_purchase", "emergency_fund", "wealth_growth"],
            risk_profile={
                "score": risk_score,
                "level": get_risk_profile(risk_score)["level"],
                "answers": demo_answers,
            },
        )
        db.add(user)
        print(f"✅ Created user: {user.email} (risk: {user.risk_profile['level']})")

        # --- 1b. Create advisors ---
        advisors_to_seed = [
            User(
                name="Aarav Mehta",
                email="aarav@financialclarity.app",
                hashed_password=hash_password("DemoPass@2026"),
                user_type="advisor",
                arn_number="ARN-123456",
                arn_verified=True,
                advisor_name="Aarav Mehta",
                onboarding_completed=True,
                gst_number="27AABCU9603R1ZM",
                gst_verified=True,
                pan_number="ABCPD1234E",
                address={"line1": "123 Nariman Point", "city": "Mumbai", "state": "Maharashtra", "pincode": "400021"},
                bio="Certified Financial Planner (CFP) with a passion for helping young professionals build long-term wealth. Specialized in mutual fund selection, asset allocation, and tax harvesting.",
                specializations=["Mutual Funds", "Wealth Growth", "Tax Planning"],
                experience_years=8,
                consultation_fee_monthly=1500.0,
            ),
            User(
                name="Priya Sharma",
                email="priya@financialclarity.app",
                hashed_password=hash_password("DemoPass@2026"),
                user_type="advisor",
                arn_number="ARN-654321",
                arn_verified=True,
                advisor_name="Priya Sharma",
                onboarding_completed=True,
                gst_number=None,
                gst_verified=False,
                pan_number="BCDPF5678G",
                address={"line1": "456 Connaught Place", "city": "Delhi", "state": "Delhi", "pincode": "110001"},
                bio="Retired senior fund manager from a top AMFI house. Helping families navigate retirement planning, debt instruments, and stable dividend portfolios.",
                specializations=["Bonds & Fixed Income", "Retirement Planning", "Estate Planning"],
                experience_years=22,
                consultation_fee_monthly=2500.0,
            ),
            User(
                name="Rohan Das",
                email="rohan@financialclarity.app",
                hashed_password=hash_password("DemoPass@2026"),
                user_type="advisor",
                arn_number="ARN-987654",
                arn_verified=True,
                advisor_name="Rohan Das",
                onboarding_completed=True,
                gst_number="19AABCU9603R1ZR",
                gst_verified=True,
                pan_number="CDEFG9012H",
                address={"line1": "789 Salt Lake Sector V", "city": "Kolkata", "state": "West Bengal", "pincode": "700091"},
                bio="Aggressive growth strategist focused on equity markets, international indexing, and multi-asset dynamic rebalancing. Helping clients maximize returns with measured risk.",
                specializations=["Stocks & Equities", "Goal-Based Planning", "Gold & Alternatives"],
                experience_years=12,
                consultation_fee_monthly=1800.0,
            ),
            User(
                name="Bucket Buffalo",
                email="bucketbuffalo@gmail.com",
                hashed_password=hash_password("DemoPass@2026"),
                user_type="advisor",
                arn_number="ARN-111111",
                arn_verified=True,
                advisor_name="Bucket Buffalo",
                onboarding_completed=True,
                gst_number="27AABCU9603R1ZP",
                gst_verified=True,
                pan_number="ABCDE5555F",
                address={"line1": "55 Main Street", "city": "Bengaluru", "state": "Karnataka", "pincode": "560001"},
                bio="Independent Financial Advisor catering to high-net-worth individuals and corporate employees. Focused on asset protection, SIP configuration, and retirement planning.",
                specializations=["Mutual Funds", "Retirement Planning", "Wealth Growth"],
                experience_years=10,
                consultation_fee_monthly=2000.0,
            )
        ]
        for adv in advisors_to_seed:
            db.add(adv)
        await db.flush()
        print(f"✅ Created {len(advisors_to_seed)} seeded advisors (including bucketbuffalo@gmail.com)")

        # --- 2. Create budgets for current month ---
        month_year = datetime.now().strftime("%Y-%m")
        budget_configs = [
            ("food", 15000),
            ("bills", 8000),
            ("shopping", 10000),
            ("entertainment", 5000),
            ("transport", 6000),
            ("health", 4000),
        ]

        budgets = []
        for category, limit in budget_configs:
            # Simulate some spending (40-95% of budget)
            spent_ratio = random.uniform(0.4, 0.95)
            spent = round(limit * spent_ratio, 2)

            budget = Budget(
                user_id=user.id,
                category=category,
                limit_amount=limit,
                current_spent=spent,
                month_year=month_year,
                alert_70_sent=spent_ratio >= 0.70,
                alert_85_sent=spent_ratio >= 0.85,
            )
            db.add(budget)
            budgets.append(budget)

        await db.flush()
        print(f"✅ Created {len(budgets)} budgets for {month_year}")



        # --- 4. Create portfolio holdings ---
        holdings_data = [
            {
                "asset_name": "HDFC Balanced Advantage Fund",
                "asset_type": "mutual_fund",
                "initial_investment": 200000,
                "current_value": 248000,
                "start_date": date(2024, 6, 15),
            },
            {
                "asset_name": "SBI FD @ 7.1% (2 Year)",
                "asset_type": "fixed_deposit",
                "initial_investment": 500000,
                "current_value": 542600,
                "start_date": date(2024, 12, 1),
            },
            {
                "asset_name": "Infosys Ltd.",
                "asset_type": "stocks",
                "initial_investment": 150000,
                "current_value": 172500,
                "start_date": date(2025, 3, 10),
            },
            {
                "asset_name": "Nippon India Gold BeES",
                "asset_type": "gold",
                "initial_investment": 100000,
                "current_value": 118000,
                "start_date": date(2025, 1, 20),
            },
            {
                "asset_name": "ICICI Prudential Nifty Next 50",
                "asset_type": "mutual_fund",
                "initial_investment": 120000,
                "current_value": 139200,
                "start_date": date(2025, 6, 1),
            },
        ]

        for h_data in holdings_data:
            # Generate 12-month value history
            months = 12
            history = []
            start_val = h_data["initial_investment"]
            end_val = h_data["current_value"]
            step = (end_val - start_val) / months

            for m in range(months):
                month_date = datetime.now() - timedelta(days=(months - m) * 30)
                # Add some randomness to make charts realistic
                val = start_val + step * m + random.uniform(-5000, 5000)
                val = max(val, start_val * 0.85)
                history.append({
                    "date": month_date.strftime("%Y-%m"),
                    "value": round(val, 2),
                })

            # Cash flows for XIRR
            cash_flows = [
                {"date": h_data["start_date"].isoformat(), "amount": -h_data["initial_investment"]}
            ]

            holding = Portfolio(
                user_id=user.id,
                asset_name=h_data["asset_name"],
                asset_type=h_data["asset_type"],
                initial_investment=h_data["initial_investment"],
                current_value=h_data["current_value"],
                start_date=h_data["start_date"],
                value_history=history,
                cash_flows=cash_flows,
            )

            # Calculate metrics
            from app.utils.financial_math import calculate_cagr, calculate_xirr

            holding.calculated_cagr = calculate_cagr(
                h_data["initial_investment"],
                h_data["current_value"],
                h_data["start_date"],
            )
            holding.calculated_xirr = calculate_xirr(
                cash_flows, h_data["current_value"]
            )

            db.add(holding)

        await db.flush()
        print(f"✅ Created {len(holdings_data)} portfolio holdings")

        await db.commit()
        print("\n🎉 Seed data created successfully!")
        print(f"   Login: pranav@financialclarity.app / DemoPass@2026")


if __name__ == "__main__":
    asyncio.run(seed())
