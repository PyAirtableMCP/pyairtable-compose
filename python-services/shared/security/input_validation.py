"""
Input Validation and Sanitization
Comprehensive input validation to prevent injection attacks
"""

import re
import html
import json
import logging
from typing import Any, Dict, List, Optional, Union
from urllib.parse import quote, unquote
from fastapi import HTTPException, Request
from pydantic import BaseModel, validator
import bleach

logger = logging.getLogger(__name__)

class ValidationError(Exception):
    """Custom validation error"""
    pass

class SQLInjectionValidator:
    """SQL Injection prevention validator"""
    
    # Common SQL injection patterns
    SQL_PATTERNS = [
        r"(?i)(\b(union|select|insert|update|delete|drop|create|alter|exec|execute)\b)",
        r"(?i)(\b(or|and)\s+\d+\s*=\s*\d+)",
        r"(?i)(';\s*(drop|delete|insert|update|create|alter))",
        r"(?i)(\/\*.*?\*\/)",  # SQL comments
        r"(?i)(--[^\r\n]*)",   # SQL comments
        r"(?i)(\bxp_cmdshell\b)",
        r"(?i)(\bsp_executesql\b)",
        r"(?i)('.*'.*=.*'.*')",
        r"(?i)(0x[0-9a-f]+)",  # Hex values
        r"(?i)(\bcast\s*\()",
        r"(?i)(\bconvert\s*\()",
        r"(?i)(\bchar\s*\()",
        r"(?i)(\bnvarchar\s*\()",
    ]
    
    @classmethod
    def validate(cls, value: str, field_name: str = "input") -> bool:
        """
        Validate input for SQL injection patterns
        
        Args:
            value: Input string to validate
            field_name: Name of the field being validated
            
        Returns:
            bool: True if input is safe
            
        Raises:
            ValidationError: If SQL injection pattern is detected
        """
        if not isinstance(value, str):
            return True
            
        for pattern in cls.SQL_PATTERNS:
            if re.search(pattern, value):
                logger.warning(f"SQL injection attempt detected in {field_name}: {pattern}")
                raise ValidationError(f"Invalid input detected in {field_name}")
                
        return True
    
    @classmethod
    def sanitize(cls, value: str) -> str:
        """
        Sanitize input by removing/escaping dangerous SQL patterns
        """
        if not isinstance(value, str):
            return value
            
        # Remove SQL comments
        value = re.sub(r"(/\*.*?\*/|--[^\r\n]*)", "", value, flags=re.IGNORECASE)
        
        # Escape single quotes
        value = value.replace("'", "''")
        
        # Remove dangerous functions
        dangerous_functions = [
            "xp_cmdshell", "sp_executesql", "openrowset", "opendatasource",
            "exec", "execute", "eval"
        ]
        
        for func in dangerous_functions:
            value = re.sub(rf"\b{func}\b", "", value, flags=re.IGNORECASE)
            
        return value.strip()

class XSSValidator:
    """Cross-Site Scripting (XSS) prevention validator"""
    
    # XSS patterns
    XSS_PATTERNS = [
        r"(?i)<script[^>]*>.*?</script>",
        r"(?i)javascript:",
        r"(?i)vbscript:",
        r"(?i)onload\s*=",
        r"(?i)onerror\s*=", 
        r"(?i)onclick\s*=",
        r"(?i)onmouseover\s*=",
        r"(?i)onfocus\s*=",
        r"(?i)onblur\s*=",
        r"(?i)onkeypress\s*=",
        r"(?i)onsubmit\s*=",
        r"(?i)<iframe[^>]*>",
        r"(?i)<embed[^>]*>",
        r"(?i)<object[^>]*>",
        r"(?i)<applet[^>]*>",
        r"(?i)<meta[^>]*>",
        r"(?i)<link[^>]*>",
        r"(?i)expression\s*\(",
        r"(?i)url\s*\(",
        r"(?i)@import",
        r"(?i)binding:",
        r"(?i)-moz-binding",
    ]
    
    @classmethod
    def validate(cls, value: str, field_name: str = "input") -> bool:
        """
        Validate input for XSS patterns
        """
        if not isinstance(value, str):
            return True
            
        for pattern in cls.XSS_PATTERNS:
            if re.search(pattern, value):
                logger.warning(f"XSS attempt detected in {field_name}: {pattern}")
                raise ValidationError(f"Invalid input detected in {field_name}")
                
        return True
    
    @classmethod
    def sanitize(cls, value: str, allowed_tags: List[str] = None) -> str:
        """
        Sanitize input by removing/escaping XSS patterns
        """
        if not isinstance(value, str):
            return value
            
        # Use bleach for HTML sanitization
        allowed_tags = allowed_tags or []
        allowed_attributes = {}
        
        # Clean HTML
        clean_value = bleach.clean(
            value,
            tags=allowed_tags,
            attributes=allowed_attributes,
            strip=True
        )
        
        # HTML encode any remaining dangerous characters
        clean_value = html.escape(clean_value, quote=True)
        
        return clean_value

