"""
Database engine, session, and base model configuration.
Supports SQLite (development) and PostgreSQL (production).
"""

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase
from app.config import get_settings

settings = get_settings()

# Create async engine with connection pooling
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    future=True,
    # Pool settings (applicable for PostgreSQL; SQLite uses NullPool by default)
    pool_pre_ping=True,
)

# Async session factory
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


class Base(DeclarativeBase):
    """Base class for all ORM models."""
    pass


async def get_db() -> AsyncSession:
    """
    Dependency that provides a database session.
    Automatically closes the session when the request completes.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def _relax_arn_linkages_not_null(conn) -> None:
    """
    SQLite can't ALTER COLUMN to drop a NOT NULL constraint in place.
    arn_linkages.arn_number predates INA support as NOT NULL — rebuild the
    table (SQLite's standard 12-step recipe) only if that's still the case,
    so INA-only linkages (arn_number IS NULL) can be inserted.
    """
    from sqlalchemy import text

    result = await conn.execute(text("PRAGMA table_info(arn_linkages)"))
    columns = result.fetchall()
    if not columns:
        return  # table doesn't exist yet — create_all will define it correctly

    arn_number_col = next((c for c in columns if c[1] == "arn_number"), None)
    if arn_number_col is None or arn_number_col[3] == 0:
        return  # already nullable (notnull flag == 0)

    await conn.execute(text("""
        CREATE TABLE arn_linkages_new (
            id VARCHAR(36) PRIMARY KEY,
            investor_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            advisor_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            linkage_type VARCHAR(10) NOT NULL DEFAULT 'ARN',
            arn_number VARCHAR(20),
            ina_number VARCHAR(30),
            linked_at DATETIME NOT NULL,
            is_active BOOLEAN NOT NULL
        )
    """))
    await conn.execute(text("""
        INSERT INTO arn_linkages_new
            (id, investor_id, advisor_id, linkage_type, arn_number, ina_number, linked_at, is_active)
        SELECT id, investor_id, advisor_id, 'ARN', arn_number, NULL, linked_at, is_active
        FROM arn_linkages
    """))
    await conn.execute(text("DROP TABLE arn_linkages"))
    await conn.execute(text("ALTER TABLE arn_linkages_new RENAME TO arn_linkages"))
    await conn.execute(text(
        "CREATE INDEX IF NOT EXISTS ix_arn_linkages_investor_id ON arn_linkages(investor_id)"
    ))
    await conn.execute(text(
        "CREATE INDEX IF NOT EXISTS ix_arn_linkages_advisor_id ON arn_linkages(advisor_id)"
    ))


async def init_db():
    """Create all tables. Used for development/testing."""
    from sqlalchemy import text
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

        if settings.DATABASE_URL.startswith("sqlite"):
            await _relax_arn_linkages_not_null(conn)

        # Best-effort additive column migrations for SQLite/PostgreSQL dev DBs.
        column_migrations = [
            ("users", "phone_number", "VARCHAR(20)"),
            ("users", "gst_verification_status", "VARCHAR(20) DEFAULT 'unverified'"),
            ("users", "gst_legal_name", "VARCHAR(200)"),
            ("arn_linkages", "linkage_type", "VARCHAR(10) DEFAULT 'ARN'"),
            ("arn_linkages", "ina_number", "VARCHAR(30)"),
            ("call_sessions", "provider", "VARCHAR(20) DEFAULT 'mock'"),
            ("call_sessions", "provider_call_sid", "VARCHAR(64)"),
        ]
        for table, column, coltype in column_migrations:
            try:
                await conn.execute(text(f"SELECT {column} FROM {table} LIMIT 1"))
            except Exception:
                try:
                    await conn.execute(
                        text(f"ALTER TABLE {table} ADD COLUMN {column} {coltype}")
                    )
                except Exception:
                    pass


async def close_db():
    """Dispose of the engine connection pool."""
    await engine.dispose()
