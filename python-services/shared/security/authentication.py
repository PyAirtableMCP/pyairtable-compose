"""
Authentication and Authorization Security
Enterprise-grade authentication with JWT and API key support
"""

import os
import time
import logging
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
import jwt
import bcrypt
from fastapi import HTTPException, Security, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials, APIKeyHeader
from pydantic import BaseModel
import redis.asyncio as redis

logger = logging.getLogger(__name__)

class SecurityContext(BaseModel):
    """Security context for authenticated requests"""
    user_id: str
    email: str
    role: str
    tenant_id: Optional[str] = None
    permissions: List[str] = []
    session_id: Optional[str] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    authenticated_at: datetime
    expires_at: datetime

class JWTAuthenticator:
    """JWT Token authentication and validation"""
    
    def __init__(self, 
                 secret_key: str,
                 algorithm: str = "HS256",
                 access_token_expire_minutes: int = 30,
                 refresh_token_expire_days: int = 7,
                 redis_client=None):
        self.secret_key = secret_key
        self.algorithm = algorithm
        self.access_token_expire_minutes = access_token_expire_minutes
        self.refresh_token_expire_days = refresh_token_expire_days
        self.redis_client = redis_client
        
        # Validate algorithm (prevent algorithm confusion attacks)
        if algorithm not in ["HS256", "HS384", "HS512"]:
            raise ValueError(f"Unsupported JWT algorithm: {algorithm}")
    
    def create_access_token(self, 
                           user_id: str,
                           email: str,
                           role: str,
                           tenant_id: Optional[str] = None,
                           permissions: List[str] = None,
                           additional_claims: Dict[str, Any] = None) -> str:
        """
        Create a secure JWT access token
        """
        now = datetime.utcnow()
        expire = now + timedelta(minutes=self.access_token_expire_minutes)
        
        payload = {
            "sub": user_id,
            "email": email,
            "role": role,
            "tenant_id": tenant_id,
            "permissions": permissions or [],
            "iat": int(now.timestamp()),
            "exp": int(expire.timestamp()),
            "nbf": int(now.timestamp()),  # Not before
            "iss": "pyairtable-auth",      # Issuer
            "aud": "pyairtable-api",       # Audience
            "type": "access"
        }
        
        # Add any additional claims
        if additional_claims:
            payload.update(additional_claims)
        
        try:
            token = jwt.encode(payload, self.secret_key, algorithm=self.algorithm)
            logger.debug(f"Created access token for user {user_id}")
            return token
        except Exception as e:
            logger.error(f"Failed to create access token: {str(e)}")
            raise HTTPException(status_code=500, detail="Token creation failed")
    
    def create_refresh_token(self, 
                            user_id: str,
                            session_id: str) -> str:
        """
        Create a refresh token for token renewal
        """
        now = datetime.utcnow()
        expire = now + timedelta(days=self.refresh_token_expire_days)
        
        payload = {
            "sub": user_id,
            "session_id": session_id,
            "iat": int(now.timestamp()),
            "exp": int(expire.timestamp()),
            "iss": "pyairtable-auth",
            "aud": "pyairtable-api",
            "type": "refresh"
        }
        
        try:
            token = jwt.encode(payload, self.secret_key, algorithm=self.algorithm)
            
            # Store refresh token in Redis for revocation tracking
            if self.redis_client:
                try:
                    redis_key = f"refresh_token:{user_id}:{session_id}"
                    expire_seconds = int(expire.timestamp() - now.timestamp())
                    await self.redis_client.setex(redis_key, expire_seconds, token)
                except Exception as redis_error:
                    logger.warning(f"Failed to store refresh token in Redis: {redis_error}")
            
            return token
        except Exception as e:
            logger.error(f"Failed to create refresh token: {str(e)}")
            raise HTTPException(status_code=500, detail="Token creation failed")
    
    async def validate_token(self, token: str, expected_type: str = "access") -> SecurityContext:
        """
        Validate and decode JWT token with comprehensive security checks
        """
        try:
            # Decode token with strict validation
            payload = jwt.decode(
                token,
                self.secret_key,
                algorithms=[self.algorithm],  # Explicitly specify allowed algorithms
                verify=True,
                options={
                    "verify_signature": True,
                    "verify_exp": True,
                    "verify_nbf": True,
                    "verify_iat": True,
                    "verify_aud": True,
                    "verify_iss": True,
                    "require": ["exp", "iat", "sub", "iss", "aud", "type"]
                },
                audience="pyairtable-api",
                issuer="pyairtable-auth"
            )
            
            # Verify token type
            if payload.get("type") != expected_type:
                raise HTTPException(status_code=401, detail=f"Invalid token type. Expected: {expected_type}")
            
            # Check if token is blacklisted (if Redis is available)
            if self.redis_client:
                try:
                    blacklist_key = f"blacklisted_token:{payload['sub']}:{payload['iat']}"
                    is_blacklisted = await self.redis_client.exists(blacklist_key)
                    if is_blacklisted:
                        raise HTTPException(status_code=401, detail="Token has been revoked")
                except Exception as redis_error:
                    logger.warning(f"Failed to check token blacklist: {redis_error}")
            
            # Create security context
            context = SecurityContext(
                user_id=payload["sub"],
                email=payload.get("email", ""),
                role=payload.get("role", "user"),
                tenant_id=payload.get("tenant_id"),
                permissions=payload.get("permissions", []),
                session_id=payload.get("session_id"),
                authenticated_at=datetime.fromtimestamp(payload["iat"]),
                expires_at=datetime.fromtimestamp(payload["exp"])
            )
            
            logger.debug(f"Token validated successfully for user {context.user_id}")
            return context
            
        except jwt.ExpiredSignatureError:
            raise HTTPException(status_code=401, detail="Token has expired")
        except jwt.InvalidTokenError as e:
            logger.warning(f"Invalid token: {str(e)}")
            raise HTTPException(status_code=401, detail="Invalid token")
        except Exception as e:
            logger.error(f"Token validation failed: {str(e)}")
            raise HTTPException(status_code=401, detail="Token validation failed")
    
    async def revoke_token(self, user_id: str, iat: int) -> bool:
        """
        Add token to blacklist for revocation
        """
        if not self.redis_client:
            logger.warning("Redis client not available for token revocation")
            return False
            
        try:
            blacklist_key = f"blacklisted_token:{user_id}:{iat}"
            # Set blacklist entry to expire after access token lifetime
            expire_seconds = self.access_token_expire_minutes * 60
            await self.redis_client.setex(blacklist_key, expire_seconds, "revoked")
            logger.info(f"Token revoked for user {user_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to revoke token: {str(e)}")
            return False
    
    async def revoke_all_tokens(self, user_id: str) -> bool:
        """
        Revoke all tokens for a user
        """
        if not self.redis_client:
            logger.warning("Redis client not available for token revocation")
            return False
            
        try:
            # Add user to global revocation list
            revocation_key = f"user_revoked:{user_id}"
            expire_seconds = max(
                self.access_token_expire_minutes * 60,
                self.refresh_token_expire_days * 24 * 60 * 60
            )
            await self.redis_client.setex(revocation_key, expire_seconds, str(int(time.time())))
            logger.info(f"All tokens revoked for user {user_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to revoke all tokens: {str(e)}")
            return False

