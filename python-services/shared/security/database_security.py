"""
Database Security Utilities
SQL injection prevention and secure database operations
"""

import logging
import re
from typing import Any, Dict, List, Optional, Tuple, Union
from datetime import datetime
import psycopg2
from psycopg2 import sql
import sqlalchemy
from sqlalchemy import text, create_engine
from sqlalchemy.orm import sessionmaker
from contextlib import contextmanager

logger = logging.getLogger(__name__)

class SQLInjectionPrevention:
    """SQL injection prevention utilities"""
    
    # Dangerous SQL keywords and patterns
    DANGEROUS_PATTERNS = [
        r"(?i)\b(union|select|insert|update|delete|drop|create|alter|exec|execute)\b",
        r"(?i)\b(or|and)\s+\d+\s*=\s*\d+",
        r"(?i)';\s*(drop|delete|insert|update|create|alter)",
        r"(?i)/\*.*?\*/",  # SQL comments
        r"(?i)--[^\r\n]*",  # SQL comments
        r"(?i)\bxp_cmdshell\b",
        r"(?i)\bsp_executesql\b",
        r"(?i)'.*'.*=.*'.*'",
        r"(?i)0x[0-9a-f]+",  # Hex values
    ]
    
    @classmethod
    def validate_sql_input(cls, value: str, field_name: str = "input") -> bool:
        """
        Validate input for SQL injection patterns
        
        Raises:
            ValueError: If SQL injection pattern is detected
        """
        if not isinstance(value, str):
            return True
        
        for pattern in cls.DANGEROUS_PATTERNS:
            if re.search(pattern, value):
                logger.warning(f"SQL injection attempt detected in {field_name}: {value[:100]}")
                raise ValueError(f"Invalid input detected in {field_name}")
        
        return True
    
    @classmethod
    def sanitize_sql_input(cls, value: str) -> str:
        """
        Sanitize input by removing dangerous SQL patterns
        """
        if not isinstance(value, str):
            return value
        
        # Remove SQL comments
        value = re.sub(r"/\*.*?\*/", "", value, flags=re.IGNORECASE | re.DOTALL)
        value = re.sub(r"--[^\r\n]*", "", value, flags=re.IGNORECASE)
        
        # Escape single quotes
        value = value.replace("'", "''")
        
        return value.strip()

class SecureQueryBuilder:
    """Secure SQL query builder using parameterized queries"""
    
    def __init__(self):
        self.query_parts = []
        self.parameters = {}
        self.parameter_count = 0
    
    def select(self, columns: Union[str, List[str]], table: str) -> 'SecureQueryBuilder':
        """Add SELECT clause"""
        if isinstance(columns, str):
            # Validate column name
            if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$', columns.replace(' ', '').replace(',', '')):
                raise ValueError(f"Invalid column name: {columns}")
            columns_str = columns
        else:
            # Validate each column name
            for col in columns:
                if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$', col):
                    raise ValueError(f"Invalid column name: {col}")
            columns_str = ", ".join(columns)
        
        # Validate table name
        if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', table):
            raise ValueError(f"Invalid table name: {table}")
        
        self.query_parts.append(f"SELECT {columns_str} FROM {table}")
        return self
    
    def where(self, condition_column: str, operator: str = "=") -> Tuple['SecureQueryBuilder', str]:
        """Add WHERE clause with parameterized condition"""
        # Validate column name
        if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$', condition_column):
            raise ValueError(f"Invalid column name: {condition_column}")
        
        # Validate operator
        allowed_operators = ["=", "!=", "<>", "<", ">", "<=", ">=", "LIKE", "IN", "NOT IN", "IS NULL", "IS NOT NULL"]
        if operator.upper() not in allowed_operators:
            raise ValueError(f"Invalid operator: {operator}")
        
        self.parameter_count += 1
        param_name = f"param_{self.parameter_count}"
        
        if operator.upper() in ["IS NULL", "IS NOT NULL"]:
            self.query_parts.append(f"WHERE {condition_column} {operator}")
        else:
            self.query_parts.append(f"WHERE {condition_column} {operator} %({param_name})s")
        
        return self, param_name
    
    def and_condition(self, condition_column: str, operator: str = "=") -> Tuple['SecureQueryBuilder', str]:
        """Add AND condition"""
        if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$', condition_column):
            raise ValueError(f"Invalid column name: {condition_column}")
        
        allowed_operators = ["=", "!=", "<>", "<", ">", "<=", ">=", "LIKE", "IN", "NOT IN", "IS NULL", "IS NOT NULL"]
        if operator.upper() not in allowed_operators:
            raise ValueError(f"Invalid operator: {operator}")
        
        self.parameter_count += 1
        param_name = f"param_{self.parameter_count}"
        
        if operator.upper() in ["IS NULL", "IS NOT NULL"]:
            self.query_parts.append(f"AND {condition_column} {operator}")
        else:
            self.query_parts.append(f"AND {condition_column} {operator} %({param_name})s")
        
        return self, param_name
    
    def order_by(self, column: str, direction: str = "ASC") -> 'SecureQueryBuilder':
        """Add ORDER BY clause"""
        if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$', column):
            raise ValueError(f"Invalid column name: {column}")
        
        if direction.upper() not in ["ASC", "DESC"]:
            raise ValueError(f"Invalid sort direction: {direction}")
        
        self.query_parts.append(f"ORDER BY {column} {direction.upper()}")
        return self
    
    def limit(self, count: int, offset: int = 0) -> 'SecureQueryBuilder':
        """Add LIMIT clause"""
        if not isinstance(count, int) or count < 0:
            raise ValueError("Limit count must be a non-negative integer")
        
        if not isinstance(offset, int) or offset < 0:
            raise ValueError("Offset must be a non-negative integer")
        
        if offset > 0:
            self.query_parts.append(f"LIMIT {count} OFFSET {offset}")
        else:
            self.query_parts.append(f"LIMIT {count}")
        
        return self
    
    def build(self) -> Tuple[str, Dict[str, Any]]:
        """Build the final query and parameters"""
        query = " ".join(self.query_parts)
        return query, self.parameters
    
    def set_parameter(self, param_name: str, value: Any) -> 'SecureQueryBuilder':
        """Set parameter value"""
        # Validate string parameters for SQL injection
        if isinstance(value, str):
            SQLInjectionPrevention.validate_sql_input(value, param_name)
        
        self.parameters[param_name] = value
        return self

