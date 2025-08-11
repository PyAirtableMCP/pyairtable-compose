#!/usr/bin/env python3
"""
Role-Based Access Control (RBAC) Framework

Comprehensive RBAC implementation with multi-factor authentication,
privileged access management, and session security.
"""

import os
import json
import yaml
import logging
import hashlib
import datetime
import secrets
import uuid
from typing import Dict, List, Any, Optional, Union
from pathlib import Path
from dataclasses import dataclass, asdict
from enum import Enum
import sqlite3
import asyncio
import aiohttp
import jwt
import bcrypt
import pyotp
import qrcode
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
import base64

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/rbac-framework.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class UserRole(Enum):
    SUPER_ADMIN = "super_admin"
    ADMIN = "admin"
    SECURITY_OFFICER = "security_officer"
    DEVELOPER = "developer"
    ANALYST = "analyst"
    USER = "user"
    GUEST = "guest"

class Permission(Enum):
    # System permissions
    SYSTEM_ADMIN = "system:admin"
    SYSTEM_READ = "system:read"
    SYSTEM_WRITE = "system:write"
    
    # User management
    USER_CREATE = "user:create"
    USER_READ = "user:read"
    USER_UPDATE = "user:update"
    USER_DELETE = "user:delete"
    
    # Data permissions
    DATA_READ = "data:read"
    DATA_WRITE = "data:write"
    DATA_DELETE = "data:delete"
    DATA_EXPORT = "data:export"
    
    # Security permissions
    SECURITY_READ = "security:read"
    SECURITY_WRITE = "security:write"
    SECURITY_ADMIN = "security:admin"
    
    # Audit permissions
    AUDIT_READ = "audit:read"
    AUDIT_WRITE = "audit:write"

class SessionStatus(Enum):
    ACTIVE = "active"
    EXPIRED = "expired"
    TERMINATED = "terminated"
    LOCKED = "locked"

class AuthMethod(Enum):
    PASSWORD = "password"
    TOTP = "totp"
    SMS = "sms"
    HARDWARE_TOKEN = "hardware_token"
    BIOMETRIC = "biometric"

@dataclass
class User:
    """User account information"""
    user_id: str
    username: str
    email: str
    password_hash: str
    roles: List[UserRole]
    is_active: bool
    is_locked: bool
    created_at: datetime.datetime
    last_login: Optional[datetime.datetime] = None
    failed_login_attempts: int = 0
    mfa_enabled: bool = False
    mfa_secret: Optional[str] = None
    password_expires_at: Optional[datetime.datetime] = None
    
@dataclass
class Session:
    """User session information"""
    session_id: str
    user_id: str
    status: SessionStatus
    created_at: datetime.datetime
    expires_at: datetime.datetime
    last_activity: datetime.datetime
    ip_address: str
    user_agent: str
    mfa_verified: bool = False

@dataclass
class AccessLog:
    """Access attempt logging"""
    log_id: str
    user_id: Optional[str]
    username: str
    action: str
    resource: str
    ip_address: str
    user_agent: str
    timestamp: datetime.datetime
    success: bool
    failure_reason: Optional[str] = None

