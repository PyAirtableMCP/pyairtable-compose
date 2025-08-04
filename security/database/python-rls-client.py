"""
Python Row-Level Security Integration for PyAirtable
Multi-tenant database access with automatic tenant isolation
Security implementation for 3vantage organization
"""

import json
import logging
import threading
import uuid
from contextlib import contextmanager
from dataclasses import dataclass, asdict
from datetime import datetime
from typing import Dict, List, Optional, Any, Union, Tuple
import asyncio
import asyncpg
import psycopg2
import psycopg2.extras
from psycopg2.pool import ThreadedConnectionPool


@dataclass
class TenantContext:
    """Tenant context for RLS enforcement"""
    tenant_id: uuid.UUID
    user_id: uuid.UUID
    role: str
    ip_address: str
    
    def to_dict(self) -> Dict[str, str]:
        return {
            'tenant_id': str(self.tenant_id),
            'user_id': str(self.user_id),
            'role': self.role,
            'ip_address': self.ip_address
        }


class DatabaseManager:
    """Multi-tenant database manager with Row-Level Security"""
    
    def __init__(
        self, 
        connection_params: Dict[str, str], 
        logger: logging.Logger = None,
        min_conn: int = 5,
        max_conn: int = 20
    ):
        self.connection_params = connection_params
        self.logger = logger or logging.getLogger(__name__)
        self._local = threading.local()
        
        # Create connection pool
        self.pool = ThreadedConnectionPool(
            min_conn, max_conn,
            **connection_params
        )
        
        self.logger.info("Database manager initialized with RLS support")
    
    def get_connection(self):
        """Get a connection from the pool"""
        return self.pool.getconn()
    
    def put_connection(self, conn):
        """Return a connection to the pool"""
        self.pool.putconn(conn)
    
    @contextmanager
    def get_tenant_connection(self, tenant_ctx: TenantContext):
        """Get a connection with tenant context set"""
        conn = self.get_connection()
        try:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cursor:
                # Set tenant context in session
                self._set_tenant_context(cursor, tenant_ctx)
                yield conn
        finally:
            self.put_connection(conn)
    
    def _set_tenant_context(self, cursor, tenant_ctx: TenantContext):
        """Set tenant context session variables"""
        session_vars = [
            f"SET LOCAL app.current_tenant_id = '{tenant_ctx.tenant_id}'",
            f"SET LOCAL app.current_user_id = '{tenant_ctx.user_id}'",
            f"SET LOCAL app.current_user_role = '{tenant_ctx.role}'",
            f"SET LOCAL app.client_ip = '{tenant_ctx.ip_address}'"
        ]
        
        for var_sql in session_vars:
            cursor.execute(var_sql)
        
        self.logger.debug(
            f"Tenant context set: tenant={tenant_ctx.tenant_id}, user={tenant_ctx.user_id}"
        )
    
    def execute_with_tenant_context(
        self, 
        tenant_ctx: TenantContext, 
        query: str, 
        params: Tuple = None
    ) -> List[Dict]:
        """Execute a query with tenant context"""
        with self.get_tenant_connection(tenant_ctx) as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cursor:
                cursor.execute(query, params or ())
                
                if cursor.description:
                    results = [dict(row) for row in cursor.fetchall()]
                    return results
                else:
                    conn.commit()
                    return []
    
    def execute_transaction_with_tenant_context(
        self,
        tenant_ctx: TenantContext,
        operations: List[Tuple[str, Tuple]]
    ) -> bool:
        """Execute multiple operations in a transaction with tenant context"""
        with self.get_tenant_connection(tenant_ctx) as conn:
            try:
                with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cursor:
                    for query, params in operations:
                        cursor.execute(query, params or ())
                    conn.commit()
                    return True
            except Exception as e:
                conn.rollback()
                self.logger.error(f"Transaction failed: {e}")
                raise
    
    def close(self):
        """Close all connections in the pool"""
        if hasattr(self, 'pool'):
            self.pool.closeall()