class APIKeyAuthenticator:
    """API Key authentication for service-to-service communication"""
    
    def __init__(self, valid_api_keys: Dict[str, Dict[str, Any]], redis_client=None):
        """
        Initialize API Key authenticator
        
        Args:
            valid_api_keys: Dictionary mapping API keys to their metadata
            redis_client: Redis client for rate limiting and logging
        """
        self.valid_api_keys = valid_api_keys
        self.redis_client = redis_client
    
    async def validate_api_key(self, api_key: str, ip_address: str = None) -> SecurityContext:
        """
        Validate API key and return security context
        """
        if not api_key:
            raise HTTPException(status_code=401, detail="API key required")
        
        if api_key not in self.valid_api_keys:
            logger.warning(f"Invalid API key attempted from IP: {ip_address}")
            raise HTTPException(status_code=401, detail="Invalid API key")
        
        key_info = self.valid_api_keys[api_key]
        
        # Check if key is disabled
        if not key_info.get("enabled", True):
            raise HTTPException(status_code=401, detail="API key disabled")
        
        # Check expiration
        if key_info.get("expires_at"):
            if datetime.fromisoformat(key_info["expires_at"]) < datetime.utcnow():
                raise HTTPException(status_code=401, detail="API key expired")
        
        # Log API key usage
        if self.redis_client:
            try:
                usage_key = f"api_key_usage:{api_key}:{datetime.utcnow().strftime('%Y%m%d%H')}"
                await self.redis_client.incr(usage_key)
                await self.redis_client.expire(usage_key, 86400)  # 24 hours
            except Exception as e:
                logger.warning(f"Failed to log API key usage: {str(e)}")
        
        # Create security context
        context = SecurityContext(
            user_id=key_info.get("service_name", "api_service"),
            email=key_info.get("contact_email", ""),
            role=key_info.get("role", "service"),
            permissions=key_info.get("permissions", []),
            ip_address=ip_address,
            authenticated_at=datetime.utcnow(),
            expires_at=datetime.utcnow() + timedelta(hours=1)  # API key sessions last 1 hour
        )
        
        logger.debug(f"API key validated for service: {context.user_id}")
        return context

