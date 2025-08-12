"""
Database Connection Pool Configuration for PyAirtable
Created: 2025-08-11
Purpose: Optimized connection pooling for authentication and user data operations
"""

import os
from typing import Optional
from sqlalchemy import create_engine, pool
from sqlalchemy.engine import Engine
from sqlalchemy.orm import sessionmaker, Session
import asyncpg
from asyncpg import Pool
import asyncio
import logging

logger = logging.getLogger(__name__)

# =============================================================================
# CONNECTION POOL CONFIGURATION
# =============================================================================

class DatabaseConfig:
    """Database connection configuration with optimization for auth workloads"""
    
    # Connection pool settings
    POOL_SIZE = int(os.getenv('DB_POOL_SIZE', '20'))  # Base connection pool size
    MAX_OVERFLOW = int(os.getenv('DB_MAX_OVERFLOW', '30'))  # Additional connections under load
    POOL_TIMEOUT = int(os.getenv('DB_POOL_TIMEOUT', '30'))  # Timeout waiting for connection
    POOL_RECYCLE = int(os.getenv('DB_POOL_RECYCLE', '3600'))  # Recycle connections every hour
    POOL_PRE_PING = True  # Validate connections before use
    
    # Connection string optimization
    CONNECT_ARGS = {
        'connect_timeout': 10,  # Connection timeout in seconds
        'command_timeout': 30,  # Command timeout in seconds
        'server_settings': {
            'jit': 'off',  # Disable JIT for faster connection startup
            'application_name': 'pyairtable_auth_service'
        }
    }
    
    # AsyncPG specific settings
    ASYNCPG_MIN_SIZE = int(os.getenv('ASYNCPG_MIN_SIZE', '10'))
    ASYNCPG_MAX_SIZE = int(os.getenv('ASYNCPG_MAX_SIZE', '20'))
    ASYNCPG_MAX_QUERIES = int(os.getenv('ASYNCPG_MAX_QUERIES', '50000'))
    ASYNCPG_MAX_INACTIVE_TIME = int(os.getenv('ASYNCPG_MAX_INACTIVE_TIME', '300'))

# =============================================================================
# SYNCHRONOUS CONNECTION POOL (SQLAlchemy)
# =============================================================================

class SyncConnectionPool:
    """Optimized synchronous connection pool for authentication operations"""
    
    def __init__(self, database_url: str):
        self.database_url = database_url
        self._engine: Optional[Engine] = None
        self._session_factory: Optional[sessionmaker] = None
        
    def get_engine(self) -> Engine:
        """Get optimized SQLAlchemy engine with connection pooling"""
        if self._engine is None:
            self._engine = create_engine(
                self.database_url,
                
                # Connection pool configuration
                poolclass=pool.QueuePool,
                pool_size=DatabaseConfig.POOL_SIZE,
                max_overflow=DatabaseConfig.MAX_OVERFLOW,
                pool_timeout=DatabaseConfig.POOL_TIMEOUT,
                pool_recycle=DatabaseConfig.POOL_RECYCLE,
                pool_pre_ping=DatabaseConfig.POOL_PRE_PING,
                
                # Connection optimization
                connect_args=DatabaseConfig.CONNECT_ARGS,
                
                # Performance settings
                echo=False,  # Disable SQL logging in production
                echo_pool=False,
                future=True,  # Use SQLAlchemy 2.0 style
                
                # Query optimization
                execution_options={
                    'autocommit': False,
                    'isolation_level': 'READ_COMMITTED'
                }
            )
            
            logger.info(f"Created SQLAlchemy engine with pool_size={DatabaseConfig.POOL_SIZE}, "
                       f"max_overflow={DatabaseConfig.MAX_OVERFLOW}")
                       
        return self._engine
    
    def get_session_factory(self) -> sessionmaker:
        """Get optimized session factory"""
        if self._session_factory is None:
            self._session_factory = sessionmaker(
                bind=self.get_engine(),
                autoflush=False,  # Manual flushing for better control
                autocommit=False,
                expire_on_commit=False  # Keep objects accessible after commit
            )
        return self._session_factory
    
    def get_session(self) -> Session:
        """Get database session from pool"""
        return self.get_session_factory()()
    
    def health_check(self) -> dict:
        """Check connection pool health"""
        engine = self.get_engine()
        pool_status = engine.pool.status()
        
        return {
            'pool_size': engine.pool.size(),
            'checked_in': engine.pool.checkedin(),
            'checked_out': engine.pool.checkedout(),
            'overflow': engine.pool.overflow(),
            'invalid': engine.pool.invalidated(),
            'status': pool_status
        }
    
    def close(self):
        """Close connection pool"""
        if self._engine:
            self._engine.dispose()
            self._engine = None
            self._session_factory = None