class AsyncDatabaseManager:
    """Async multi-tenant database manager with RLS"""
    
    def __init__(
        self,
        connection_params: Dict[str, str],
        logger: logging.Logger = None,
        max_connections: int = 20
    ):
        self.connection_params = connection_params
        self.logger = logger or logging.getLogger(__name__)
        self.max_connections = max_connections
        self._pool = None
    
    async def initialize(self):
        """Initialize the async connection pool"""
        self._pool = await asyncpg.create_pool(
            **self.connection_params,
            max_size=self.max_connections
        )
        self.logger.info("Async database manager initialized with RLS support")
    
    async def execute_with_tenant_context(
        self,
        tenant_ctx: TenantContext,
        query: str,
        *params
    ) -> List[Dict]:
        """Execute query with tenant context (async)"""
        if not self._pool:
            await self.initialize()
        
        async with self._pool.acquire() as conn:
            async with conn.transaction():
                # Set tenant context
                await self._set_tenant_context_async(conn, tenant_ctx)
                
                # Execute query
                result = await conn.fetch(query, *params)
                return [dict(row) for row in result]
    
    async def _set_tenant_context_async(self, conn, tenant_ctx: TenantContext):
        """Set tenant context in async connection"""
        session_vars = [
            f"SET LOCAL app.current_tenant_id = '{tenant_ctx.tenant_id}'",
            f"SET LOCAL app.current_user_id = '{tenant_ctx.user_id}'",
            f"SET LOCAL app.current_user_role = '{tenant_ctx.role}'",
            f"SET LOCAL app.client_ip = '{tenant_ctx.ip_address}'"
        ]
        
        for var_sql in session_vars:
            await conn.execute(var_sql)
    
    async def close(self):
        """Close the connection pool"""
        if self._pool:
            await self._pool.close()


@dataclass
class Tenant:
    """Tenant model"""
    id: uuid.UUID
    name: str
    slug: str
    status: str
    tier: str
    max_users: int
    max_workspaces: int
    max_storage_gb: int
    encryption_key_id: Optional[str]
    created_at: datetime
    updated_at: datetime
    security_settings: Dict[str, Any]


@dataclass
class User:
    """User model"""
    id: uuid.UUID
    tenant_id: uuid.UUID
    email: str
    username: Optional[str]
    first_name: Optional[str]
    last_name: Optional[str]
    status: str
    email_verified: bool
    mfa_enabled: bool
    last_login: Optional[datetime]
    failed_login_attempts: int
    locked_until: Optional[datetime]
    created_at: datetime
    updated_at: datetime


@dataclass
class Workspace:
    """Workspace model"""
    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    description: Optional[str]
    owner_id: uuid.UUID
    settings: Dict[str, Any]
    status: str
    created_at: datetime
    updated_at: datetime


class TenantService:
    """Service for tenant management operations"""
    
    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager
        self.logger = logging.getLogger(__name__)
    
    def get_tenant_by_id(self, tenant_id: uuid.UUID) -> Optional[Tenant]:
        """Get tenant by ID (admin operation, no RLS)"""
        query = """
            SELECT id, name, slug, status, tier, max_users, max_workspaces, 
                   max_storage_gb, encryption_key_id, created_at, updated_at, 
                   security_settings
            FROM tenant_management.tenants
            WHERE id = %s
        """
        
        with self.db.get_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cursor:
                cursor.execute(query, (tenant_id,))
                row = cursor.fetchone()
                
                if row:
                    return Tenant(**dict(row))
                return None
    
    def create_tenant(
        self, 
        name: str, 
        slug: str, 
        owner_email: str, 
        owner_password: str, 
        tier: str = 'standard'
    ) -> Tenant:
        """Create a new tenant with owner user"""
        query = """
            SELECT tenant_management.create_tenant(%s, %s, %s, %s, %s)
        """
        
        with self.db.get_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(query, (name, slug, owner_email, owner_password, tier))
                tenant_id = cursor.fetchone()[0]
                conn.commit()
        
        return self.get_tenant_by_id(uuid.UUID(tenant_id))
    
    def list_tenants(self, limit: int = 50, offset: int = 0) -> List[Tenant]:
        """List all tenants (admin operation)"""
        query = """
            SELECT id, name, slug, status, tier, max_users, max_workspaces,
                   max_storage_gb, encryption_key_id, created_at, updated_at,
                   security_settings
            FROM tenant_management.tenants
            WHERE status = 'active'
            ORDER BY created_at DESC
            LIMIT %s OFFSET %s
        """
        
        with self.db.get_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cursor:
                cursor.execute(query, (limit, offset))
                rows = cursor.fetchall()
                
                return [Tenant(**dict(row)) for row in rows]


