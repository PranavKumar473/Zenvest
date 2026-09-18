"""
Universal investment execution.
Every investment made through the platform — regardless of asset type or
entry point (advisor screen, fund directory, top-5 recommendations) — flows
through record_investment(), which:
  1. Creates an InvestmentConfirmation (the staged/confirmed record).
  2. Always registers the transaction under CORPORATE_ARN for fund-house
     execution, never the individual advisor's personal ARN — the investor
     is never asked for or shown this value.
  3. If a human advisor guided the investment, writes an AdvisorCommission
     ledger row (EUIN-attributed) for internal payout accounting — entirely
     separate from the ARN used for fund-house execution.
  4. Auto-creates the resulting Portfolio holding and, when the advisor
     resolves to a platform user, an ArnLinkage for portfolio visibility
     (unrelated to execution routing).
"""
from datetime import date, datetime, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.advisor_commission import AdvisorCommission
from app.models.arn_linkage import ArnLinkage
from app.models.investment_confirmation import InvestmentConfirmation
from app.models.portfolio import Portfolio
from app.models.user import User

settings = get_settings()


async def _resolve_human_advisor(db: AsyncSession, advisor_id: Optional[str], advisor_euin: Optional[str]) -> Optional[User]:
    """Best-effort match to a platform advisor account, by id or by EUIN.
    Human guidance is still recorded (name + EUIN) even if no match is found —
    the advisor need not be a registered platform user."""
    if advisor_id:
        res = await db.execute(
            select(User).where(User.id == advisor_id, User.user_type == "advisor")
        )
        matched = res.scalar_one_or_none()
        if matched:
            return matched
    if advisor_euin:
        res = await db.execute(
            select(User).where(User.euin == advisor_euin, User.user_type == "advisor")
        )
        return res.scalar_one_or_none()
    return None


async def record_investment(
    db: AsyncSession,
    *,
    investor: User,
    asset_type: str,
    scheme_name: str,
    suggested_amount: float,
    actual_amount: float,
    confirmed: bool = True,
    investment_mode: Optional[str] = "sip",
    advisor_source: str = "robo",
    advisor_id: Optional[str] = None,
    advisor_name: Optional[str] = None,
    advisor_euin: Optional[str] = None,
) -> dict:
    resolved_advisor: Optional[User] = None
    if advisor_source == "human":
        resolved_advisor = await _resolve_human_advisor(db, advisor_id, advisor_euin)

    confirmation = InvestmentConfirmation(
        user_id=investor.id,
        asset_type=asset_type,
        scheme_name=scheme_name,
        suggested_amount=suggested_amount,
        actual_amount=actual_amount,
        confirmed=confirmed,
        confirmed_at=datetime.now(timezone.utc) if confirmed else None,
        advisor_source=advisor_source,
        advisor_id=resolved_advisor.id if resolved_advisor else None,
        advisor_name=advisor_name if advisor_source == "human" else None,
        advisor_euin=advisor_euin if advisor_source == "human" else None,
        execution_arn=settings.CORPORATE_ARN,
    )
    db.add(confirmation)

    portfolio_id: Optional[str] = None
    if confirmed and actual_amount > 0:
        holding = Portfolio(
            user_id=investor.id,
            asset_name=scheme_name,
            asset_type=asset_type,
            current_value=actual_amount,
            initial_investment=actual_amount,
            start_date=date.today(),
            advisor_id=resolved_advisor.id if resolved_advisor else None,
            advisor_arn=resolved_advisor.arn_number if resolved_advisor else None,
            investment_mode=investment_mode,
            advisor_source=advisor_source,
            execution_arn=settings.CORPORATE_ARN,
            advisor_euin=advisor_euin if advisor_source == "human" else None,
        )
        db.add(holding)
        await db.flush()  # populate holding.id for the commission ledger row below
        portfolio_id = holding.id

        if advisor_source == "human":
            db.add(AdvisorCommission(
                advisor_id=resolved_advisor.id if resolved_advisor else None,
                investor_id=investor.id,
                investment_confirmation_id=confirmation.id,
                portfolio_id=holding.id,
                advisor_name=advisor_name or (resolved_advisor.advisor_name if resolved_advisor else "Unknown"),
                advisor_euin=advisor_euin,
                scheme_name=scheme_name,
                invested_amount=actual_amount,
            ))

        if resolved_advisor:
            link_res = await db.execute(
                select(ArnLinkage).where(
                    ArnLinkage.investor_id == investor.id,
                    ArnLinkage.advisor_id == resolved_advisor.id,
                    ArnLinkage.is_active == True,
                )
            )
            if not link_res.scalar_one_or_none():
                db.add(ArnLinkage(
                    investor_id=investor.id,
                    advisor_id=resolved_advisor.id,
                    arn_number=resolved_advisor.arn_number or "ARN-00000",
                    is_active=True,
                ))

    await db.commit()

    return {
        "message": "Investment recorded",
        "confirmation_id": confirmation.id,
        "portfolio_id": portfolio_id,
        "advisor_source": advisor_source,
    }