# =============================================================================
# ASYNCHRONOUS CONNECTION POOL (AsyncPG)
# =============================================================================

class AsyncConnectionPool:
    """Optimized asynchronous connection pool for high-performance operations"""
    
    def __init__(self, database_url: str):
        self.database_url = database_url
        self._pool: Optional[Pool] = None
        self._lock = asyncio.Lock()
    
    async def get_pool(self) -> Pool:
        """Get or create asyncpg connection pool"""
        if self._pool is None:
            async with self._lock:
                if self._pool is None:
                    # Parse database URL for asyncpg
                    import urllib.parse
                    parsed = urllib.parse.urlparse(self.database_url)
                    
                    self._pool = await asyncpg.create_pool(
                        host=parsed.hostname,
                        port=parsed.port or 5432,
                        user=parsed.username,
                        password=parsed.password,
                        database=parsed.path[1:] if parsed.path else None,
                        
                        # Pool configuration
                        min_size=DatabaseConfig.ASYNCPG_MIN_SIZE,
                        max_size=DatabaseConfig.ASYNCPG_MAX_SIZE,
                        max_queries=DatabaseConfig.ASYNCPG_MAX_QUERIES,
                        max_inactive_connection_lifetime=DatabaseConfig.ASYNCPG_MAX_INACTIVE_TIME,
                        
                        # Connection optimization
                        command_timeout=30,
                        server_settings={
                            'application_name': 'pyairtable_async_auth',
                            'jit': 'off',
                            'timezone': 'UTC'
                        }
                    )
                    
                    logger.info(f"Created AsyncPG pool with min_size={DatabaseConfig.ASYNCPG_MIN_SIZE}, "
                               f"max_size={DatabaseConfig.ASYNCPG_MAX_SIZE}")
        
        return self._pool
    
    async def execute_query(self, query: str, *args, fetch_one: bool = False, fetch_all: bool = False):
        """Execute optimized database query"""
        pool = await self.get_pool()
        
        async with pool.acquire() as connection:
            if fetch_one:
                return await connection.fetchrow(query, *args)
            elif fetch_all:
                return await connection.fetch(query, *args)
            else:
                return await connection.execute(query, *args)
    
    async def execute_transaction(self, queries: list):
        """Execute multiple queries in a transaction"""
        pool = await self.get_pool()
        
        async with pool.acquire() as connection:
            async with connection.transaction():
                results = []
                for query_data in queries:
                    if isinstance(query_data, tuple):
                        query, args = query_data[0], query_data[1:]
                    else:
                        query, args = query_data, ()
                    
                    result = await connection.execute(query, *args)
                    results.append(result)
                
                return results
    
    async def health_check(self) -> dict:
        """Check async pool health"""
        if self._pool is None:
            return {'status': 'not_initialized'}
        
        return {
            'min_size': self._pool.get_min_size(),
            'max_size': self._pool.get_max_size(),
            'current_size': self._pool.get_size(),
            'idle_connections': self._pool.get_idle_size(),
            'status': 'healthy' if not self._pool.is_closed() else 'closed'
        }
    
    async def close(self):
        """Close connection pool"""
        if self._pool and not self._pool.is_closed():
            await self._pool.close()
            self._pool = None

# =============================================================================
# CONNECTION POOL MANAGER
# =============================================================================

