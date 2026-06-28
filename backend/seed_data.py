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
        await db.flush()
        await db.refresh(user)

        print(f"✅ Created user: {user.email} (risk: {user.risk_profile['level']})")

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