class RBACFramework:
    """Main RBAC framework implementation"""
    
    def __init__(self, config_path: str = "rbac-config.yaml"):
        self.config = self._load_config(config_path)
        self.db_path = self.config.get('database_path', 'rbac.db')
        self.encryption_key = self._get_encryption_key()
        self.cipher_suite = Fernet(self.encryption_key)
        self.jwt_secret = self.config.get('jwt_secret', secrets.token_urlsafe(32))
        self._init_database()
        self._load_role_permissions()
    
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load RBAC configuration"""
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Config file {config_path} not found, using defaults")
            return self._default_config()
    
    def _default_config(self) -> Dict[str, Any]:
        """Default RBAC configuration"""
        return {
            'session_timeout_minutes': 480,  # 8 hours
            'max_failed_attempts': 5,
            'account_lockout_minutes': 30,
            'password_min_length': 12,
            'password_complexity_required': True,
            'mfa_required_roles': ['super_admin', 'admin', 'security_officer'],
            'password_expiry_days': 90,
            'jwt_expiry_hours': 24,
            'audit_log_retention_days': 2555,  # 7 years
            'privileged_session_timeout_minutes': 60
        }
    
    def _get_encryption_key(self) -> bytes:
        """Get or generate encryption key"""
        key_file = Path('.rbac_encryption_key')
        if key_file.exists():
            return key_file.read_bytes()
        else:
            key = Fernet.generate_key()
            key_file.write_bytes(key)
            os.chmod(key_file, 0o600)
            return key
    
    def _init_database(self):
        """Initialize RBAC database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Users table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                user_id TEXT PRIMARY KEY,
                username TEXT UNIQUE NOT NULL,
                email TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                roles TEXT NOT NULL,
                is_active BOOLEAN DEFAULT TRUE,
                is_locked BOOLEAN DEFAULT FALSE,
                created_at TEXT NOT NULL,
                last_login TEXT,
                failed_login_attempts INTEGER DEFAULT 0,
                mfa_enabled BOOLEAN DEFAULT FALSE,
                mfa_secret TEXT,
                password_expires_at TEXT
            )
        ''')
        
        # Sessions table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS sessions (
                session_id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                last_activity TEXT NOT NULL,
                ip_address TEXT NOT NULL,
                user_agent TEXT NOT NULL,
                mfa_verified BOOLEAN DEFAULT FALSE,
                FOREIGN KEY (user_id) REFERENCES users (user_id)
            )
        ''')
        
        # Access logs table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS access_logs (
                log_id TEXT PRIMARY KEY,
                user_id TEXT,
                username TEXT NOT NULL,
                action TEXT NOT NULL,
                resource TEXT NOT NULL,
                ip_address TEXT NOT NULL,
                user_agent TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                success BOOLEAN NOT NULL,
                failure_reason TEXT,
                FOREIGN KEY (user_id) REFERENCES users (user_id)
            )
        ''')
        
        # Role permissions table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS role_permissions (
                role TEXT NOT NULL,
                permission TEXT NOT NULL,
                PRIMARY KEY (role, permission)
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def _load_role_permissions(self):
        """Load role-permission mappings"""
        role_permissions = {
            UserRole.SUPER_ADMIN: [
                Permission.SYSTEM_ADMIN, Permission.USER_CREATE, Permission.USER_READ,
                Permission.USER_UPDATE, Permission.USER_DELETE, Permission.DATA_READ,
                Permission.DATA_WRITE, Permission.DATA_DELETE, Permission.DATA_EXPORT,
                Permission.SECURITY_ADMIN, Permission.AUDIT_READ, Permission.AUDIT_WRITE
            ],
            UserRole.ADMIN: [
                Permission.SYSTEM_READ, Permission.SYSTEM_WRITE, Permission.USER_CREATE,
                Permission.USER_READ, Permission.USER_UPDATE, Permission.DATA_READ,
                Permission.DATA_WRITE, Permission.SECURITY_READ, Permission.SECURITY_WRITE,
                Permission.AUDIT_READ
            ],
            UserRole.SECURITY_OFFICER: [
                Permission.SYSTEM_READ, Permission.USER_READ, Permission.DATA_READ,
                Permission.SECURITY_READ, Permission.SECURITY_WRITE, Permission.SECURITY_ADMIN,
                Permission.AUDIT_READ, Permission.AUDIT_WRITE
            ],
            UserRole.DEVELOPER: [
                Permission.SYSTEM_READ, Permission.DATA_READ, Permission.DATA_WRITE,
                Permission.SECURITY_READ
            ],
            UserRole.ANALYST: [
                Permission.DATA_READ, Permission.DATA_EXPORT, Permission.AUDIT_READ
            ],
            UserRole.USER: [
                Permission.DATA_READ
            ],
            UserRole.GUEST: []
        }
        
        # Store in database
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Clear existing permissions
        cursor.execute('DELETE FROM role_permissions')
        
        # Insert role permissions
        for role, permissions in role_permissions.items():
            for permission in permissions:
                cursor.execute(
                    'INSERT INTO role_permissions (role, permission) VALUES (?, ?)',
                    (role.value, permission.value)
                )
        
        conn.commit()
        conn.close()
    
    def _encrypt_sensitive_data(self, data: str) -> str:
        """Encrypt sensitive data"""
        return self.cipher_suite.encrypt(data.encode()).decode()
    
    def _decrypt_sensitive_data(self, encrypted_data: str) -> str:
        """Decrypt sensitive data"""
        try:
            return self.cipher_suite.decrypt(encrypted_data.encode()).decode()
        except Exception as e:
            logger.error(f"Failed to decrypt data: {e}")
            return ""
    
    def _hash_password(self, password: str) -> str:
        """Hash password using bcrypt"""
        salt = bcrypt.gensalt()
        return bcrypt.hashpw(password.encode(), salt).decode()
    
    def _verify_password(self, password: str, password_hash: str) -> bool:
        """Verify password against hash"""
        try:
            return bcrypt.checkpw(password.encode(), password_hash.encode())
        except Exception:
            return False
    
    def _validate_password_complexity(self, password: str) -> bool:
        """Validate password complexity requirements"""
        if len(password) < self.config.get('password_min_length', 12):
            return False
        
        if not self.config.get('password_complexity_required', True):
            return True
        
        # Check for uppercase, lowercase, digits, and special characters
        has_upper = any(c.isupper() for c in password)
        has_lower = any(c.islower() for c in password)
        has_digit = any(c.isdigit() for c in password)
        has_special = any(c in "!@#$%^&*()_+-=[]{}|;:,.<>?" for c in password)
        
        return has_upper and has_lower and has_digit and has_special
    
    async def create_user(self, username: str, email: str, password: str, 
                         roles: List[UserRole], created_by: str) -> str:
        """Create new user account"""
        try:
            # Validate password complexity
            if not self._validate_password_complexity(password):
                raise ValueError("Password does not meet complexity requirements")
            
            # Check if user already exists
            if self._user_exists(username, email):
                raise ValueError("User already exists with this username or email")
            
            user_id = str(uuid.uuid4())
            password_hash = self._hash_password(password)
            
            # Set password expiry
            password_expires_at = None
            if self.config.get('password_expiry_days', 0) > 0:
                password_expires_at = datetime.datetime.utcnow() + datetime.timedelta(
                    days=self.config['password_expiry_days']
                )
            
            user = User(
                user_id=user_id,
                username=username,
                email=email,
                password_hash=password_hash,
                roles=roles,
                is_active=True,
                is_locked=False,
                created_at=datetime.datetime.utcnow(),
                password_expires_at=password_expires_at
            )
            
            # Store user in database
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO users (
                    user_id, username, email, password_hash, roles,
                    is_active, is_locked, created_at, password_expires_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                user.user_id,
                user.username,
                user.email,
                user.password_hash,
                json.dumps([role.value for role in user.roles]),
                user.is_active,
                user.is_locked,
                user.created_at.isoformat(),
                user.password_expires_at.isoformat() if user.password_expires_at else None
            ))
            
            conn.commit()
            conn.close()
            
            # Log user creation
            await self._log_access_attempt(
                user_id=user_id,
                username=username,
                action="user_created",
                resource=f"user:{user_id}",
                ip_address="system",
                user_agent="system",
                success=True
            )
            
            logger.info(f"User created: {username} by {created_by}")
            return user_id
            
        except Exception as e:
            logger.error(f"Failed to create user {username}: {e}")
            raise
    
    async def authenticate_user(self, username: str, password: str, 
                              ip_address: str, user_agent: str, 
                              mfa_token: Optional[str] = None) -> Optional[str]:
        """Authenticate user and create session"""
        try:
            # Get user from database
            user = self._get_user_by_username(username)
            if not user:
                await self._log_access_attempt(
                    user_id=None,
                    username=username,
                    action="login_attempt",
                    resource="authentication",
                    ip_address=ip_address,
                    user_agent=user_agent,
                    success=False,
                    failure_reason="user_not_found"
                )
                return None
            
            # Check if user is active and not locked
            if not user.is_active or user.is_locked:
                await self._log_access_attempt(
                    user_id=user.user_id,
                    username=username,
                    action="login_attempt",
                    resource="authentication",
                    ip_address=ip_address,
                    user_agent=user_agent,
                    success=False,
                    failure_reason="account_locked_or_inactive"
                )
                return None
            
            # Verify password
            if not self._verify_password(password, user.password_hash):
                await self._handle_failed_login(user.user_id, ip_address, user_agent)
                return None
            
            # Check MFA if enabled
            mfa_verified = True
            if user.mfa_enabled:
                if not mfa_token:
                    await self._log_access_attempt(
                        user_id=user.user_id,
                        username=username,
                        action="login_attempt",
                        resource="authentication",
                        ip_address=ip_address,
                        user_agent=user_agent,
                        success=False,
                        failure_reason="mfa_token_required"
                    )
                    return None
                
                mfa_verified = self._verify_mfa_token(user.mfa_secret, mfa_token)
                if not mfa_verified:
                    await self._log_access_attempt(
                        user_id=user.user_id,
                        username=username,
                        action="login_attempt",
                        resource="authentication",
                        ip_address=ip_address,
                        user_agent=user_agent,
                        success=False,
                        failure_reason="invalid_mfa_token"
                    )
                    return None
            
            # Create session
            session_id = await self._create_session(
                user.user_id, ip_address, user_agent, mfa_verified
            )
            
            # Update last login and reset failed attempts
            await self._update_user_login(user.user_id)
            
            # Log successful authentication
            await self._log_access_attempt(
                user_id=user.user_id,
                username=username,
                action="login_success",
                resource="authentication",
                ip_address=ip_address,
                user_agent=user_agent,
                success=True
            )
            
            logger.info(f"User authenticated: {username} from {ip_address}")
            return session_id
            
        except Exception as e:
            logger.error(f"Authentication failed for {username}: {e}")
            return None
    
    async def authorize_action(self, session_id: str, permission: Permission, 
                             resource: str) -> bool:
        """Authorize user action based on permissions"""
        try:
            # Validate session
            session = self._get_session(session_id)
            if not session or session.status != SessionStatus.ACTIVE:
                return False
            
            # Check session expiry
            if datetime.datetime.utcnow() > session.expires_at:
                await self._expire_session(session_id)
                return False
            
            # Get user and roles
            user = self._get_user_by_id(session.user_id)
            if not user or not user.is_active or user.is_locked:
                return False
            
            # Check if user has required permission
            has_permission = await self._user_has_permission(user.user_id, permission)
            
            # Log authorization attempt
            await self._log_access_attempt(
                user_id=user.user_id,
                username=user.username,
                action=f"authorize_{permission.value}",
                resource=resource,
                ip_address=session.ip_address,
                user_agent=session.user_agent,
                success=has_permission,
                failure_reason=None if has_permission else "insufficient_permissions"
            )
            
            # Update session activity
            if has_permission:
                await self._update_session_activity(session_id)
            
            return has_permission
            
        except Exception as e:
            logger.error(f"Authorization failed for session {session_id}: {e}")
            return False
    
    async def enable_mfa(self, user_id: str) -> Dict[str, Any]:
        """Enable multi-factor authentication for user"""
        try:
            user = self._get_user_by_id(user_id)
            if not user:
                raise ValueError("User not found")
            
            if user.mfa_enabled:
                raise ValueError("MFA already enabled for this user")
            
            # Generate MFA secret
            mfa_secret = pyotp.random_base32()
            
            # Create TOTP instance
            totp = pyotp.TOTP(mfa_secret)
            
            # Generate QR code for setup
            provisioning_uri = totp.provisioning_uri(
                name=user.email,
                issuer_name="PyAirtable Security"
            )
            
            # Store encrypted MFA secret
            encrypted_secret = self._encrypt_sensitive_data(mfa_secret)
            
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute(
                'UPDATE users SET mfa_secret = ? WHERE user_id = ?',
                (encrypted_secret, user_id)
            )
            
            conn.commit()
            conn.close()
            
            # Generate QR code
            qr = qrcode.QRCode(version=1, box_size=10, border=5)
            qr.add_data(provisioning_uri)
            qr.make(fit=True)
            
            logger.info(f"MFA setup initiated for user: {user.username}")
            
            return {
                "secret": mfa_secret,
                "qr_code_uri": provisioning_uri,
                "backup_codes": self._generate_backup_codes(user_id)
            }
            
        except Exception as e:
            logger.error(f"Failed to enable MFA for user {user_id}: {e}")
            raise
    
    async def verify_mfa_setup(self, user_id: str, token: str) -> bool:
        """Verify MFA setup with provided token"""
        try:
            user = self._get_user_by_id(user_id)
            if not user or not user.mfa_secret:
                return False
            
            # Decrypt MFA secret
            mfa_secret = self._decrypt_sensitive_data(user.mfa_secret)
            
            # Verify token
            if self._verify_mfa_token(mfa_secret, token):
                # Enable MFA
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                
                cursor.execute(
                    'UPDATE users SET mfa_enabled = TRUE WHERE user_id = ?',
                    (user_id,)
                )
                
                conn.commit()
                conn.close()
                
                logger.info(f"MFA enabled for user: {user.username}")
                return True
            
            return False
            
        except Exception as e:
            logger.error(f"Failed to verify MFA setup for user {user_id}: {e}")
            return False
    
    def _verify_mfa_token(self, secret: str, token: str) -> bool:
        """Verify TOTP token"""
        try:
            totp = pyotp.TOTP(secret)
            return totp.verify(token, valid_window=1)
        except Exception:
            return False
    
    async def generate_security_report(self, 
                                     start_date: datetime.datetime,
                                     end_date: datetime.datetime) -> Dict[str, Any]:
        """Generate comprehensive security report"""
        try:
            conn = sqlite3.connect(self.db_path)
            
            # Get access logs in date range
            logs_df = pd.read_sql_query('''
                SELECT * FROM access_logs 
                WHERE timestamp BETWEEN ? AND ?
            ''', conn, params=[start_date.isoformat(), end_date.isoformat()])
            
            # Get user statistics
            users_df = pd.read_sql_query('SELECT * FROM users', conn)
            
            # Get session statistics
            sessions_df = pd.read_sql_query('''
                SELECT * FROM sessions 
                WHERE created_at BETWEEN ? AND ?
            ''', conn, params=[start_date.isoformat(), end_date.isoformat()])
            
            conn.close()
            
            report = {
                "report_period": {
                    "start": start_date.isoformat(),
                    "end": end_date.isoformat()
                },
                "user_statistics": {
                    "total_users": len(users_df),
                    "active_users": len(users_df[users_df['is_active'] == True]),
                    "locked_users": len(users_df[users_df['is_locked'] == True]),
                    "mfa_enabled_users": len(users_df[users_df['mfa_enabled'] == True]),
                    "users_by_role": users_df['roles'].value_counts().to_dict() if len(users_df) > 0 else {}
                },
                "access_statistics": {
                    "total_access_attempts": len(logs_df),
                    "successful_logins": len(logs_df[(logs_df['action'] == 'login_success') & (logs_df['success'] == True)]),
                    "failed_logins": len(logs_df[(logs_df['action'] == 'login_attempt') & (logs_df['success'] == False)]),
                    "authorization_attempts": len(logs_df[logs_df['action'].str.startswith('authorize_')]),
                    "top_accessed_resources": logs_df['resource'].value_counts().head(10).to_dict() if len(logs_df) > 0 else {}
                },
                "session_statistics": {
                    "total_sessions": len(sessions_df),
                    "active_sessions": len(sessions_df[sessions_df['status'] == 'active']),
                    "average_session_duration": self._calculate_average_session_duration(sessions_df),
                    "sessions_by_status": sessions_df['status'].value_counts().to_dict() if len(sessions_df) > 0 else {}
                },
                "security_metrics": self._calculate_security_metrics(logs_df, users_df, sessions_df)
            }
            
            return report
            
        except Exception as e:
            logger.error(f"Failed to generate security report: {e}")
            raise

async def main():
    """Main execution function for testing"""
    rbac = RBACFramework()
    
    # Example: Create a user
    try:
        user_id = await rbac.create_user(
            username="testuser",
            email="test@example.com",
            password="SecurePassword123!",
            roles=[UserRole.USER],
            created_by="system"
        )
        print(f"User created: {user_id}")
    except Exception as e:
        print(f"User creation failed: {e}")
    
    # Example: Authenticate user
    try:
        session_id = await rbac.authenticate_user(
            username="testuser",
            password="SecurePassword123!",
            ip_address="127.0.0.1",
            user_agent="Test Client"
        )
        if session_id:
            print(f"Authentication successful: {session_id}")
        else:
            print("Authentication failed")
    except Exception as e:
        print(f"Authentication error: {e}")

if __name__ == "__main__":
    asyncio.run(main())