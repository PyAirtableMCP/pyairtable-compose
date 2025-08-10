#!/usr/bin/env python3

"""
JWT Token Rotation Service

SECURITY NOTICE: This service implements JWT token rotation and blacklisting
to enhance authentication security and meet OWASP recommendations.

DESCRIPTION:
  - Implements JWT token rotation with refresh tokens
  - Maintains token blacklist for revoked tokens
  - Provides secure token validation and renewal
  - Supports multiple signing algorithms
  - Redis-backed for high-performance token storage

OWASP COMPLIANCE:
  - A02:2021 – Cryptographic Failures (secure token handling)
  - A07:2021 – Identification and Authentication Failures (token rotation)
  - A04:2021 – Insecure Design (secure authentication flow)
"""

import os
import jwt
import redis
import json
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Dict, Optional, Tuple, List
import logging
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.backends import default_backend
import base64

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class JWTRotationService:
    """
    Secure JWT Token Rotation Service
    
    Implements token rotation, blacklisting, and refresh token management
    following OWASP security best practices.
    """
    
    def __init__(self):
        # Configuration from environment
        self.jwt_secret = os.getenv('JWT_SECRET')
        self.jwt_refresh_secret = os.getenv('JWT_REFRESH_SECRET')
        self.jwt_algorithm = os.getenv('JWT_ALGORITHM', 'HS256')
        self.jwt_issuer = os.getenv('JWT_ISSUER', 'pyairtable-platform')
        self.jwt_audience = os.getenv('JWT_AUDIENCE', 'pyairtable-api')
        
        # Token expiration times (in seconds)
        self.access_token_expiration = int(os.getenv('JWT_ACCESS_TOKEN_EXPIRATION', 900))  # 15 minutes
        self.refresh_token_expiration = int(os.getenv('JWT_REFRESH_TOKEN_EXPIRATION', 604800))  # 7 days
        
        # Rotation configuration
        self.rotation_enabled = os.getenv('JWT_ROTATION_ENABLED', 'true').lower() == 'true'
        self.rotation_threshold = int(os.getenv('JWT_ROTATION_THRESHOLD', 300))  # 5 minutes before expiry
        self.blacklist_enabled = os.getenv('JWT_BLACKLIST_ENABLED', 'true').lower() == 'true'
        
        # Security validation
        if not self.jwt_secret or len(self.jwt_secret) < 64:
            raise ValueError("JWT_SECRET must be at least 64 characters (512 bits)")
        
        if not self.jwt_refresh_secret or len(self.jwt_refresh_secret) < 64:
            raise ValueError("JWT_REFRESH_SECRET must be at least 64 characters (512 bits)")
        
        # Redis connection for token storage
        self.redis_client = self._init_redis_connection()
        
        logger.info("JWT Rotation Service initialized with enhanced security")
    
    def _init_redis_connection(self) -> redis.Redis:
        """Initialize secure Redis connection for token storage."""
        redis_url = os.getenv('REDIS_URL', 'redis://localhost:6379/0')
        redis_password = os.getenv('REDIS_PASSWORD')
        
        try:
            client = redis.from_url(
                redis_url,
                password=redis_password,
                socket_keepalive=True,
                socket_keepalive_options={},
                decode_responses=True,
                ssl_cert_reqs=None  # Set to 'required' in production with SSL
            )
            
            # Test connection
            client.ping()
            logger.info("Redis connection established successfully")
            return client
            
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            raise
    
    def generate_token_pair(self, user_id: str, user_data: Dict) -> Tuple[str, str]:
        """
        Generate access and refresh token pair.
        
        Args:
            user_id: Unique user identifier
            user_data: Additional user claims
            
        Returns:
            Tuple of (access_token, refresh_token)
        """
        now = datetime.now(timezone.utc)
        
        # Generate unique token ID for tracking
        token_id = secrets.token_urlsafe(32)
        refresh_token_id = secrets.token_urlsafe(32)
        
        # Access token payload
        access_payload = {
            'sub': user_id,
            'iss': self.jwt_issuer,
            'aud': self.jwt_audience,
            'iat': now.timestamp(),
            'exp': (now + timedelta(seconds=self.access_token_expiration)).timestamp(),
            'jti': token_id,
            'type': 'access',
            'data': user_data
        }
        
        # Refresh token payload
        refresh_payload = {
            'sub': user_id,
            'iss': self.jwt_issuer,
            'aud': self.jwt_audience,
            'iat': now.timestamp(),
            'exp': (now + timedelta(seconds=self.refresh_token_expiration)).timestamp(),
            'jti': refresh_token_id,
            'type': 'refresh',
            'access_jti': token_id
        }
        
        # Sign tokens
        access_token = jwt.encode(access_payload, self.jwt_secret, algorithm=self.jwt_algorithm)
        refresh_token = jwt.encode(refresh_payload, self.jwt_refresh_secret, algorithm=self.jwt_algorithm)
        
        # Store token metadata in Redis
        self._store_token_metadata(token_id, user_id, access_payload['exp'])
        self._store_refresh_token_metadata(refresh_token_id, user_id, token_id, refresh_payload['exp'])
        
        logger.info(f"Generated token pair for user {user_id}")
        return access_token, refresh_token
    
    def validate_access_token(self, token: str) -> Optional[Dict]:
        """
        Validate access token and check blacklist.
        
        Args:
            token: JWT access token to validate
            
        Returns:
            Token payload if valid, None otherwise
        """
        try:
            # Decode and verify token
            payload = jwt.decode(
                token,
                self.jwt_secret,
                algorithms=[self.jwt_algorithm],
                issuer=self.jwt_issuer,
                audience=self.jwt_audience,
                options={
                    'verify_exp': True,
                    'verify_iat': True,
                    'verify_signature': True
                }
            )
            
            # Check token type
            if payload.get('type') != 'access':
                logger.warning(f"Invalid token type: {payload.get('type')}")
                return None
            
            # Check blacklist
            if self.blacklist_enabled and self._is_token_blacklisted(payload['jti']):
                logger.warning(f"Token {payload['jti']} is blacklisted")
                return None
            
            # Check if token needs rotation
            if self.rotation_enabled and self._should_rotate_token(payload['exp']):
                payload['needs_rotation'] = True
            
            return payload
            
        except jwt.ExpiredSignatureError:
            logger.warning("Token has expired")
            return None
        except jwt.InvalidTokenError as e:
            logger.warning(f"Invalid token: {e}")
            return None
        except Exception as e:
            logger.error(f"Token validation error: {e}")
            return None
    
    def refresh_token_pair(self, refresh_token: str) -> Optional[Tuple[str, str]]:
        """
        Generate new token pair using refresh token.
        
        Args:
            refresh_token: Valid refresh token
            
        Returns:
            New (access_token, refresh_token) pair or None if invalid
        """
        try:
            # Validate refresh token
            payload = jwt.decode(
                refresh_token,
                self.jwt_refresh_secret,
                algorithms=[self.jwt_algorithm],
                issuer=self.jwt_issuer,
                audience=self.jwt_audience
            )
            
            if payload.get('type') != 'refresh':
                logger.warning("Invalid refresh token type")
                return None
            
            # Check if refresh token is blacklisted
            if self.blacklist_enabled and self._is_token_blacklisted(payload['jti']):
                logger.warning("Refresh token is blacklisted")
                return None
            
            user_id = payload['sub']
            
            # Blacklist old tokens
            if self.blacklist_enabled:
                self._blacklist_token(payload['jti'])  # Blacklist refresh token
                if 'access_jti' in payload:
                    self._blacklist_token(payload['access_jti'])  # Blacklist associated access token
            
            # Get user data from stored metadata
            user_data = self._get_user_data_from_storage(user_id)
            
            # Generate new token pair
            new_access_token, new_refresh_token = self.generate_token_pair(user_id, user_data)
            
            logger.info(f"Refreshed token pair for user {user_id}")
            return new_access_token, new_refresh_token
            
        except jwt.ExpiredSignatureError:
            logger.warning("Refresh token has expired")
            return None
        except jwt.InvalidTokenError as e:
            logger.warning(f"Invalid refresh token: {e}")
            return None
        except Exception as e:
            logger.error(f"Token refresh error: {e}")
            return None
    
    def revoke_token(self, token: str) -> bool:
        """
        Revoke a token by adding it to blacklist.
        
        Args:
            token: Token to revoke
            
        Returns:
            True if successfully revoked
        """
        try:
            payload = jwt.decode(
                token,
                self.jwt_secret if 'access' in token else self.jwt_refresh_secret,
                algorithms=[self.jwt_algorithm],
                options={'verify_exp': False}  # Allow expired tokens to be revoked
            )
            
            self._blacklist_token(payload['jti'])
            logger.info(f"Revoked token {payload['jti']}")
            return True
            
        except Exception as e:
            logger.error(f"Token revocation error: {e}")
            return False
    
    def revoke_all_user_tokens(self, user_id: str) -> bool:
        """
        Revoke all tokens for a specific user.
        
        Args:
            user_id: User identifier
            
        Returns:
            True if successfully revoked
        """
        try:
            # Get all tokens for user from Redis
            user_tokens = self._get_user_tokens(user_id)
            
            for token_id in user_tokens:
                self._blacklist_token(token_id)
            
            logger.info(f"Revoked all tokens for user {user_id}")
            return True
            
        except Exception as e:
            logger.error(f"User token revocation error: {e}")
            return False
    
    def _store_token_metadata(self, token_id: str, user_id: str, expiry: float):
        """Store token metadata in Redis."""
        metadata = {
            'user_id': user_id,
            'issued_at': datetime.now(timezone.utc).isoformat(),
            'expires_at': datetime.fromtimestamp(expiry, timezone.utc).isoformat()
        }
        
        # Store with expiration matching token
        ttl = int(expiry - datetime.now(timezone.utc).timestamp())
        if ttl > 0:
            self.redis_client.setex(f"token:{token_id}", ttl, json.dumps(metadata))
            self.redis_client.sadd(f"user_tokens:{user_id}", token_id)
            self.redis_client.expire(f"user_tokens:{user_id}", ttl)
    
    def _store_refresh_token_metadata(self, refresh_token_id: str, user_id: str, 
                                    access_token_id: str, expiry: float):
        """Store refresh token metadata in Redis."""
        metadata = {
            'user_id': user_id,
            'access_token_id': access_token_id,
            'issued_at': datetime.now(timezone.utc).isoformat(),
            'expires_at': datetime.fromtimestamp(expiry, timezone.utc).isoformat()
        }
        
        ttl = int(expiry - datetime.now(timezone.utc).timestamp())
        if ttl > 0:
            self.redis_client.setex(f"refresh_token:{refresh_token_id}", ttl, json.dumps(metadata))
    
    def _is_token_blacklisted(self, token_id: str) -> bool:
        """Check if token is blacklisted."""
        return self.redis_client.sismember("blacklisted_tokens", token_id)
    
    def _blacklist_token(self, token_id: str):
        """Add token to blacklist."""
        self.redis_client.sadd("blacklisted_tokens", token_id)
        # Set expiration for blacklist cleanup (same as max token expiration)
        self.redis_client.expire("blacklisted_tokens", self.refresh_token_expiration)
    
    def _should_rotate_token(self, exp: float) -> bool:
        """Check if token should be rotated based on expiration threshold."""
        time_until_expiry = exp - datetime.now(timezone.utc).timestamp()
        return time_until_expiry <= self.rotation_threshold
    
    def _get_user_tokens(self, user_id: str) -> List[str]:
        """Get all active tokens for a user."""
        return list(self.redis_client.smembers(f"user_tokens:{user_id}"))
    
    def _get_user_data_from_storage(self, user_id: str) -> Dict:
        """Retrieve user data from storage (implement based on your user store)."""
        # This should integrate with your user management system
        # For now, return basic user data
        return {
            'user_id': user_id,
            'roles': ['user'],  # Default role
            'permissions': []
        }
    
    def get_token_statistics(self) -> Dict:
        """Get token usage statistics for monitoring."""
        try:
            stats = {
                'total_blacklisted_tokens': self.redis_client.scard("blacklisted_tokens"),
                'active_sessions': 0,
                'total_users_with_tokens': 0
            }
            
            # Count active sessions and users
            for key in self.redis_client.scan_iter(match="user_tokens:*"):
                stats['total_users_with_tokens'] += 1
                stats['active_sessions'] += self.redis_client.scard(key)
            
            return stats
            
        except Exception as e:
            logger.error(f"Failed to get token statistics: {e}")
            return {}
    
    def cleanup_expired_tokens(self):
        """Clean up expired token metadata (run periodically)."""
        try:
            # Redis automatically handles key expiration, but we can clean up user token sets
            for key in self.redis_client.scan_iter(match="user_tokens:*"):
                # Remove expired token IDs from user sets
                token_ids = self.redis_client.smembers(key)
                for token_id in token_ids:
                    if not self.redis_client.exists(f"token:{token_id}"):
                        self.redis_client.srem(key, token_id)
            
            logger.info("Completed token cleanup")
            
        except Exception as e:
            logger.error(f"Token cleanup error: {e}")


# Example usage and testing
if __name__ == "__main__":
    # Initialize service
    service = JWTRotationService()
    
    # Example: Generate token pair
    user_id = "user123"
    user_data = {"email": "user@example.com", "roles": ["user"]}
    
    access_token, refresh_token = service.generate_token_pair(user_id, user_data)
    print(f"Access Token: {access_token[:50]}...")
    print(f"Refresh Token: {refresh_token[:50]}...")
    
    # Validate access token
    payload = service.validate_access_token(access_token)
    if payload:
        print(f"Token valid for user: {payload['sub']}")
    
    # Test token refresh
    new_access, new_refresh = service.refresh_token_pair(refresh_token)
    if new_access and new_refresh:
        print("Token pair refreshed successfully")
    
    # Get statistics
    stats = service.get_token_statistics()
    print(f"Token Statistics: {stats}")