"""Database connection management."""

from typing import Optional

from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import NullPool, QueuePool

from ..core.config import get_database_settings
from ..core.logging import get_logger

logger = get_logger(__name__)

# Global engine instance
_engine: Optional[AsyncEngine] = None
_session_factory: Optional[sessionmaker] = None


async def create_database_pool() -> None:
    """Create database connection pool."""
    global _engine, _session_factory
    
    if _engine is not None:
        logger.warning("Database pool already exists")
        return
    
    settings = get_database_settings()
    
    # Configure connection pool
    pool_class = QueuePool if "sqlite" not in settings.url else NullPool
    
    _engine = create_async_engine(
        settings.url,
        poolclass=pool_class,
        pool_size=settings.pool_size if pool_class == QueuePool else None,
        max_overflow=settings.max_overflow if pool_class == QueuePool else None,
        pool_timeout=settings.pool_timeout if pool_class == QueuePool else None,
        pool_recycle=settings.pool_recycle if pool_class == QueuePool else None,
        echo=settings.echo,
        future=True,
    )
    
    _session_factory = sessionmaker(
        bind=_engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    
    logger.info(
        "Database connection pool created",
        pool_size=settings.pool_size,
        max_overflow=settings.max_overflow,
    )


async def close_database_pool() -> None:
    """Close database connection pool."""
    global _engine, _session_factory
    
    if _engine is not None:
        await _engine.dispose()
        _engine = None
        _session_factory = None
        logger.info("Database connection pool closed")


def get_engine() -> AsyncEngine:
    """Get database engine."""
    if _engine is None:
        raise RuntimeError("Database pool not initialized. Call create_database_pool() first.")
    return _engine


def get_session_factory() -> sessionmaker:
    """Get session factory."""
    if _session_factory is None:
        raise RuntimeError("Database pool not initialized. Call create_database_pool() first.")
    return _session_factory


async def get_session() -> AsyncSession:
    """Get database session."""
    factory = get_session_factory()
    async with factory() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()