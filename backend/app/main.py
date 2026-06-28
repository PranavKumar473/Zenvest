"""
Financial Clarity — FastAPI Application Entry Point.
Configures middleware, registers routers, and manages application lifecycle.
"""

import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI

from app.config import get_settings
from app.database import init_db, close_db
from app.middleware.error_handler import GlobalErrorHandler
from app.middleware.security import SecurityHeadersMiddleware, setup_cors, limiter
from app.routers import auth, users, budgets, transactions, portfolios, account_aggregator
from slowapi.errors import RateLimitExceeded
from slowapi import _rate_limit_exceeded_handler

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(name)s | %(levelname)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("financial_clarity")

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle manager."""
    # Startup
    logger.info("Starting Financial Clarity API v%s", settings.APP_VERSION)
    await init_db()
    logger.info("Database initialized")
    yield
    # Shutdown
    logger.info("Shutting down Financial Clarity API")
    await close_db()


# Create FastAPI application
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description=(
        "Production-grade financial management API with investment advisory, "
        "budget tracking, portfolio analytics, and Account Aggregator integration."
    ),
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# --- Middleware (order matters: outermost first) ---
app.add_middleware(GlobalErrorHandler)
app.add_middleware(SecurityHeadersMiddleware)
setup_cors(app)

# --- Register API Routers ---
API_PREFIX = "/api/v1"

app.include_router(auth.router, prefix=API_PREFIX)
app.include_router(users.router, prefix=API_PREFIX)
app.include_router(budgets.router, prefix=API_PREFIX)
app.include_router(transactions.router, prefix=API_PREFIX)
app.include_router(portfolios.router, prefix=API_PREFIX)
app.include_router(account_aggregator.router, prefix=API_PREFIX)


# --- Health Check ---
@app.get("/health", tags=["System"])
async def health_check():
    """Application health check endpoint."""
    return {
        "status": "healthy",
        "version": settings.APP_VERSION,
        "service": settings.APP_NAME,
    }


@app.get("/", tags=["System"])
async def root():
    """Root endpoint with API information."""
    return {
        "name": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "docs": "/docs",
        "health": "/health",
    }
