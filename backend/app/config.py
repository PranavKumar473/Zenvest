"""
Application configuration.
Uses pydantic-settings for environment variable management with secure defaults.
"""

from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Application
    APP_NAME: str = "Financial Clarity"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False

    # Server
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # Database
    DATABASE_URL: str = "sqlite+aiosqlite:///./financial_clarity.db"

    # JWT Authentication
    JWT_SECRET_KEY: str = "CHANGE-THIS-TO-A-SECURE-RANDOM-STRING-IN-PRODUCTION"
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    JWT_REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Encryption (AES-256)
    ENCRYPTION_KEY: str = "CHANGE-THIS-32-BYTE-KEY-IN-PROD!"  # Must be 32 bytes

    # CORS — allow all localhost ports for local dev
    CORS_ORIGINS: list[str] = [
        "http://localhost",
        "http://localhost:3000",
        "http://localhost:5000",
        "http://localhost:8080",
        "http://localhost:8081",
        "http://127.0.0.1:8080",
        "http://127.0.0.1:3000",
    ]
    CORS_ALLOW_ALL_LOCALHOST: bool = True

    # Rate Limiting
    RATE_LIMIT_PER_MINUTE: int = 60
    AUTH_RATE_LIMIT_PER_MINUTE: int = 10
    SYNC_RATE_LIMIT_PER_MINUTE: int = 30

    # Security & Audit
    AUDIT_LOG_ENABLED: bool = True

    # Account Aggregator (Mock)
    AA_CONSENT_EXPIRY_HOURS: int = 24
    AA_DATA_FETCH_TIMEOUT_SECONDS: int = 30

    # GST Verification (Mock GST Portal API for MVP)
    GST_PORTAL_API_URL: str = ""
    GST_PORTAL_API_KEY: str = ""
    # When either is blank, GstService falls back to MockGstPortalProvider

    # Twilio — masked call bridging & recording
    TWILIO_ACCOUNT_SID: str = ""
    TWILIO_AUTH_TOKEN: str = ""
    TWILIO_MASKING_NUMBER: str = ""  # Twilio number used as the shared masked caller ID
    TWILIO_RECORDING_STATUS_CALLBACK_URL: str = ""
    # When SID/token are blank, TelephonyService falls back to MockTelephonyProvider

    # Razorpay — recurring monthly consultation-fee subscriptions
    RAZORPAY_KEY_ID: str = ""
    RAZORPAY_KEY_SECRET: str = ""
    RAZORPAY_WEBHOOK_SECRET: str = ""
    # When key/secret are blank, BillingService falls back to MockBillingProvider

    # Investment routing — every execution through the platform's "Invest"
    # flow registers under this single corporate ARN (AMFI distributor
    # registration), regardless of which human advisor guided the investor.
    # Never shown to the end customer; individual advisors are attributed
    # via EUIN (Employee Unique Identification Number) for commission
    # accounting only — EUIN, not a second ARN, is the correct AMFI
    # mechanism for individual-level accountability under one corporate ARN.
    CORPORATE_ARN: str = "ARN-000001"
    CORPORATE_ARN_HOLDER_NAME: str = "Financial Clarity Distribution Services"

    # Risk metrics — annualized risk-free rate used in Sharpe/Sortino/Alpha
    # (CAPM) calculations. Not a live feed (no free live G-Sec/T-bill API);
    # a periodically-updated assumption, consistent with how most retail
    # investment platforms source this figure. Update from RBI's published
    # 91-day T-bill cutoff yield.
    RISK_FREE_RATE_ANNUAL: float = 0.068  # ~6.8%, update periodically

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "case_sensitive": True,
    }


@lru_cache()
def get_settings() -> Settings:
    """Cached settings instance."""
    return Settings()
