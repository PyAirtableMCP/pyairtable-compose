"""PostgreSQL repository for SAGA persistence."""

import json
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional

import asyncpg
from asyncpg import Pool

from ..models.sagas import SagaInstance, SagaStatus, SagaStep

logger = logging.getLogger(__name__)


class PostgresSagaRepository:
    """PostgreSQL-based repository for SAGA persistence."""
    
    def __init__(self, connection_pool: Pool):
        self.pool = connection_pool
    
    async def save_saga_instance(self, saga: SagaInstance) -> None:
        """Save or update a SAGA instance in PostgreSQL."""
        try:
            async with self.pool.acquire() as conn:
                # Serialize steps to JSON
                steps_data = []
                for step in saga.steps:
                    step_data = {
                        "id": step.id,
                        "name": step.name,
                        "service": step.service,
                        "status": step.status,
                        "command": step.command,
                        "compensation_command": step.compensation_command,
                        "started_at": step.started_at.isoformat() if step.started_at else None,
                        "completed_at": step.completed_at.isoformat() if step.completed_at else None,
                        "error_message": step.error_message,
                        "result": step.result
                    }
                    steps_data.append(step_data)
                
                # Check if saga exists
                existing = await conn.fetchrow(
                    "SELECT id FROM saga_instances WHERE id = $1",
                    saga.id
                )
                
                if existing:
                    # Update existing saga
                    await conn.execute("""
                        UPDATE saga_instances SET
                            saga_type = $2,
                            status = $3,
                            current_step = $4,
                            total_steps = $5,
                            input_data = $6,
                            output_data = $7,
                            error_message = $8,
                            correlation_id = $9,
                            tenant_id = $10,
                            completed_at = $11,
                            steps_data = $12,
                            metadata = $13
                        WHERE id = $1
                    """,
                        saga.id,
                        saga.type,
                        saga.status.value if hasattr(saga.status, 'value') else str(saga.status),
                        saga.current_step,
                        len(saga.steps),
                        json.dumps(saga.input_data),
                        json.dumps(saga.output_data),
                        saga.error_message,
                        saga.correlation_id,
                        saga.tenant_id,
                        saga.completed_at,
                        json.dumps(steps_data),
                        json.dumps(getattr(saga, 'metadata', {}))
                    )
                    
                    logger.debug(f"Updated SAGA instance {saga.id} in PostgreSQL")
                else:
                    # Insert new saga
                    await conn.execute("""
                        INSERT INTO saga_instances (
                            id, saga_type, status, current_step, total_steps,
                            input_data, output_data, error_message, correlation_id,
                            tenant_id, started_at, completed_at, steps_data, metadata
                        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
                    """,
                        saga.id,
                        saga.type,
                        saga.status.value if hasattr(saga.status, 'value') else str(saga.status),
                        saga.current_step,
                        len(saga.steps),
                        json.dumps(saga.input_data),
                        json.dumps(saga.output_data),
                        saga.error_message,
                        saga.correlation_id,
                        saga.tenant_id,
                        saga.started_at,
                        saga.completed_at,
                        json.dumps(steps_data),
                        json.dumps(getattr(saga, 'metadata', {}))
                    )
                    
                    logger.debug(f"Inserted new SAGA instance {saga.id} into PostgreSQL")
                
        except Exception as e:
            logger.error(f"Failed to save SAGA instance {saga.id}: {e}")
            raise
    
    async def get_saga_instance(self, saga_id: str) -> Optional[SagaInstance]:
        """Get a SAGA instance by ID from PostgreSQL."""
        try:
            async with self.pool.acquire() as conn:
                row = await conn.fetchrow("""
                    SELECT id, saga_type, status, current_step, total_steps,
                           input_data, output_data, error_message, correlation_id,
                           tenant_id, started_at, completed_at, steps_data, metadata
                    FROM saga_instances WHERE id = $1
                """, saga_id)
                
                if not row:
                    return None
                
                # Deserialize steps data
                steps = []
                steps_data = json.loads(row['steps_data']) if row['steps_data'] else []
                
                for step_data in steps_data:
                    step = SagaStep(
                        id=step_data['id'],
                        name=step_data['name'],
                        service=step_data['service'],
                        command=step_data['command'],
                        compensation_command=step_data.get('compensation_command')
                    )
                    step.status = step_data['status']
                    step.started_at = (
                        datetime.fromisoformat(step_data['started_at'].replace('Z', '+00:00'))
                        if step_data['started_at'] else None
                    )
                    step.completed_at = (
                        datetime.fromisoformat(step_data['completed_at'].replace('Z', '+00:00'))
                        if step_data['completed_at'] else None
                    )
                    step.error_message = step_data.get('error_message')
                    step.result = step_data.get('result')
                    steps.append(step)
                
                # Create SAGA instance
                saga = SagaInstance(
                    id=row['id'],
                    type=row['saga_type'],
                    status=SagaStatus[row['status'].upper()] if hasattr(SagaStatus, row['status'].upper()) else SagaStatus.PENDING,
                    steps=steps,
                    input_data=json.loads(row['input_data']) if row['input_data'] else {},
                    correlation_id=row['correlation_id'],
                    tenant_id=row['tenant_id'],
                    started_at=row['started_at'],
                    completed_at=row['completed_at']
                )
                
                saga.current_step = row['current_step']
                saga.output_data = json.loads(row['output_data']) if row['output_data'] else {}
                saga.error_message = row['error_message']
                saga.metadata = json.loads(row['metadata']) if row['metadata'] else {}
                
                logger.debug(f"Retrieved SAGA instance {saga_id} from PostgreSQL")
                return saga
                
        except Exception as e:
            logger.error(f"Failed to get SAGA instance {saga_id}: {e}")
            return None
    
    async def list_saga_instances(
        self,
        status: Optional[SagaStatus] = None,
        saga_type: Optional[str] = None,
        tenant_id: Optional[str] = None,
        limit: int = 100,
        offset: int = 0
    ) -> List[SagaInstance]:
        """List SAGA instances with filtering."""
        try:
            async with self.pool.acquire() as conn:
                # Build query conditions
                conditions = []
                params = []
                param_count = 0
                
                if status:
                    param_count += 1
                    conditions.append(f"status = ${param_count}")
                    params.append(status.value if hasattr(status, 'value') else str(status))
                
                if saga_type:
                    param_count += 1
                    conditions.append(f"saga_type = ${param_count}")
                    params.append(saga_type)
                
                if tenant_id:
                    param_count += 1
                    conditions.append(f"tenant_id = ${param_count}")
                    params.append(tenant_id)
                
                # Add limit and offset
                param_count += 1
                limit_param = f"${param_count}"
                params.append(limit)
                
                param_count += 1
                offset_param = f"${param_count}"
                params.append(offset)
                
                # Build full query
                where_clause = "WHERE " + " AND ".join(conditions) if conditions else ""
                query = f"""
                    SELECT id, saga_type, status, current_step, total_steps,
                           input_data, output_data, error_message, correlation_id,
                           tenant_id, started_at, completed_at, steps_data, metadata
                    FROM saga_instances
                    {where_clause}
                    ORDER BY started_at DESC
                    LIMIT {limit_param} OFFSET {offset_param}
                """
                
                rows = await conn.fetch(query, *params)
                
                sagas = []
                for row in rows:
                    # Deserialize steps data
                    steps = []
                    steps_data = json.loads(row['steps_data']) if row['steps_data'] else []
                    
                    for step_data in steps_data:
                        step = SagaStep(
                            id=step_data['id'],
                            name=step_data['name'],
                            service=step_data['service'],
                            command=step_data['command'],
                            compensation_command=step_data.get('compensation_command')
                        )
                        step.status = step_data['status']
                        step.started_at = (
                            datetime.fromisoformat(step_data['started_at'].replace('Z', '+00:00'))
                            if step_data['started_at'] else None
                        )
                        step.completed_at = (
                            datetime.fromisoformat(step_data['completed_at'].replace('Z', '+00:00'))
                            if step_data['completed_at'] else None
                        )
                        step.error_message = step_data.get('error_message')
                        step.result = step_data.get('result')
                        steps.append(step)
                    
                    # Create SAGA instance
                    saga = SagaInstance(
                        id=row['id'],
                        type=row['saga_type'],
                        status=SagaStatus[row['status'].upper()] if hasattr(SagaStatus, row['status'].upper()) else SagaStatus.PENDING,
                        steps=steps,
                        input_data=json.loads(row['input_data']) if row['input_data'] else {},
                        correlation_id=row['correlation_id'],
                        tenant_id=row['tenant_id'],
                        started_at=row['started_at'],
                        completed_at=row['completed_at']
                    )
                    
                    saga.current_step = row['current_step']
                    saga.output_data = json.loads(row['output_data']) if row['output_data'] else {}
                    saga.error_message = row['error_message']
                    saga.metadata = json.loads(row['metadata']) if row['metadata'] else {}
                    
                    sagas.append(saga)
                
                logger.debug(f"Retrieved {len(sagas)} SAGA instances from PostgreSQL")
                return sagas
                
        except Exception as e:
            logger.error(f"Failed to list SAGA instances: {e}")
            return []
    
    async def delete_saga_instance(self, saga_id: str) -> bool:
        """Delete a SAGA instance from PostgreSQL."""
        try:
            async with self.pool.acquire() as conn:
                result = await conn.execute(
                    "DELETE FROM saga_instances WHERE id = $1",
                    saga_id
                )
                
                deleted = result == "DELETE 1"
                if deleted:
                    logger.debug(f"Deleted SAGA instance {saga_id} from PostgreSQL")
                else:
                    logger.warning(f"SAGA instance {saga_id} not found for deletion")
                
                return deleted
                
        except Exception as e:
            logger.error(f"Failed to delete SAGA instance {saga_id}: {e}")
            return False
    
    async def get_saga_count(
        self,
        status: Optional[SagaStatus] = None,
        saga_type: Optional[str] = None,
        tenant_id: Optional[str] = None
    ) -> int:
        """Get count of SAGA instances with filtering."""
        try:
            async with self.pool.acquire() as conn:
                # Build query conditions
                conditions = []
                params = []
                param_count = 0
                
                if status:
                    param_count += 1
                    conditions.append(f"status = ${param_count}")
                    params.append(status.value if hasattr(status, 'value') else str(status))
                
                if saga_type:
                    param_count += 1
                    conditions.append(f"saga_type = ${param_count}")
                    params.append(saga_type)
                
                if tenant_id:
                    param_count += 1
                    conditions.append(f"tenant_id = ${param_count}")
                    params.append(tenant_id)
                
                where_clause = "WHERE " + " AND ".join(conditions) if conditions else ""
                query = f"SELECT COUNT(*) FROM saga_instances {where_clause}"
                
                count = await conn.fetchval(query, *params)
                return count or 0
                
        except Exception as e:
            logger.error(f"Failed to get SAGA count: {e}")
            return 0
    
    async def cleanup_completed_sagas(self, older_than_hours: int = 24) -> int:
        """Clean up completed SAGA instances older than specified hours."""
        try:
            async with self.pool.acquire() as conn:
                result = await conn.execute("""
                    DELETE FROM saga_instances 
                    WHERE status IN ('COMPLETED', 'COMPENSATED') 
                    AND completed_at < NOW() - INTERVAL '%s hours'
                """, older_than_hours)
                
                deleted_count = int(result.split()[-1]) if result.startswith("DELETE") else 0
                logger.info(f"Cleaned up {deleted_count} completed SAGA instances older than {older_than_hours} hours")
                return deleted_count
                
        except Exception as e:
            logger.error(f"Failed to cleanup completed SAGAs: {e}")
            return 0
    
    async def get_saga_statistics(self) -> Dict[str, Any]:
        """Get SAGA statistics from PostgreSQL."""
        try:
            async with self.pool.acquire() as conn:
                # Get status counts
                status_rows = await conn.fetch("""
                    SELECT status, COUNT(*) as count 
                    FROM saga_instances 
                    GROUP BY status
                """)
                
                status_counts = {row['status']: row['count'] for row in status_rows}
                
                # Get type counts
                type_rows = await conn.fetch("""
                    SELECT saga_type, COUNT(*) as count 
                    FROM saga_instances 
                    GROUP BY saga_type
                """)
                
                type_counts = {row['saga_type']: row['count'] for row in type_rows}
                
                # Get recent activity (last 24 hours)
                recent_activity = await conn.fetchval("""
                    SELECT COUNT(*) 
                    FROM saga_instances 
                    WHERE started_at >= NOW() - INTERVAL '24 hours'
                """)
                
                # Get average completion time for completed sagas
                avg_duration = await conn.fetchval("""
                    SELECT AVG(EXTRACT(EPOCH FROM (completed_at - started_at)))
                    FROM saga_instances 
                    WHERE status = 'COMPLETED' AND completed_at IS NOT NULL
                """)
                
                return {
                    "total_sagas": sum(status_counts.values()),
                    "status_distribution": status_counts,
                    "type_distribution": type_counts,
                    "recent_activity_24h": recent_activity or 0,
                    "average_completion_time_seconds": float(avg_duration) if avg_duration else None
                }
                
        except Exception as e:
            logger.error(f"Failed to get SAGA statistics: {e}")
            return {}


# Add the steps_data column to existing saga_instances table if it doesn't exist
MIGRATION_ADD_STEPS_DATA_COLUMN = """
-- Add steps_data column to store serialized step information
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name='saga_instances' AND column_name='steps_data'
    ) THEN
        ALTER TABLE saga_instances ADD COLUMN steps_data JSONB DEFAULT '[]';
    END IF;
END $$;

-- Add metadata column if it doesn't exist
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name='saga_instances' AND column_name='metadata'
    ) THEN
        ALTER TABLE saga_instances ADD COLUMN metadata JSONB DEFAULT '{}';
    END IF;
END $$;

-- Create indexes for new columns
CREATE INDEX IF NOT EXISTS idx_saga_instances_steps_data ON saga_instances USING GIN (steps_data);
CREATE INDEX IF NOT EXISTS idx_saga_instances_metadata ON saga_instances USING GIN (metadata);
"""