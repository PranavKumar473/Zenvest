import pytest
import httpx
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.main import app
from app.models.user import User
from app.services.auth_service import create_access_token
from app.database import AsyncSessionLocal


@pytest.mark.asyncio
async def test_compare_funds_endpoint():
    """
    Test the /api/v1/mutual-funds/compare endpoint.
    Retrieves a user from the DB, generates a JWT, and requests details
    for Mirae Asset Large Cap (118825) and Parag Parikh Flexi Cap (122639).
    """
    # 1. Fetch a user from the database or create one if empty
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(User).limit(1))
        user = result.scalar_one_or_none()
        
        if not user:
            # Fallback/create temporary user if db is empty
            user = User(
                name="Test Investor",
                email="test.investor@example.com",
                hashed_password="somehashedpwd",
                user_type="user",
                onboarding_completed=True,
            )
            session.add(user)
            await session.commit()
            await session.refresh(user)

        user_id = user.id

    # 2. Generate a valid access token
    token = create_access_token(user_id)

    # 3. Call comparison endpoint using ASGI Transport
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        headers = {"Authorization": f"Bearer {token}"}
        response = await ac.get(
            "/api/v1/mutual-funds/compare",
            params={"codes": "118825,122639"},
            headers=headers,
        )

    # 4. Assertions
    assert response.status_code == 200
    data = response.json()
    assert "funds" in data
    funds = data["funds"]
    assert len(funds) >= 2

    # Verify we got the correct funds back
    returned_codes = {f["scheme_code"] for f in funds}
    assert 118825 in returned_codes
    assert 122639 in returned_codes

    # Verify risk metrics, yearly returns and nav chart exist
    for fund in funds:
        assert "name" in fund
        assert "nav" in fund
        assert "returns_3y" in fund
        assert "risk_metrics" in fund
        assert "nav_chart" in fund
        assert "yearly_returns" in fund
        print(f"\nFund {fund['scheme_code']} ({fund['name']}):")
        print(f"  NAV: {fund['nav']}")
        print(f"  3Y Return: {fund['returns_3y']}%")
        print(f"  Sharpe Ratio: {fund['risk_metrics'].get('sharpe_ratio')}")
