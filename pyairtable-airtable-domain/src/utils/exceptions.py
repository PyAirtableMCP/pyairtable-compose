"""Custom exception classes for the application."""

from typing import Any, Dict, Optional


class PyAirtableError(Exception):
    """Base exception for PyAirtable domain service."""
    
    def __init__(
        self,
        message: str,
        error_code: str = "GENERIC_ERROR",
        details: Optional[Dict[str, Any]] = None
    ):
        self.message = message
        self.error_code = error_code
        self.details = details or {}
        super().__init__(self.message)


class ConfigurationError(PyAirtableError):
    """Configuration-related errors."""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, "CONFIGURATION_ERROR", details)


class AuthenticationError(PyAirtableError):
    """Authentication-related errors."""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, "AUTHENTICATION_ERROR", details)


class AuthorizationError(PyAirtableError):
    """Authorization-related errors."""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, "AUTHORIZATION_ERROR", details)


class ValidationError(PyAirtableError):
    """Data validation errors."""
    
    def __init__(self, message: str, field: str = "", details: Optional[Dict[str, Any]] = None):
        self.field = field
        details = details or {}
        if field:
            details["field"] = field
        super().__init__(message, "VALIDATION_ERROR", details)


class AirtableAPIError(PyAirtableError):
    """Airtable API-related errors."""
    
    def __init__(
        self,
        message: str,
        status_code: Optional[int] = None,
        response_data: Optional[Dict[str, Any]] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.status_code = status_code
        self.response_data = response_data or {}
        
        details = details or {}
        if status_code:
            details["status_code"] = status_code
        if response_data:
            details["response_data"] = response_data
        
        super().__init__(message, "AIRTABLE_API_ERROR", details)


class RateLimitError(AirtableAPIError):
    """Rate limit exceeded errors."""
    
    def __init__(
        self,
        message: str = "Rate limit exceeded",
        retry_after: Optional[int] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.retry_after = retry_after
        
        details = details or {}
        if retry_after:
            details["retry_after"] = retry_after
        
        super().__init__(message, 429, details=details)
        self.error_code = "RATE_LIMIT_ERROR"


class DatabaseError(PyAirtableError):
    """Database-related errors."""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, "DATABASE_ERROR", details)


class CacheError(PyAirtableError):
    """Cache-related errors."""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message, "CACHE_ERROR", details)


class WorkflowError(PyAirtableError):
    """Workflow execution errors."""
    
    def __init__(
        self,
        message: str,
        workflow_id: Optional[str] = None,
        execution_id: Optional[str] = None,
        step_index: Optional[int] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.workflow_id = workflow_id
        self.execution_id = execution_id
        self.step_index = step_index
        
        details = details or {}
        if workflow_id:
            details["workflow_id"] = workflow_id
        if execution_id:
            details["execution_id"] = execution_id
        if step_index is not None:
            details["step_index"] = step_index
        
        super().__init__(message, "WORKFLOW_ERROR", details)


class BusinessLogicError(PyAirtableError):
    """Business logic processing errors."""
    
    def __init__(
        self,
        message: str,
        rule_name: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.rule_name = rule_name
        
        details = details or {}
        if rule_name:
            details["rule_name"] = rule_name
        
        super().__init__(message, "BUSINESS_LOGIC_ERROR", details)


class ExternalServiceError(PyAirtableError):
    """External service integration errors."""
    
    def __init__(
        self,
        message: str,
        service_name: str,
        status_code: Optional[int] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.service_name = service_name
        self.status_code = status_code
        
        details = details or {}
        details["service_name"] = service_name
        if status_code:
            details["status_code"] = status_code
        
        super().__init__(message, "EXTERNAL_SERVICE_ERROR", details)


class TimeoutError(PyAirtableError):
    """Timeout-related errors."""
    
    def __init__(
        self,
        message: str = "Operation timed out",
        timeout_seconds: Optional[float] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.timeout_seconds = timeout_seconds
        
        details = details or {}
        if timeout_seconds:
            details["timeout_seconds"] = timeout_seconds
        
        super().__init__(message, "TIMEOUT_ERROR", details)


class ResourceNotFoundError(PyAirtableError):
    """Resource not found errors."""
    
    def __init__(
        self,
        message: str,
        resource_type: str,
        resource_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.resource_type = resource_type
        self.resource_id = resource_id
        
        details = details or {}
        details["resource_type"] = resource_type
        if resource_id:
            details["resource_id"] = resource_id
        
        super().__init__(message, "RESOURCE_NOT_FOUND", details)


class ConflictError(PyAirtableError):
    """Resource conflict errors."""
    
    def __init__(
        self,
        message: str,
        resource_type: str,
        conflicting_field: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.resource_type = resource_type
        self.conflicting_field = conflicting_field
        
        details = details or {}
        details["resource_type"] = resource_type
        if conflicting_field:
            details["conflicting_field"] = conflicting_field
        
        super().__init__(message, "CONFLICT_ERROR", details)


class RetryableError(PyAirtableError):
    """Errors that can be retried."""
    
    def __init__(
        self,
        message: str,
        retry_after: Optional[float] = None,
        max_retries: int = 3,
        details: Optional[Dict[str, Any]] = None
    ):
        self.retry_after = retry_after
        self.max_retries = max_retries
        
        details = details or {}
        if retry_after:
            details["retry_after"] = retry_after
        details["max_retries"] = max_retries
        
        super().__init__(message, "RETRYABLE_ERROR", details)


def create_error_response(error: PyAirtableError, request_id: Optional[str] = None) -> Dict[str, Any]:
    """Create standardized error response dictionary."""
    response = {
        "error": {
            "code": error.error_code,
            "message": error.message,
            "details": error.details,
        }
    }
    
    if request_id:
        response["request_id"] = request_id
    
    # Add specific error fields
    if isinstance(error, AirtableAPIError) and error.status_code:
        response["error"]["status_code"] = error.status_code
    
    if isinstance(error, ValidationError) and error.field:
        response["error"]["field"] = error.field
    
    if isinstance(error, RateLimitError) and error.retry_after:
        response["error"]["retry_after"] = error.retry_after
    
    return response