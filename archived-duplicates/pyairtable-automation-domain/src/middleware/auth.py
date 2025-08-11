"""Authentication middleware."""

import uuid
from typing import Optional

from fastapi import Request, Response
from fastapi.security.utils import get_authorization_scheme_param
from jose import JWTError, jwt
from starlette.middleware.base import BaseHTTPMiddleware

from ..core.logging import get_logger

logger = get_logger(__name__)


class AuthenticationMiddleware(BaseHTTPMiddleware):
    """Authentication middleware for API requests."""
    
    def __init__(
        self,
        app,
        internal_api_key: str,
        jwt_secret_key: str,
        jwt_algorithm: str = "HS256"
    ):
        super().__init__(app)
        self.internal_api_key = internal_api_key
        self.jwt_secret_key = jwt_secret_key
        self.jwt_algorithm = jwt_algorithm
        
        # Public endpoints that don't require authentication
        self.public_endpoints = {
            "/",
            "/health",
            "/info",
            "/docs",
            "/redoc",
            "/openapi.json",
            "/metrics",
        }
    
    async def dispatch(self, request: Request, call_next) -> Response:
        """Process request through authentication."""
        # Generate request ID
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id
        
        # Skip auth for public endpoints
        if self._is_public_endpoint(request.url.path):
            return await call_next(request)
        
        # Check authentication
        auth_result = await self._authenticate_request(request)
        if not auth_result.get("authenticated", False):
            return Response(
                content='{"error": "unauthorized", "message": "Authentication required"}',
                status_code=401,
                media_type="application/json",
                headers={"X-Request-ID": request_id}
            )
        
        # Add user info to request state
        request.state.user = auth_result.get("user")
        request.state.auth_type = auth_result.get("auth_type")
        
        return await call_next(request)
    
    def _is_public_endpoint(self, path: str) -> bool:
        """Check if endpoint is public."""
        return path in self.public_endpoints or path.startswith("/docs") or path.startswith("/redoc")
    
    async def _authenticate_request(self, request: Request) -> dict:
        """Authenticate the request."""
        authorization = request.headers.get("Authorization")
        if not authorization:
            return {"authenticated": False}
        
        scheme, credentials = get_authorization_scheme_param(authorization)
        
        # Check for internal API key
        if scheme.lower() == "bearer" and credentials == self.internal_api_key:
            return {
                "authenticated": True,
                "auth_type": "api_key",
                "user": {"type": "service", "id": "internal"}
            }
        
        # Check for JWT token
        if scheme.lower() == "bearer":
            try:
                payload = jwt.decode(
                    credentials,
                    self.jwt_secret_key,
                    algorithms=[self.jwt_algorithm]
                )
                return {
                    "authenticated": True,
                    "auth_type": "jwt",
                    "user": payload
                }
            except JWTError as e:
                logger.warning("JWT validation failed", error=str(e))
                return {"authenticated": False}
        
        return {"authenticated": False}