class UserService:
    """Service for user operations with RLS"""
    
    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager
        self.logger = logging.getLogger(__name__)
    
    def get_users(
        self, 
        tenant_ctx: TenantContext, 
        limit: int = 50, 
        offset: int = 0
    ) -> List[User]:
        """Get users for current tenant (RLS enforced)"""
        query = """
            SELECT id, tenant_id, email, username, first_name, last_name, 
                   status, email_verified, mfa_enabled, last_login, 
                   failed_login_attempts, locked_until, created_at, updated_at
            FROM public.users
            WHERE status IN ('active', 'inactive')
            ORDER BY created_at DESC
            LIMIT %s OFFSET %s
        """
        
        results = self.db.execute_with_tenant_context(
            tenant_ctx, query, (limit, offset)
        )
        
        users = []
        for row in results:
            # Convert string UUIDs back to UUID objects
            row['id'] = uuid.UUID(row['id'])
            row['tenant_id'] = uuid.UUID(row['tenant_id'])
            users.append(User(**row))
        
        return users
    
    def create_user(
        self, 
        tenant_ctx: TenantContext, 
        email: str, 
        password_hash: str,
        first_name: Optional[str] = None,
        last_name: Optional[str] = None
    ) -> User:
        """Create a new user in current tenant"""
        query = """
            INSERT INTO public.users (tenant_id, email, password_hash, first_name, last_name, status, email_verified)
            VALUES (%s, %s, %s, %s, %s, 'active', false)
            RETURNING id, tenant_id, email, username, first_name, last_name,
                      status, email_verified, mfa_enabled, last_login,
                      failed_login_attempts, locked_until, created_at, updated_at
        """
        
        results = self.db.execute_with_tenant_context(
            tenant_ctx, query, 
            (tenant_ctx.tenant_id, email, password_hash, first_name, last_name)
        )
        
        if results:
            row = results[0]
            row['id'] = uuid.UUID(row['id'])
            row['tenant_id'] = uuid.UUID(row['tenant_id'])
            return User(**row)
        
        raise Exception("Failed to create user")
    
    def get_user_by_email(self, tenant_ctx: TenantContext, email: str) -> Optional[User]:
        """Get user by email within current tenant"""
        query = """
            SELECT id, tenant_id, email, username, first_name, last_name,
                   status, email_verified, mfa_enabled, last_login,
                   failed_login_attempts, locked_until, created_at, updated_at
            FROM public.users
            WHERE email = %s AND status != 'deleted'
        """
        
        results = self.db.execute_with_tenant_context(tenant_ctx, query, (email,))
        
        if results:
            row = results[0]
            row['id'] = uuid.UUID(row['id'])
            row['tenant_id'] = uuid.UUID(row['tenant_id'])
            return User(**row)
        
        return None


class WorkspaceService:
    """Service for workspace operations with RLS"""
    
    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager
        self.logger = logging.getLogger(__name__)
    
    def get_workspaces(
        self, 
        tenant_ctx: TenantContext, 
        limit: int = 50, 
        offset: int = 0
    ) -> List[Workspace]:
        """Get workspaces for current tenant (RLS enforced)"""
        query = """
            SELECT id, tenant_id, name, description, owner_id, settings, 
                   status, created_at, updated_at
            FROM public.workspaces
            WHERE status = 'active'
            ORDER BY created_at DESC
            LIMIT %s OFFSET %s
        """
        
        results = self.db.execute_with_tenant_context(
            tenant_ctx, query, (limit, offset)
        )
        
        workspaces = []
        for row in results:
            row['id'] = uuid.UUID(row['id'])
            row['tenant_id'] = uuid.UUID(row['tenant_id'])
            row['owner_id'] = uuid.UUID(row['owner_id'])
            workspaces.append(Workspace(**row))
        
        return workspaces
    
    def create_workspace(
        self, 
        tenant_ctx: TenantContext, 
        name: str, 
        description: Optional[str] = None
    ) -> Workspace:
        """Create a new workspace in current tenant"""
        query = """
            INSERT INTO public.workspaces (tenant_id, name, description, owner_id, status)
            VALUES (%s, %s, %s, %s, 'active')
            RETURNING id, tenant_id, name, description, owner_id, settings,
                      status, created_at, updated_at
        """
        
        results = self.db.execute_with_tenant_context(
            tenant_ctx, query, 
            (tenant_ctx.tenant_id, name, description, tenant_ctx.user_id)
        )
        
        if results:
            row = results[0]
            row['id'] = uuid.UUID(row['id'])
            row['tenant_id'] = uuid.UUID(row['tenant_id'])
            row['owner_id'] = uuid.UUID(row['owner_id'])
            return Workspace(**row)
        
        raise Exception("Failed to create workspace")