class PathTraversalValidator:
    """Path traversal attack prevention validator"""
    
    # Path traversal patterns
    PATH_PATTERNS = [
        r"\.\.[\\/]",
        r"[\\/]\.\.[\\/]",
        r"\.\.[\\/]\.\.[\\/]",
        r"[\\/]etc[\\/]passwd",
        r"[\\/]etc[\\/]shadow", 
        r"[\\/]proc[\\/]",
        r"[\\/]sys[\\/]",
        r"[\\/]dev[\\/]",
        r"[\\/]var[\\/]log[\\/]",
        r"boot\.ini",
        r"win\.ini",
        r"system\.ini",
    ]
    
    @classmethod
    def validate(cls, value: str, field_name: str = "input") -> bool:
        """
        Validate input for path traversal patterns
        """
        if not isinstance(value, str):
            return True
            
        # URL decode to catch encoded attacks
        decoded_value = unquote(value)
        
        for pattern in cls.PATH_PATTERNS:
            if re.search(pattern, value, re.IGNORECASE) or re.search(pattern, decoded_value, re.IGNORECASE):
                logger.warning(f"Path traversal attempt detected in {field_name}: {pattern}")
                raise ValidationError(f"Invalid path detected in {field_name}")
                
        return True
    
    @classmethod
    def sanitize(cls, value: str) -> str:
        """
        Sanitize path input
        """
        if not isinstance(value, str):
            return value
            
        # Remove path traversal sequences
        value = re.sub(r"\.\.[\\/]+", "", value)
        value = re.sub(r"[\\/]+\.\.", "", value)
        
        # Remove null bytes
        value = value.replace("\x00", "")
        
        # Normalize slashes
        value = value.replace("\\", "/")
        
        return value.strip()

class CommandInjectionValidator:
    """Command injection prevention validator"""
    
    # Command injection patterns
    CMD_PATTERNS = [
        r"[;&|`$()]",
        r"(?i)\b(cat|ls|dir|type|echo|whoami|id|pwd|uname)\b",
        r"(?i)\b(rm|del|copy|move|mkdir|rmdir)\b",
        r"(?i)\b(wget|curl|nc|netcat|telnet|ssh)\b",
        r"(?i)\b(chmod|chown|su|sudo)\b",
        r"(?i)\b(powershell|cmd|bash|sh|zsh|csh)\b",
        r"(?i)\b(python|perl|ruby|php|node)\b",
    ]
    
    @classmethod
    def validate(cls, value: str, field_name: str = "input") -> bool:
        """
        Validate input for command injection patterns
        """
        if not isinstance(value, str):
            return True
            
        for pattern in cls.CMD_PATTERNS:
            if re.search(pattern, value):
                logger.warning(f"Command injection attempt detected in {field_name}: {pattern}")
                raise ValidationError(f"Invalid input detected in {field_name}")
                
        return True
    
    @classmethod 
    def sanitize(cls, value: str) -> str:
        """
        Sanitize input to prevent command injection
        """
        if not isinstance(value, str):
            return value
            
        # Remove dangerous characters
        dangerous_chars = [";", "&", "|", "`", "$", "(", ")", "<", ">"]
        for char in dangerous_chars:
            value = value.replace(char, "")
            
        return value.strip()