class PasswordHasher:
    """Secure password hashing utility"""
    
    @staticmethod
    def hash_password(password: str) -> str:
        """
        Hash password using bcrypt with secure defaults
        """
        if not password:
            raise ValueError("Password cannot be empty")
        
        # Use high cost factor for security (12 rounds = ~250ms on modern CPU)
        salt = bcrypt.gensalt(rounds=12)
        hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
        return hashed.decode('utf-8')
    
    @staticmethod
    def verify_password(password: str, hashed_password: str) -> bool:
        """
        Verify password against hash
        """
        if not password or not hashed_password:
            return False
        
        try:
            return bcrypt.checkpw(password.encode('utf-8'), hashed_password.encode('utf-8'))
        except Exception as e:
            logger.error(f"Password verification failed: {str(e)}")
            return False

# FastAPI dependency functions
security = HTTPBearer()
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

# Global authenticator instances (to be initialized by each service)
jwt_authenticator: Optional[JWTAuthenticator] = None
api_key_authenticator: Optional[APIKeyAuthenticator] = None

def initialize_authenticators(
    jwt_secret: str,
    api_keys: Dict[str, Dict[str, Any]] = None,
    redis_client=None
) -> None:
    """Initialize global authenticator instances"""
    global jwt_authenticator, api_key_authenticator
    
    jwt_authenticator = JWTAuthenticator(jwt_secret, redis_client=redis_client)
    
    if api_keys:
        api_key_authenticator = APIKeyAuthenticator(api_keys, redis_client=redis_client)

async def get_current_user(credentials: HTTPAuthorizationCredentials = Security(security)) -> SecurityContext:
    """
    FastAPI dependency to get current authenticated user
    """
    if not jwt_authenticator:
        raise HTTPException(status_code=500, detail="Authentication not initialized")
    
    if not credentials:
        raise HTTPException(status_code=401, detail="Authentication required")
    
    return await jwt_authenticator.validate_token(credentials.credentials)

async def get_api_key_user(api_key: str = Security(api_key_header)) -> SecurityContext:
    """
    FastAPI dependency to authenticate via API key
    """
    if not api_key_authenticator:
        raise HTTPException(status_code=500, detail="API key authentication not initialized")
    
    if not api_key:
        raise HTTPException(status_code=401, detail="API key required")
    
    return await api_key_authenticator.validate_api_key(api_key)

def require_permission(permission: str):
    """
    FastAPI dependency factory to require specific permission
    """
    def permission_checker(user: SecurityContext = Depends(get_current_user)) -> SecurityContext:
        if permission not in user.permissions and user.role != "admin":
            raise HTTPException(status_code=403, detail=f"Permission required: {permission}")
        return user
    
    return permission_checker

def require_role(role: str):
    """
    FastAPI dependency factory to require specific role
    """
    def role_checker(user: SecurityContext = Depends(get_current_user)) -> SecurityContext:
        if user.role != role and user.role != "admin":
            raise HTTPException(status_code=403, detail=f"Role required: {role}")
        return user
    
    return role_checker

def optional_auth(credentials: HTTPAuthorizationCredentials = Security(security, auto_error=False)) -> Optional[SecurityContext]:
    """
    Optional authentication dependency
    """
    if not credentials or not jwt_authenticator:
        return None
    
    try:
        return jwt_authenticator.validate_token(credentials.credentials)
    except HTTPException:
        return None