class SecurityService:
    """Service for security operations and audit logging"""
    
    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager
        self.logger = logging.getLogger(__name__)
    
    def log_security_event(
        self,
        tenant_ctx: TenantContext,
        event_type: str,
        action: str,
        result: str,
        details: Dict[str, Any] = None
    ):
        """Log a security event to audit log"""
        query = """
            INSERT INTO security_audit.audit_log (
                tenant_id, user_id, event_type, action, result, 
                ip_address, details, created_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
        """
        
        self.db.execute_with_tenant_context(
            tenant_ctx, query,
            (
                tenant_ctx.tenant_id,
                tenant_ctx.user_id,
                event_type,
                action,
                result,
                tenant_ctx.ip_address,
                json.dumps(details or {})
            )
        )
        
        self.logger.info(
            f"Security event logged: {event_type}.{action} = {result} "
            f"for tenant {tenant_ctx.tenant_id}"
        )
    
    def validate_tenant_isolation(
        self, 
        tenant_ctx: TenantContext, 
        test_tenant_id: uuid.UUID
    ) -> Dict[str, int]:
        """Validate tenant isolation for a specific tenant"""
        query = """
            SELECT table_name, record_count
            FROM security.validate_tenant_isolation(%s)
        """
        
        results = self.db.execute_with_tenant_context(
            tenant_ctx, query, (test_tenant_id,)
        )
        
        return {row['table_name']: row['record_count'] for row in results}
    
    def get_security_metrics(self, tenant_ctx: TenantContext) -> Dict[str, Any]:
        """Get security metrics for current tenant"""
        query = """
            SELECT tenant_id, tenant_name, tier, user_count, workspace_count,
                   table_count, record_count, api_key_count, last_user_activity,
                   failed_operations_24h
            FROM security_audit.tenant_security_metrics
            WHERE tenant_id = %s
        """
        
        results = self.db.execute_with_tenant_context(
            tenant_ctx, query, (tenant_ctx.tenant_id,)
        )
        
        if results:
            return results[0]
        return {}


class RLSMiddleware:
    """Middleware for automatic tenant context injection"""
    
    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager
        self.logger = logging.getLogger(__name__)
    
    def create_tenant_context(
        self,
        tenant_id: str,
        user_id: str,
        role: str,
        ip_address: str
    ) -> TenantContext:
        """Create tenant context from request parameters"""
        return TenantContext(
            tenant_id=uuid.UUID(tenant_id),
            user_id=uuid.UUID(user_id),
            role=role,
            ip_address=ip_address
        )
    
    def validate_tenant_access(self, tenant_ctx: TenantContext) -> bool:
        """Validate that user has access to tenant"""
        query = """
            SELECT COUNT(*) as count
            FROM tenant_management.tenant_users
            WHERE tenant_id = %s AND user_id = %s AND status = 'active'
        """
        
        results = self.db.execute_with_tenant_context(
            tenant_ctx, query, (tenant_ctx.tenant_id, tenant_ctx.user_id)
        )
        
        return results[0]['count'] > 0 if results else False


# Example usage and testing
def example_usage():
    """Example usage of RLS database services"""
    import logging
    
    # Configure logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    # Database connection parameters
    connection_params = {
        'host': 'localhost',
        'database': 'pyairtable',
        'user': 'pyairtable_app',
        'password': 'secure_password',
        'port': 5432,
        'sslmode': 'require'
    }
    
    # Initialize database manager
    db_manager = DatabaseManager(connection_params, logger)
    
    # Create services
    tenant_service = TenantService(db_manager)
    user_service = UserService(db_manager)
    workspace_service = WorkspaceService(db_manager)
    security_service = SecurityService(db_manager)
    
    try:
        # Create tenant context (typically from JWT or session)
        tenant_ctx = TenantContext(
            tenant_id=uuid.uuid4(),
            user_id=uuid.uuid4(),
            role='admin',
            ip_address='192.168.1.100'
        )
        
        # Log security event
        security_service.log_security_event(
            tenant_ctx, 'authentication', 'login', 'success'
        )
        
        # Get users (automatically filtered by tenant)
        users = user_service.get_users(tenant_ctx, limit=10)
        logger.info(f"Retrieved {len(users)} users for tenant {tenant_ctx.tenant_id}")
        
        # Create workspace (automatically associated with tenant)
        workspace = workspace_service.create_workspace(
            tenant_ctx, "Test Workspace", "A test workspace"
        )
        logger.info(f"Created workspace: {workspace.name}")
        
        # Validate tenant isolation
        isolation_results = security_service.validate_tenant_isolation(
            tenant_ctx, tenant_ctx.tenant_id
        )
        logger.info(f"Tenant isolation validation: {isolation_results}")
        
    except Exception as e:
        logger.error(f"Example failed: {e}")
    finally:
        db_manager.close()


if __name__ == "__main__":
    example_usage()