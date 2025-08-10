"""Event store implementation for SAGA orchestrator."""

import logging
from abc import ABC, abstractmethod
from datetime import datetime
from typing import List, Optional

from sqlalchemy import create_engine, Column, String, DateTime, Integer, JSON, Boolean, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import IntegrityError

from ..models.events import Event

logger = logging.getLogger(__name__)

Base = declarative_base()


class EventStoreModel(Base):
    """SQLAlchemy model for event store."""
    __tablename__ = 'event_store'
    
    id = Column(String, primary_key=True)
    stream_id = Column(String, index=True, nullable=False)
    version = Column(Integer, nullable=False)
    event_type = Column(String, nullable=False)
    event_data = Column(JSON, nullable=False)
    event_metadata = Column(JSON, default={})
    created_at = Column(DateTime, default=datetime.utcnow)
    correlation_id = Column(String, index=True)


class ConcurrencyError(Exception):
    """Raised when optimistic concurrency check fails."""
    pass


class EventStore(ABC):
    """Abstract base class for event store implementations."""
    
    @abstractmethod
    async def append_events(
        self, 
        stream_id: str, 
        events: List[Event], 
        expected_version: Optional[int] = None
    ) -> None:
        """Append events to stream with optimistic concurrency control."""
        pass
    
    @abstractmethod
    async def read_stream(
        self, 
        stream_id: str, 
        from_version: int = 0,
        to_version: Optional[int] = None
    ) -> List[Event]:
        """Read events from stream."""
        pass
    
    @abstractmethod
    async def read_all_events(
        self, 
        from_position: int = 0,
        max_count: int = 1000
    ) -> List[Event]:
        """Read all events from all streams."""
        pass


class PostgreSQLEventStore(EventStore):
    """PostgreSQL-based event store with optimistic concurrency control."""
    
    def __init__(self, database_url: str):
        self.engine = create_engine(database_url)
        self.SessionLocal = sessionmaker(bind=self.engine)
        self._ensure_tables()
        
    def _ensure_tables(self) -> None:
        """Ensure event store tables exist."""
        try:
            # Run migrations first
            self._run_migrations()
            
            # Then ensure SQLAlchemy tables exist
            Base.metadata.create_all(self.engine)
            logger.info("Event store tables initialized")
        except Exception as e:
            logger.error(f"Failed to initialize event store tables: {e}")
            raise
    
    def _run_migrations(self) -> None:
        """Run database migrations."""
        try:
            import os
            from pathlib import Path
            
            # Get migrations directory
            current_dir = Path(__file__).parent
            migrations_dir = current_dir.parent.parent.parent / "migrations"
            
            if not migrations_dir.exists():
                logger.info("No migrations directory found, skipping migrations")
                return
                
            # Connect to database
            with self.engine.connect() as conn:
                # Get list of migration files
                migration_files = sorted([f for f in os.listdir(migrations_dir) if f.endswith('.sql')])
                
                for migration_file in migration_files:
                    migration_path = migrations_dir / migration_file
                    migration_version = migration_file.replace('.sql', '')
                    
                    # Check if migration was already applied
                    try:
                        result = conn.execute(
                            text("SELECT version FROM schema_migrations WHERE version = :version"),
                            {"version": migration_version}
                        ).fetchone()
                        
                        if result:
                            logger.debug(f"Migration {migration_version} already applied")
                            continue
                            
                    except Exception:
                        # schema_migrations table doesn't exist yet, continue with migration
                        pass
                    
                    # Run migration
                    logger.info(f"Applying migration: {migration_version}")
                    with open(migration_path, 'r') as f:
                        migration_sql = f.read()
                    
                    # Execute migration in a transaction
                    trans = conn.begin()
                    try:
                        conn.execute(text(migration_sql))
                        trans.commit()
                        logger.info(f"Migration {migration_version} applied successfully")
                    except Exception as e:
                        trans.rollback()
                        logger.error(f"Migration {migration_version} failed: {e}")
                        raise
                        
            logger.info("Database migrations completed")
            
        except Exception as e:
            logger.error(f"Failed to run migrations: {e}")
            # Don't raise - allow service to continue without migrations
            pass
        
    async def append_events(
        self, 
        stream_id: str, 
        events: List[Event], 
        expected_version: Optional[int] = None
    ) -> None:
        """Append events to stream with optimistic concurrency control."""
        session = self.SessionLocal()
        try:
            # Get current version
            current_version = session.execute(
                text("SELECT COUNT(*) FROM event_store WHERE stream_id = :stream_id"),
                {"stream_id": stream_id}
            ).scalar() or 0
            
            # Check optimistic concurrency
            if expected_version is not None and current_version != expected_version:
                raise ConcurrencyError(
                    f"Expected version {expected_version}, got {current_version}"
                )
            
            # Append events
            for i, event in enumerate(events):
                event_model = EventStoreModel(
                    id=event.id,
                    stream_id=stream_id,
                    version=current_version + i + 1,
                    event_type=event.type.value,
                    event_data=event.to_dict(),
                    event_metadata=event.metadata,
                    correlation_id=event.correlation_id
                )
                session.add(event_model)
            
            session.commit()
            logger.debug(f"Appended {len(events)} events to stream {stream_id}")
            
        except Exception as e:
            session.rollback()
            logger.error(f"Failed to append events to stream {stream_id}: {e}")
            raise
        finally:
            session.close()
    
    async def read_stream(
        self, 
        stream_id: str, 
        from_version: int = 0,
        to_version: Optional[int] = None
    ) -> List[Event]:
        """Read events from stream."""
        session = self.SessionLocal()
        try:
            query = session.query(EventStoreModel)\
                .filter(EventStoreModel.stream_id == stream_id)\
                .filter(EventStoreModel.version >= from_version)
            
            if to_version:
                query = query.filter(EventStoreModel.version <= to_version)
                
            events = query.order_by(EventStoreModel.version).all()
            
            return [
                Event.from_dict(event.event_data) 
                for event in events
            ]
            
        except Exception as e:
            logger.error(f"Failed to read stream {stream_id}: {e}")
            raise
        finally:
            session.close()
    
    async def read_all_events(
        self, 
        from_position: int = 0,
        max_count: int = 1000
    ) -> List[Event]:
        """Read all events from all streams (for projections)."""
        session = self.SessionLocal()
        try:
            events = session.query(EventStoreModel)\
                .filter(EventStoreModel.id > str(from_position))\
                .order_by(EventStoreModel.created_at)\
                .limit(max_count)\
                .all()
            
            return [
                Event.from_dict(event.event_data) 
                for event in events
            ]
            
        except Exception as e:
            logger.error(f"Failed to read all events: {e}")
            raise
        finally:
            session.close()