class InputValidator:
    """Main input validator that combines all validation types"""
    
    def __init__(self, 
                 enable_sql_validation: bool = True,
                 enable_xss_validation: bool = True, 
                 enable_path_validation: bool = True,
                 enable_cmd_validation: bool = True,
                 max_length: int = 10000):
        self.enable_sql_validation = enable_sql_validation
        self.enable_xss_validation = enable_xss_validation
        self.enable_path_validation = enable_path_validation
        self.enable_cmd_validation = enable_cmd_validation
        self.max_length = max_length
        
    def validate_string(self, value: str, field_name: str = "input") -> bool:
        """
        Validate a string input with all enabled validators
        """
        if not isinstance(value, str):
            return True
            
        # Check length
        if len(value) > self.max_length:
            raise ValidationError(f"Input too long in {field_name} (max {self.max_length} characters)")
            
        # Run validators
        if self.enable_sql_validation:
            SQLInjectionValidator.validate(value, field_name)
            
        if self.enable_xss_validation:
            XSSValidator.validate(value, field_name)
            
        if self.enable_path_validation:
            PathTraversalValidator.validate(value, field_name)
            
        if self.enable_cmd_validation:
            CommandInjectionValidator.validate(value, field_name)
            
        return True
    
    def sanitize_string(self, value: str, allowed_html_tags: List[str] = None) -> str:
        """
        Sanitize a string input with all enabled sanitizers
        """
        if not isinstance(value, str):
            return value
            
        # Apply sanitizers
        if self.enable_sql_validation:
            value = SQLInjectionValidator.sanitize(value)
            
        if self.enable_xss_validation:
            value = XSSValidator.sanitize(value, allowed_html_tags)
            
        if self.enable_path_validation:
            value = PathTraversalValidator.sanitize(value)
            
        if self.enable_cmd_validation:
            value = CommandInjectionValidator.sanitize(value)
            
        return value
        
    def validate_dict(self, data: Dict[str, Any], field_prefix: str = "") -> bool:
        """
        Recursively validate dictionary data
        """
        for key, value in data.items():
            field_name = f"{field_prefix}.{key}" if field_prefix else key
            
            if isinstance(value, str):
                self.validate_string(value, field_name)
            elif isinstance(value, dict):
                self.validate_dict(value, field_name)
            elif isinstance(value, list):
                self.validate_list(value, field_name)
                
        return True
        
    def validate_list(self, data: List[Any], field_prefix: str = "") -> bool:
        """
        Validate list data
        """
        for i, item in enumerate(data):
            field_name = f"{field_prefix}[{i}]"
            
            if isinstance(item, str):
                self.validate_string(item, field_name)
            elif isinstance(item, dict):
                self.validate_dict(item, field_name)
            elif isinstance(item, list):
                self.validate_list(item, field_name)
                
        return True

# Global validator instance
default_validator = InputValidator()

def validate_request_data(data: Union[Dict, List, str], field_name: str = "request") -> bool:
    """
    Validate request data using the default validator
    """
    try:
        if isinstance(data, str):
            return default_validator.validate_string(data, field_name)
        elif isinstance(data, dict):
            return default_validator.validate_dict(data, field_name)
        elif isinstance(data, list):
            return default_validator.validate_list(data, field_name)
        else:
            return True
    except ValidationError as e:
        logger.error(f"Validation failed: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

def sanitize_request_data(data: Union[Dict, List, str], allowed_html_tags: List[str] = None) -> Any:
    """
    Sanitize request data using the default validator
    """
    if isinstance(data, str):
        return default_validator.sanitize_string(data, allowed_html_tags)
    elif isinstance(data, dict):
        sanitized = {}
        for key, value in data.items():
            sanitized[key] = sanitize_request_data(value, allowed_html_tags)
        return sanitized
    elif isinstance(data, list):
        return [sanitize_request_data(item, allowed_html_tags) for item in data]
    else:
        return data

# Pydantic model for validated requests
class ValidatedRequest(BaseModel):
    """Base model with input validation"""
    
    @validator('*', pre=True)
    def validate_all_fields(cls, v):
        """Validate all fields in the request"""
        if isinstance(v, str):
            validate_request_data(v)
        return v

class SecureStringField(BaseModel):
    """Secure string field with validation"""
    value: str
    
    @validator('value')
    def validate_value(cls, v):
        validate_request_data(v, "secure_string")
        return v