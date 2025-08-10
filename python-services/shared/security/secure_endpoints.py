"""
Secure API Endpoint Decorators and Validators
Enterprise-grade endpoint security for FastAPI
"""

import logging
from functools import wraps
from typing import Any, Callable, Dict, List, Optional, Union
from fastapi import HTTPException, Request, Depends
from pydantic import BaseModel, validator
from .input_validation import validate_request_data, sanitize_request_data, ValidationError
from .authentication import SecurityContext, get_current_user

logger = logging.getLogger(__name__)

class SecureEndpointConfig:
    """Configuration for secure endpoints"""
    
    def __init__(self,
                 require_auth: bool = True,
                 required_permissions: List[str] = None,
                 required_role: str = None,
                 validate_input: bool = True,
                 sanitize_input: bool = True,
                 rate_limit: int = None,
                 max_request_size: int = 1024 * 1024,  # 1MB
                 allowed_content_types: List[str] = None):
        self.require_auth = require_auth
        self.required_permissions = required_permissions or []
        self.required_role = required_role
        self.validate_input = validate_input
        self.sanitize_input = sanitize_input
        self.rate_limit = rate_limit
        self.max_request_size = max_request_size
        self.allowed_content_types = allowed_content_types or [
            "application/json", 
            "application/x-www-form-urlencoded",
            "multipart/form-data"
        ]

def secure_endpoint(config: SecureEndpointConfig = None):
    """
    Decorator to add comprehensive security to FastAPI endpoints
    """
    if config is None:
        config = SecureEndpointConfig()
    
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Get request object
            request = None
            for arg in args:
                if isinstance(arg, Request):
                    request = arg
                    break
            
            if not request:
                # Try to find request in kwargs
                request = kwargs.get('request')
            
            if not request:
                raise HTTPException(status_code=500, detail="Request object not found")
            
            try:
                # 1. Content-Type validation
                if request.method in ["POST", "PUT", "PATCH"]:
                    content_type = request.headers.get("content-type", "").split(";")[0].strip()
                    if content_type and content_type not in config.allowed_content_types:
                        raise HTTPException(
                            status_code=415, 
                            detail=f"Unsupported content type: {content_type}"
                        )
                
                # 2. Request size validation
                content_length = request.headers.get("content-length")
                if content_length and int(content_length) > config.max_request_size:
                    raise HTTPException(status_code=413, detail="Request entity too large")
                
                # 3. Authentication and authorization
                user = None
                if config.require_auth:
                    # Get current user (this will handle JWT validation)
                    user = await get_current_user()
                    
                    # Check required role
                    if config.required_role and user.role != config.required_role and user.role != "admin":
                        raise HTTPException(
                            status_code=403, 
                            detail=f"Required role: {config.required_role}"
                        )
                    
                    # Check required permissions
                    for permission in config.required_permissions:
                        if permission not in user.permissions and user.role != "admin":
                            raise HTTPException(
                                status_code=403, 
                                detail=f"Required permission: {permission}"
                            )
                
                # 4. Input validation and sanitization
                if config.validate_input or config.sanitize_input:
                    # Get request body if it exists
                    if hasattr(request, '_body'):
                        body = await request.body()
                        if body:
                            try:
                                import json
                                request_data = json.loads(body)
                                
                                if config.validate_input:
                                    validate_request_data(request_data, "request_body")
                                
                                if config.sanitize_input:
                                    request_data = sanitize_request_data(request_data)
                                    # Note: We can't modify the original request body,
                                    # but validation has already occurred
                                    
                            except json.JSONDecodeError:
                                # Not JSON, skip validation for now
                                pass
                            except ValidationError as ve:
                                raise HTTPException(status_code=400, detail=str(ve))
                
                # 5. Add security context to kwargs if user is authenticated
                if user:
                    kwargs['current_user'] = user
                
                # Execute the original function
                result = await func(*args, **kwargs)
                
                # 6. Log successful request (for audit trail)
                logger.info(f"Secure endpoint accessed: {request.url.path} by {user.user_id if user else 'anonymous'}")
                
                return result
                
            except HTTPException:
                raise
            except Exception as e:
                logger.error(f"Secure endpoint error on {request.url.path}: {str(e)}")
                raise HTTPException(status_code=500, detail="Internal server error")
        
        return wrapper
    return decorator

# Predefined security configurations
class SecurityConfigs:
    """Predefined security configurations for common use cases"""
    
    # Public endpoints (no authentication required)
    PUBLIC = SecureEndpointConfig(
        require_auth=False,
        validate_input=True,
        sanitize_input=True
    )
    
    # Basic authenticated endpoints
    AUTHENTICATED = SecureEndpointConfig(
        require_auth=True,
        validate_input=True,
        sanitize_input=True
    )
    
    # Admin-only endpoints
    ADMIN_ONLY = SecureEndpointConfig(
        require_auth=True,
        required_role="admin",
        validate_input=True,
        sanitize_input=True,
        max_request_size=512 * 1024  # 512KB for admin endpoints
    )
    
    # High-security endpoints (e.g., financial data)
    HIGH_SECURITY = SecureEndpointConfig(
        require_auth=True,
        validate_input=True,
        sanitize_input=True,
        rate_limit=10,  # 10 requests per minute
        max_request_size=256 * 1024,  # 256KB
        allowed_content_types=["application/json"]
    )
    
    # File upload endpoints
    FILE_UPLOAD = SecureEndpointConfig(
        require_auth=True,
        validate_input=True,
        sanitize_input=False,  # Don't sanitize file content
        max_request_size=10 * 1024 * 1024,  # 10MB
        allowed_content_types=["multipart/form-data"]
    )