class ConnectionManager:
    """Manages both sync and async connection pools"""
    
    def __init__(self, database_url: str):
        self.database_url = database_url
        self.sync_pool = SyncConnectionPool(database_url)
        self.async_pool = AsyncConnectionPool(database_url)
    
    def get_sync_session(self) -> Session:
        """Get synchronous database session"""
        return self.sync_pool.get_session()
    
    async def get_async_pool(self) -> Pool:
        """Get asynchronous connection pool"""
        return await self.async_pool.get_pool()
    
    async def health_check(self) -> dict:
        """Comprehensive health check for both pools"""
        sync_health = self.sync_pool.health_check()
        async_health = await self.async_pool.health_check()
        
        return {
            'sync_pool': sync_health,
            'async_pool': async_health,
            'database_url': self.database_url.split('@')[0] + '@***'  # Hide credentials
        }
    
    async def close_all(self):
        """Close all connection pools"""
        self.sync_pool.close()
        await self.async_pool.close()

# =============================================================================
# CONTEXT MANAGERS FOR OPTIMIZED DATABASE ACCESS
# =============================================================================

class DatabaseSession:
    """Context manager for database sessions with automatic cleanup"""
    
    def __init__(self, connection_manager: ConnectionManager):
        self.connection_manager = connection_manager
        self.session: Optional[Session] = None
    
    def __enter__(self) -> Session:
        self.session = self.connection_manager.get_sync_session()
        return self.session
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            if exc_type is not None:
                self.session.rollback()
            else:
                self.session.commit()
            self.session.close()

class AsyncDatabaseConnection:
    """Context manager for async database connections"""
    
    def __init__(self, connection_manager: ConnectionManager):
        self.connection_manager = connection_manager
        self.connection = None
    
    async def __aenter__(self):
        pool = await self.connection_manager.get_async_pool()
        self.connection = await pool.acquire()
        return self.connection
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.connection:
            await self.connection_manager.async_pool._pool.release(self.connection)

# =============================================================================
# PERFORMANCE MONITORING
# =============================================================================

class PerformanceMonitor:
    """Monitor database connection pool performance"""
    
    @staticmethod
    async def log_pool_metrics(connection_manager: ConnectionManager):
        """Log connection pool metrics"""
        health = await connection_manager.health_check()
        
        logger.info("Database Pool Metrics:")
        logger.info(f"  Sync Pool - Size: {health['sync_pool']['pool_size']}, "
                   f"Checked out: {health['sync_pool']['checked_out']}, "
                   f"Overflow: {health['sync_pool']['overflow']}")
        
        if health['async_pool']['status'] == 'healthy':
            logger.info(f"  Async Pool - Current: {health['async_pool']['current_size']}, "
                       f"Idle: {health['async_pool']['idle_connections']}, "
                       f"Max: {health['async_pool']['max_size']}")
    
    @staticmethod
    def get_pool_recommendations(health_data: dict) -> list:
        """Get recommendations for pool optimization"""
        recommendations = []
        
        sync_pool = health_data.get('sync_pool', {})
        overflow = sync_pool.get('overflow', 0)
        checked_out = sync_pool.get('checked_out', 0)
        pool_size = sync_pool.get('pool_size', 0)
        
        if overflow > pool_size * 0.5:
            recommendations.append("Consider increasing DB_POOL_SIZE - high overflow usage")
        
        if checked_out > pool_size * 0.8:
            recommendations.append("Pool utilization high - monitor for connection exhaustion")
        
        async_pool = health_data.get('async_pool', {})
        current_size = async_pool.get('current_size', 0)
        max_size = async_pool.get('max_size', 0)
        
        if current_size >= max_size * 0.9:
            recommendations.append("Async pool near capacity - consider increasing ASYNCPG_MAX_SIZE")
        
        return recommendations

# =============================================================================
# FACTORY FUNCTION
# =============================================================================

def create_connection_manager() -> ConnectionManager:
    """Create optimized connection manager from environment"""
    database_url = os.getenv('DATABASE_URL')
    if not database_url:
        raise ValueError("DATABASE_URL environment variable is required")
    
    return ConnectionManager(database_url)