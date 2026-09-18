"""
Universal "Invest" workflow request/response schemas.
"""
from typing import Literal, Optional
from pydantic import BaseModel, Field, model_validator


class InvestmentGuidance(BaseModel):
    """Answers the 'Who guided your investment?' modal."""
    source: Literal["robo", "human"] = "robo"
    advisor_name: Optional[str] = Field(None, max_length=200)
    advisor_euin: Optional[str] = Field(None, max_length=20)
    advisor_id: Optional[str] = Field(
        None, description="Platform advisor user id, if the investor picked one from a list"
    )

    @model_validator(mode="after")
    def require_human_details(self):
        if self.source == "human" and not (self.advisor_name and self.advisor_euin):
            raise ValueError(
                "advisor_name and advisor_euin are required when guidance source is 'human'"
            )
        return self


class InvestRequest(BaseModel):
    asset_type: str = Field(..., examples=["mutual_fund"])
    scheme_name: str = Field(..., max_length=200)
    scheme_code: Optional[int] = Field(None, description="mfapi.in scheme code, if applicable")
    suggested_amount: float = Field(0, ge=0)
    actual_amount: float = Field(..., gt=0)
    investment_mode: Optional[str] = "sip"
    guidance: InvestmentGuidance = InvestmentGuidance()


class InvestResponse(BaseModel):
    message: str
    confirmation_id: str
    portfolio_id: Optional[str] = None
    advisor_source: str