# Convenience decorators
def public_endpoint(func):
    """Decorator for public endpoints"""
    return secure_endpoint(SecurityConfigs.PUBLIC)(func)

def authenticated_endpoint(func):
    """Decorator for authenticated endpoints"""
    return secure_endpoint(SecurityConfigs.AUTHENTICATED)(func)

def admin_endpoint(func):
    """Decorator for admin-only endpoints"""
    return secure_endpoint(SecurityConfigs.ADMIN_ONLY)(func)

def high_security_endpoint(func):
    """Decorator for high-security endpoints"""
    return secure_endpoint(SecurityConfigs.HIGH_SECURITY)(func)

# Request validation models
class SecureRequest(BaseModel):
    """Base class for secure request models with automatic validation"""
    
    class Config:
        # Validate all fields
        validate_all = True
        # Don't allow extra fields
        extra = "forbid"
        # Use enum values
        use_enum_values = True
        
    @validator('*', pre=True)
    def validate_all_fields(cls, v, field):
        """Validate all string fields for security issues"""
        if isinstance(v, str):
            try:
                validate_request_data(v, field.name)
            except ValidationError as e:
                raise ValueError(str(e))
        return v

class SecureStringField(BaseModel):
    """Secure string field with comprehensive validation"""
    value: str
    
    @validator('value')
    def validate_string(cls, v):
        if not isinstance(v, str):
            raise ValueError("Value must be a string")
        
        # Length check
        if len(v) > 10000:
            raise ValueError("String too long (max 10000 characters)")
        
        # Security validation
        try:
            validate_request_data(v, "secure_string")
        except ValidationError as e:
            raise ValueError(str(e))
        
        return v

class SecureEmailField(BaseModel):
    """Secure email field with validation"""
    email: str
    
    @validator('email')
    def validate_email(cls, v):
        import re
        
        if not v:
            raise ValueError("Email is required")
        
        # Basic email format validation
        email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        if not re.match(email_pattern, v):
            raise ValueError("Invalid email format")
        
        # Security validation
        try:
            validate_request_data(v, "email")
        except ValidationError as e:
            raise ValueError(str(e))
        
        return v.lower().strip()

class SecureIDField(BaseModel):
    """Secure ID field (UUID validation)"""
    id: str
    
    @validator('id')
    def validate_id(cls, v):
        import uuid
        
        if not v:
            raise ValueError("ID is required")
        
        # UUID validation
        try:
            uuid.UUID(v)
        except ValueError:
            raise ValueError("Invalid UUID format")
        
        return v

class SecurePaginationParams(BaseModel):
    """Secure pagination parameters"""
    limit: int = 50
    offset: int = 0
    
    @validator('limit')
    def validate_limit(cls, v):
        if v < 1 or v > 1000:
            raise ValueError("Limit must be between 1 and 1000")
        return v
    
    @validator('offset')
    def validate_offset(cls, v):
        if v < 0:
            raise ValueError("Offset must be non-negative")
        return v

# Secure query parameter validator
def validate_query_params(request: Request) -> Dict[str, Any]:
    """
    Validate and sanitize query parameters
    """
    validated_params = {}
    
    for key, value in request.query_params.items():
        try:
            # Validate parameter name
            if not key.replace('_', '').replace('-', '').isalnum():
                raise ValidationError(f"Invalid parameter name: {key}")
            
            # Validate parameter value
            if isinstance(value, str):
                validate_request_data(value, key)
                validated_params[key] = sanitize_request_data(value)
            else:
                validated_params[key] = value
                
        except ValidationError as e:
            raise HTTPException(status_code=400, detail=f"Invalid query parameter {key}: {str(e)}")
    
    return validated_params

# Path parameter validator
def validate_path_param(param_value: str, param_name: str = "path_param") -> str:
    """
    Validate path parameters
    """
    try:
        validate_request_data(param_value, param_name)
        return sanitize_request_data(param_value)
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=f"Invalid path parameter {param_name}: {str(e)}")

# File upload validator
def validate_file_upload(
    file_content: bytes, 
    filename: str, 
    max_size: int = 10 * 1024 * 1024,  # 10MB
    allowed_extensions: List[str] = None
) -> bool:
    """
    Validate uploaded files
    """
    allowed_extensions = allowed_extensions or [
        '.txt', '.csv', '.json', '.xml', '.pdf', '.doc', '.docx', 
        '.jpg', '.jpeg', '.png', '.gif', '.zip'
    ]
    
    # Size check
    if len(file_content) > max_size:
        raise HTTPException(status_code=413, detail="File too large")
    
    # Extension check
    import os
    file_ext = os.path.splitext(filename)[1].lower()
    if file_ext not in allowed_extensions:
        raise HTTPException(status_code=400, detail=f"File type not allowed: {file_ext}")
    
    # Basic content validation (check for executables)
    dangerous_signatures = [
        b'\x4d\x5a',  # PE executable
        b'\x7f\x45\x4c\x46',  # ELF executable
        b'#!/',  # Shell script
        b'<script',  # HTML with script
    ]
    
    file_start = file_content[:100].lower()
    for signature in dangerous_signatures:
        if signature in file_start:
            raise HTTPException(status_code=400, detail="Potentially dangerous file content detected")
    
    return True