class SecureDatabaseManager:
    """Secure database manager with SQL injection prevention"""
    
    def __init__(self, database_url: str, pool_size: int = 5):
        self.database_url = database_url
        self.engine = create_engine(
            database_url,
            pool_size=pool_size,
            pool_pre_ping=True,  # Validate connections
            echo=False  # Don't log SQL queries (security)
        )
        self.SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=self.engine)
    
    @contextmanager
    def get_session(self):
        """Get database session with automatic cleanup"""
        session = self.SessionLocal()
        try:
            yield session
        except Exception as e:
            session.rollback()
            logger.error(f"Database session error: {str(e)}")
            raise
        finally:
            session.close()
    
    def execute_secure_query(self, 
                           query: str, 
                           parameters: Dict[str, Any] = None,
                           fetch: bool = True) -> Optional[List[Dict]]:
        """
        Execute parameterized query securely
        
        Args:
            query: SQL query with named parameters (%(param_name)s)
            parameters: Dictionary of parameter values
            fetch: Whether to fetch results
            
        Returns:
            Query results or None for non-SELECT queries
        """
        if parameters is None:
            parameters = {}
        
        # Validate all string parameters
        for param_name, param_value in parameters.items():
            if isinstance(param_value, str):
                SQLInjectionPrevention.validate_sql_input(param_value, param_name)
        
        try:
            with self.get_session() as session:
                result = session.execute(text(query), parameters)
                
                if fetch and result.returns_rows:
                    # Convert to list of dictionaries
                    columns = result.keys()
                    rows = result.fetchall()
                    return [dict(zip(columns, row)) for row in rows]
                else:
                    session.commit()
                    return None
                    
        except Exception as e:
            logger.error(f"Secure query execution failed: {str(e)}")
            raise
    
    def get_by_id(self, 
                  table: str, 
                  id_column: str, 
                  id_value: Union[str, int],
                  columns: List[str] = None) -> Optional[Dict]:
        """
        Securely get record by ID
        """
        builder = SecureQueryBuilder()
        
        if columns:
            query_builder, param_name = builder.select(columns, table).where(id_column)
        else:
            query_builder, param_name = builder.select("*", table).where(id_column)
        
        query_builder.set_parameter(param_name, id_value)
        
        query, parameters = query_builder.build()
        results = self.execute_secure_query(query, parameters)
        
        return results[0] if results else None
    
    def search_records(self,
                      table: str,
                      filters: Dict[str, Any],
                      columns: List[str] = None,
                      order_by: str = None,
                      limit: int = 100,
                      offset: int = 0) -> List[Dict]:
        """
        Securely search records with filters
        """
        builder = SecureQueryBuilder()
        
        if columns:
            builder.select(columns, table)
        else:
            builder.select("*", table)
        
        # Add filters
        first_filter = True
        for column, value in filters.items():
            if first_filter:
                query_builder, param_name = builder.where(column)
                first_filter = False
            else:
                query_builder, param_name = builder.and_condition(column)
            
            query_builder.set_parameter(param_name, value)
        
        # Add ordering
        if order_by:
            builder.order_by(order_by)
        
        # Add pagination
        builder.limit(limit, offset)
        
        query, parameters = builder.build()
        return self.execute_secure_query(query, parameters) or []
    
    def count_records(self, table: str, filters: Dict[str, Any] = None) -> int:
        """
        Securely count records with optional filters
        """
        builder = SecureQueryBuilder()
        builder.select("COUNT(*) as count", table)
        
        if filters:
            first_filter = True
            for column, value in filters.items():
                if first_filter:
                    query_builder, param_name = builder.where(column)
                    first_filter = False
                else:
                    query_builder, param_name = builder.and_condition(column)
                
                query_builder.set_parameter(param_name, value)
        
        query, parameters = builder.build()
        results = self.execute_secure_query(query, parameters)
        
        return results[0]["count"] if results else 0

