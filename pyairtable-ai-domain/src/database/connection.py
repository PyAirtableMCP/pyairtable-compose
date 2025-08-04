"""Database connection management"""
import asyncio
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase

from ..core.config import get_settings
from ..core.logging import get_logger


class Base(DeclarativeBase):
    """Base class for SQLAlchemy models"""
    pass


# Global database session and engine
_engine = None
_session_factory = None
logger = get_logger(__name__)


async def init_db() -> None:
    """Initialize database connection"""
    global _engine, _session_factory
    
    settings = get_settings()
    
    try:
        # Create async engine
        _engine = create_async_engine(
            settings.database_url,
            echo=settings.debug,
            pool_pre_ping=True,
            pool_recycle=3600,  # 1 hour
            max_overflow=20,
            pool_size=10,
        )
        
        # Create session factory
        _session_factory = async_sessionmaker(
            bind=_engine,
            class_=AsyncSession,
            expire_on_commit=False
        )
        
        # Test connection
        async with _engine.begin() as conn:
            await conn.execute(text("SELECT 1"))
        
        logger.info("Database connection initialized successfully")
        
    except Exception as e:
        logger.error(f"Failed to initialize database: {str(e)}")
        raise


async def close_db() -> None:
    """Close database connection"""
    global _engine
    
    if _engine:
        await _engine.dispose()
        logger.info("Database connection closed")


async def get_db() -> AsyncSession:
    """Get database session"""
    if not _session_factory:
        raise RuntimeError("Database not initialized. Call init_db() first.")
    
    async with _session_factory() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def get_db_session() -> AsyncSession:
    """Get database session for direct use"""
    if not _session_factory:
        raise RuntimeError("Database not initialized. Call init_db() first.")
    
    return _session_factory()


# Import this after engine setup to avoid circular imports
from sqlalchemy import text