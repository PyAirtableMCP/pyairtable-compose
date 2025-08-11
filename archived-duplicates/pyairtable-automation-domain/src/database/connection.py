"""Database connection management."""

from typing import Optional

from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import NullPool

from ..core.config import get_settings
from ..core.logging import get_logger

# Global database instances
engine: Optional[AsyncEngine] = None
async_session_factory: Optional[sessionmaker] = None
logger = get_logger(__name__)


async def create_database_pool() -> None:
    """Create database connection pool."""
    global engine, async_session_factory
    
    settings = get_settings()
    
    # Create async engine
    engine = create_async_engine(
        settings.database.url,
        pool_size=settings.database.pool_size,
        max_overflow=settings.database.max_overflow,
        echo=settings.database.echo,
        poolclass=NullPool if settings.is_testing else None,
    )
    
    # Create async session factory
    async_session_factory = sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False
    )
    
    logger.info("Database connection pool created")


async def close_database_pool() -> None:
    """Close database connection pool."""
    global engine, async_session_factory
    
    if engine:
        await engine.dispose()
        engine = None
        async_session_factory = None
        logger.info("Database connection pool closed")


def get_database_engine() -> AsyncEngine:
    """Get database engine."""
    if engine is None:
        raise RuntimeError("Database engine not initialized")
    return engine


def get_session_factory() -> sessionmaker:
    """Get async session factory."""
    if async_session_factory is None:
        raise RuntimeError("Session factory not initialized")
    return async_session_factory


async def get_session() -> AsyncSession:
    """Get database session."""
    session_factory = get_session_factory()
    async with session_factory() as session:
        yield session