class AuditLogger:
    """Database audit logger for security events"""
    
    def __init__(self, db_manager: SecureDatabaseManager):
        self.db_manager = db_manager
        self.audit_table = "security_audit_log"
        self._ensure_audit_table()
    
    def _ensure_audit_table(self):
        """Ensure audit table exists"""
        create_table_query = f"""
        CREATE TABLE IF NOT EXISTS {self.audit_table} (
            id SERIAL PRIMARY KEY,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            user_id VARCHAR(255),
            action VARCHAR(100) NOT NULL,
            resource VARCHAR(255),
            ip_address INET,
            user_agent TEXT,
            status VARCHAR(20) NOT NULL,
            details JSONB,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON {self.audit_table}(timestamp);
        CREATE INDEX IF NOT EXISTS idx_audit_user_id ON {self.audit_table}(user_id);
        CREATE INDEX IF NOT EXISTS idx_audit_action ON {self.audit_table}(action);
        """
        
        try:
            self.db_manager.execute_secure_query(create_table_query, fetch=False)
        except Exception as e:
            logger.error(f"Failed to create audit table: {str(e)}")
    
    def log_security_event(self,
                          action: str,
                          status: str = "success",
                          user_id: str = None,
                          resource: str = None,
                          ip_address: str = None,
                          user_agent: str = None,
                          details: Dict[str, Any] = None):
        """
        Log security event to audit table
        """
        try:
            query = f"""
            INSERT INTO {self.audit_table} 
            (user_id, action, resource, ip_address, user_agent, status, details)
            VALUES (%(user_id)s, %(action)s, %(resource)s, %(ip_address)s, %(user_agent)s, %(status)s, %(details)s)
            """
            
            import json
            parameters = {
                "user_id": user_id,
                "action": action,
                "resource": resource,
                "ip_address": ip_address,
                "user_agent": user_agent,
                "status": status,
                "details": json.dumps(details) if details else None
            }
            
            self.db_manager.execute_secure_query(query, parameters, fetch=False)
            
        except Exception as e:
            logger.error(f"Failed to log security event: {str(e)}")
    
    def log_failed_login(self, email: str, ip_address: str, user_agent: str = None):
        """Log failed login attempt"""
        self.log_security_event(
            action="failed_login",
            status="failure",
            resource=email,
            ip_address=ip_address,
            user_agent=user_agent
        )
    
    def log_successful_login(self, user_id: str, ip_address: str, user_agent: str = None):
        """Log successful login"""
        self.log_security_event(
            action="successful_login",
            status="success",
            user_id=user_id,
            ip_address=ip_address,
            user_agent=user_agent
        )
    
    def log_permission_denied(self, user_id: str, resource: str, ip_address: str = None):
        """Log permission denied event"""
        self.log_security_event(
            action="permission_denied",
            status="failure",
            user_id=user_id,
            resource=resource,
            ip_address=ip_address
        )
    
    def log_data_access(self, user_id: str, resource: str, action: str = "read"):
        """Log data access event"""
        self.log_security_event(
            action=f"data_{action}",
            status="success",
            user_id=user_id,
            resource=resource
        )

# Example usage functions
def create_secure_database_manager(database_url: str) -> SecureDatabaseManager:
    """Create a secure database manager instance"""
    return SecureDatabaseManager(database_url)

def validate_and_sanitize_db_input(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate and sanitize dictionary data for database operations
    """
    sanitized_data = {}
    
    for key, value in data.items():
        # Validate key name (column names)
        if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', key):
            raise ValueError(f"Invalid column name: {key}")
        
        # Validate and sanitize value
        if isinstance(value, str):
            SQLInjectionPrevention.validate_sql_input(value, key)
            sanitized_data[key] = SQLInjectionPrevention.sanitize_sql_input(value)
        else:
            sanitized_data[key] = value
    
    return sanitized_data