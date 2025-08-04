"""Authentication and authorization middleware."""

import uuid
from typing import Optional

from fastapi import Request, Response, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from starlette.middleware.base import BaseHTTPMiddleware

from ..core.logging import get_logger

logger = get_logger(__name__)

security = HTTPBearer(auto_error=False)


class AuthenticationMiddleware(BaseHTTPMiddleware):
    """Middleware for handling authentication and authorization."""
    
    def __init__(
        self,
        app,
        internal_api_key: str = "",
        jwt_secret_key: str = "",
        jwt_algorithm: str = "HS256",
    ):
        super().__init__(app)
        self.internal_api_key = internal_api_key
        self.jwt_secret_key = jwt_secret_key
        self.jwt_algorithm = jwt_algorithm
        
        # Public endpoints that don't require authentication
        self.public_endpoints = {
            "/",
            "/health",
            "/health/detailed", 
            "/ready",
            "/live",
            "/docs",
            "/redoc",
            "/openapi.json",
            "/metrics",
        }
    
    async def dispatch(self, request: Request, call_next) -> Response:
        """Process authentication for each request."""
        
        # Generate request ID for tracing
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id
        
        # Skip authentication for public endpoints
        if self._is_public_endpoint(request.url.path):
            response = await call_next(request)
            response.headers["X-Request-ID"] = request_id
            return response
        
        # Extract authentication info
        auth_result = await self._authenticate_request(request)
        
        if auth_result["authenticated"]:
            request.state.user_id = auth_result.get("user_id")
            request.state.user_roles = auth_result.get("roles", [])
            request.state.auth_type = auth_result.get("auth_type")
        else:
            # For now, we'll allow unauthenticated requests but log them
            logger.warning(
                "Unauthenticated request",
                path=request.url.path,
                method=request.method,
                request_id=request_id,
                error=auth_result.get("error")
            )
            request.state.user_id = None
            request.state.user_roles = []
            request.state.auth_type = None
        
        # Process request
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        
        return response
    
    def _is_public_endpoint(self, path: str) -> bool:
        """Check if endpoint is public."""
        # Remove trailing slash
        path = path.rstrip("/")
        
        # Check exact matches
        if path in self.public_endpoints:
            return True
        
        # Check path prefixes
        public_prefixes = ["/health", "/metrics"]
        for prefix in public_prefixes:
            if path.startswith(prefix):
                return True
        
        return False
    
    async def _authenticate_request(self, request: Request) -> dict:
        """Authenticate the request using various methods."""
        
        # Method 1: Internal API Key (for service-to-service communication)
        if self.internal_api_key:
            api_key = request.headers.get("X-API-Key")
            if api_key == self.internal_api_key:
                return {
                    "authenticated": True,
                    "auth_type": "api_key",
                    "user_id": "internal_service",
                    "roles": ["service"]
                }
        
        # Method 2: JWT Token
        if self.jwt_secret_key:
            auth_header = request.headers.get("Authorization")
            if auth_header and auth_header.startswith("Bearer "):
                token = auth_header.split(" ")[1]
                try:
                    payload = jwt.decode(
                        token,
                        self.jwt_secret_key,
                        algorithms=[self.jwt_algorithm]
                    )
                    return {
                        "authenticated": True,
                        "auth_type": "jwt",
                        "user_id": payload.get("sub"),
                        "roles": payload.get("roles", []),
                        "permissions": payload.get("permissions", [])
                    }
                except JWTError as e:
                    return {
                        "authenticated": False,
                        "error": f"Invalid JWT token: {str(e)}"
                    }
        
        # Method 3: Session-based authentication (could be added later)
        # ...
        
        return {
            "authenticated": False,
            "error": "No valid authentication method found"
        }


def require_auth(request: Request) -> dict:
    """Dependency to require authentication."""
    if not hasattr(request.state, "user_id") or not request.state.user_id:
        raise HTTPException(status_code=401, detail="Authentication required")
    
    return {
        "user_id": request.state.user_id,
        "roles": getattr(request.state, "user_roles", []),
        "auth_type": getattr(request.state, "auth_type", None)
    }


def require_role(required_role: str):
    """Dependency factory to require specific role."""
    def _require_role(auth_info: dict = require_auth) -> dict:
        if required_role not in auth_info.get("roles", []):
            raise HTTPException(
                status_code=403,
                detail=f"Role '{required_role}' required"
            )
        return auth_info
    
    return _require_role


def require_permission(required_permission: str):
    """Dependency factory to require specific permission."""
    def _require_permission(request: Request) -> dict:
        auth_info = require_auth(request)
        permissions = getattr(request.state, "permissions", [])
        
        if required_permission not in permissions:
            raise HTTPException(
                status_code=403,
                detail=f"Permission '{required_permission}' required"
            )
        return auth_info
    
    return _require_permission