"""Advanced validation engine for business rules and data validation."""

import re
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List, Optional, Union, Callable, Pattern
from dataclasses import dataclass, field
from enum import Enum
from abc import ABC, abstractmethod

from ...core.logging import get_logger
from ...utils.exceptions import ValidationError

logger = get_logger(__name__)


class ValidationSeverity(Enum):
    """Validation error severity levels."""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


class ValidationType(Enum):
    """Types of validation rules."""
    REQUIRED = "required"
    TYPE = "type"
    FORMAT = "format"
    RANGE = "range"
    LENGTH = "length"
    PATTERN = "pattern"
    CUSTOM = "custom"
    BUSINESS_RULE = "business_rule"


@dataclass
class ValidationResult:
    """Result of a validation check."""
    is_valid: bool
    field_name: Optional[str] = None
    validation_type: Optional[ValidationType] = None
    severity: ValidationSeverity = ValidationSeverity.ERROR
    message: str = ""
    expected_value: Optional[Any] = None
    actual_value: Optional[Any] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ValidationSummary:
    """Summary of all validation results."""
    is_valid: bool
    total_checks: int
    passed_checks: int
    failed_checks: int
    warnings_count: int
    errors_count: int
    critical_count: int
    results: List[ValidationResult] = field(default_factory=list)
    
    def add_result(self, result: ValidationResult) -> None:
        """Add a validation result."""
        self.results.append(result)
        self.total_checks += 1
        
        if result.is_valid:
            self.passed_checks += 1
        else:
            self.failed_checks += 1
            
            if result.severity == ValidationSeverity.WARNING:
                self.warnings_count += 1
            elif result.severity == ValidationSeverity.ERROR:
                self.errors_count += 1
            elif result.severity == ValidationSeverity.CRITICAL:
                self.critical_count += 1
        
        # Update overall validity
        self.is_valid = self.errors_count == 0 and self.critical_count == 0


class BaseValidator(ABC):
    """Base class for all validators."""
    
    def __init__(self, field_name: str, severity: ValidationSeverity = ValidationSeverity.ERROR):
        self.field_name = field_name
        self.severity = severity
    
    @abstractmethod
    def validate(self, value: Any, context: Optional[Dict[str, Any]] = None) -> ValidationResult:
        """Validate a value."""
        pass
    
    def _create_result(self, is_valid: bool, message: str, 
                      expected: Any = None, actual: Any = None,
                      validation_type: Optional[ValidationType] = None) -> ValidationResult:
        """Create a validation result."""
        return ValidationResult(
            is_valid=is_valid,
            field_name=self.field_name,
            validation_type=validation_type,
            severity=self.severity,
            message=message,
            expected_value=expected,
            actual_value=actual
        )


class RequiredValidator(BaseValidator):
    """Validates that a field is not empty."""
    
    def validate(self, value: Any, context: Optional[Dict[str, Any]] = None) -> ValidationResult:
        is_valid = value is not None and value != ""
        
        if isinstance(value, (list, dict)):
            is_valid = len(value) > 0
        
        message = f"Field '{self.field_name}' is required" if not is_valid else "Field is present"
        
        return self._create_result(
            is_valid=is_valid,
            message=message,
            validation_type=ValidationType.REQUIRED,
            actual=value
        )


class TypeValidator(BaseValidator):
    """Validates data types."""
    
    def __init__(self, field_name: str, expected_type: Union[type, tuple], 
                 severity: ValidationSeverity = ValidationSeverity.ERROR):
        super().__init__(field_name, severity)
        self.expected_type = expected_type
    
    def validate(self, value: Any, context: Optional[Dict[str, Any]] = None) -> ValidationResult:
        if value is None:
            return self._create_result(
                is_valid=True,
                message="Value is None",
                validation_type=ValidationType.TYPE
            )
        
        is_valid = isinstance(value, self.expected_type)
        
        message = (
            f"Field '{self.field_name}' has correct type" if is_valid
            else f"Field '{self.field_name}' expected {self.expected_type}, got {type(value)}"
        )
        
        return self._create_result(
            is_valid=is_valid,
            message=message,
            expected=self.expected_type,
            actual=type(value),
            validation_type=ValidationType.TYPE
        )


class RangeValidator(BaseValidator):
    """Validates numeric ranges."""
    
    def __init__(self, field_name: str, min_value: Optional[Union[int, float]] = None,
                 max_value: Optional[Union[int, float]] = None,
                 severity: ValidationSeverity = ValidationSeverity.ERROR):
        super().__init__(field_name, severity)
        self.min_value = min_value
        self.max_value = max_value
    
    def validate(self, value: Any, context: Optional[Dict[str, Any]] = None) -> ValidationResult:
        if value is None or not isinstance(value, (int, float, Decimal)):
            return self._create_result(
                is_valid=True,
                message="Value is not numeric, skipping range validation",
                validation_type=ValidationType.RANGE
            )
        
        is_valid = True
        messages = []
        
        if self.min_value is not None and value < self.min_value:
            is_valid = False
            messages.append(f"below minimum {self.min_value}")
        
        if self.max_value is not None and value > self.max_value:
            is_valid = False
            messages.append(f"above maximum {self.max_value}")
        
        if is_valid:
            message = f"Field '{self.field_name}' is within valid range"
        else:
            message = f"Field '{self.field_name}' is {', '.join(messages)}"
        
        return self._create_result(
            is_valid=is_valid,
            message=message,
            expected=f"[{self.min_value}, {self.max_value}]",
            actual=value,
            validation_type=ValidationType.RANGE
        )


class LengthValidator(BaseValidator):
    """Validates string/array length."""
    
    def __init__(self, field_name: str, min_length: Optional[int] = None,
                 max_length: Optional[int] = None,
                 severity: ValidationSeverity = ValidationSeverity.ERROR):
        super().__init__(field_name, severity)
        self.min_length = min_length
        self.max_length = max_length
    
    def validate(self, value: Any, context: Optional[Dict[str, Any]] = None) -> ValidationResult:
        if value is None:
            return self._create_result(
                is_valid=True,
                message="Value is None, skipping length validation",
                validation_type=ValidationType.LENGTH
            )
        
        try:
            length = len(value)
        except TypeError:
            return self._create_result(
                is_valid=False,
                message=f"Field '{self.field_name}' does not support length operation",
                validation_type=ValidationType.LENGTH,
                actual=value
            )
        
        is_valid = True
        messages = []
        
        if self.min_length is not None and length < self.min_length:
            is_valid = False
            messages.append(f"shorter than minimum {self.min_length}")
        
        if self.max_length is not None and length > self.max_length:
            is_valid = False
            messages.append(f"longer than maximum {self.max_length}")
        
        if is_valid:
            message = f"Field '{self.field_name}' has valid length ({length})"
        else:
            message = f"Field '{self.field_name}' length ({length}) is {', '.join(messages)}"
        
        return self._create_result(
            is_valid=is_valid,
            message=message,
            expected=f"length [{self.min_length}, {self.max_length}]",
            actual=length,
            validation_type=ValidationType.LENGTH
        )


class PatternValidator(BaseValidator):
    """Validates against regex patterns."""
    
    def __init__(self, field_name: str, pattern: Union[str, Pattern],
                 severity: ValidationSeverity = ValidationSeverity.ERROR):
        super().__init__(field_name, severity)
        self.pattern = re.compile(pattern) if isinstance(pattern, str) else pattern
        self.pattern_str = pattern if isinstance(pattern, str) else pattern.pattern
    
    def validate(self, value: Any, context: Optional[Dict[str, Any]] = None) -> ValidationResult:
        if value is None:
            return self._create_result(
                is_valid=True,
                message="Value is None, skipping pattern validation",
                validation_type=ValidationType.PATTERN
            )
        
        value_str = str(value)
        is_valid = bool(self.pattern.match(value_str))
        
        message = (
            f"Field '{self.field_name}' matches pattern" if is_valid
            else f"Field '{self.field_name}' does not match pattern '{self.pattern_str}'"
        )
        
        return self._create_result(
            is_valid=is_valid,
            message=message,
            expected=self.pattern_str,
            actual=value_str,
            validation_type=ValidationType.PATTERN
        )


class EmailValidator(PatternValidator):
    """Email format validator."""
    
    EMAIL_PATTERN = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    
    def __init__(self, field_name: str, severity: ValidationSeverity = ValidationSeverity.ERROR):
        super().__init__(field_name, self.EMAIL_PATTERN, severity)


class PhoneValidator(PatternValidator):
    """Phone number format validator."""
    
    PHONE_PATTERN = r'^[+]?[1-9]?[0-9]{7,15}$'
    
    def __init__(self, field_name: str, severity: ValidationSeverity = ValidationSeverity.ERROR):
        super().__init__(field_name, self.PHONE_PATTERN, severity)


class URLValidator(PatternValidator):
    """URL format validator."""
    
    URL_PATTERN = r'^https?://(?:[-\w.])+(?:[:\d]+)?(?:/(?:[\w/_.])*(?:\?(?:[\w&=%.])*)?(?:#(?:[\w.])*)?)?$'
    
    def __init__(self, field_name: str, severity: ValidationSeverity = ValidationSeverity.ERROR):
        super().__init__(field_name, self.URL_PATTERN, severity)


class CustomValidator(BaseValidator):
    """Custom validation with user-defined function."""
    
    def __init__(self, field_name: str, validator_func: Callable[[Any, Optional[Dict[str, Any]]], bool],
                 error_message: str = "Custom validation failed",
                 severity: ValidationSeverity = ValidationSeverity.ERROR):
        super().__init__(field_name, severity)
        self.validator_func = validator_func
        self.error_message = error_message
    
    def validate(self, value: Any, context: Optional[Dict[str, Any]] = None) -> ValidationResult:
        try:
            is_valid = self.validator_func(value, context)
            message = (
                f"Field '{self.field_name}' passed custom validation" if is_valid
                else f"Field '{self.field_name}': {self.error_message}"
            )
            
            return self._create_result(
                is_valid=is_valid,
                message=message,
                validation_type=ValidationType.CUSTOM,
                actual=value
            )
        except Exception as e:
            return self._create_result(
                is_valid=False,
                message=f"Field '{self.field_name}' custom validation error: {e}",
                validation_type=ValidationType.CUSTOM,
                actual=value
            )


class ValidationRule:
    """Combines multiple validators for a field."""
    
    def __init__(self, field_name: str):
        self.field_name = field_name
        self.validators: List[BaseValidator] = []
    
    def add_validator(self, validator: BaseValidator) -> 'ValidationRule':
        """Add a validator to this rule."""
        self.validators.append(validator)
        return self
    
    def required(self, severity: ValidationSeverity = ValidationSeverity.ERROR) -> 'ValidationRule':
        """Add required validation."""
        return self.add_validator(RequiredValidator(self.field_name, severity))
    
    def type_check(self, expected_type: Union[type, tuple], 
                  severity: ValidationSeverity = ValidationSeverity.ERROR) -> 'ValidationRule':
        """Add type validation."""
        return self.add_validator(TypeValidator(self.field_name, expected_type, severity))
    
    def range_check(self, min_value: Optional[Union[int, float]] = None,
                   max_value: Optional[Union[int, float]] = None,
                   severity: ValidationSeverity = ValidationSeverity.ERROR) -> 'ValidationRule':
        """Add range validation."""
        return self.add_validator(RangeValidator(self.field_name, min_value, max_value, severity))
    
    def length_check(self, min_length: Optional[int] = None,
                    max_length: Optional[int] = None,
                    severity: ValidationSeverity = ValidationSeverity.ERROR) -> 'ValidationRule':
        """Add length validation."""
        return self.add_validator(LengthValidator(self.field_name, min_length, max_length, severity))
    
    def pattern_check(self, pattern: Union[str, Pattern],
                     severity: ValidationSeverity = ValidationSeverity.ERROR) -> 'ValidationRule':
        """Add pattern validation."""
        return self.add_validator(PatternValidator(self.field_name, pattern, severity))
    
    def email_format(self, severity: ValidationSeverity = ValidationSeverity.ERROR) -> 'ValidationRule':
        """Add email format validation."""
        return self.add_validator(EmailValidator(self.field_name, severity))
    
    def phone_format(self, severity: ValidationSeverity = ValidationSeverity.ERROR) -> 'ValidationRule':
        """Add phone format validation."""
        return self.add_validator(PhoneValidator(self.field_name, severity))
    
    def url_format(self, severity: ValidationSeverity = ValidationSeverity.ERROR) -> 'ValidationRule':
        """Add URL format validation."""
        return self.add_validator(URLValidator(self.field_name, severity))
    
    def custom(self, validator_func: Callable[[Any, Optional[Dict[str, Any]]], bool],
              error_message: str = "Custom validation failed",
              severity: ValidationSeverity = ValidationSeverity.ERROR) -> 'ValidationRule':
        """Add custom validation."""
        return self.add_validator(CustomValidator(self.field_name, validator_func, error_message, severity))
    
    def validate(self, value: Any, context: Optional[Dict[str, Any]] = None) -> List[ValidationResult]:
        """Run all validators for this field."""
        results = []
        for validator in self.validators:
            try:
                result = validator.validate(value, context)
                results.append(result)
            except Exception as e:
                logger.error(f"Validation error for field {self.field_name}", error=str(e))
                results.append(ValidationResult(
                    is_valid=False,
                    field_name=self.field_name,
                    severity=ValidationSeverity.CRITICAL,
                    message=f"Validation system error: {e}",
                    actual_value=value
                ))
        return results


class ValidationSchema:
    """Collection of validation rules for a data structure."""
    
    def __init__(self, name: str):
        self.name = name
        self.rules: Dict[str, ValidationRule] = {}
        self.allow_unknown_fields = True
        self.global_validators: List[Callable[[Dict[str, Any]], ValidationResult]] = []
    
    def field(self, field_name: str) -> ValidationRule:
        """Get or create a validation rule for a field."""
        if field_name not in self.rules:
            self.rules[field_name] = ValidationRule(field_name)
        return self.rules[field_name]
    
    def add_global_validator(self, validator_func: Callable[[Dict[str, Any]], ValidationResult]) -> None:
        """Add a global validator that operates on the entire data structure."""
        self.global_validators.append(validator_func)
    
    def validate(self, data: Dict[str, Any], context: Optional[Dict[str, Any]] = None) -> ValidationSummary:
        """Validate data against this schema."""
        summary = ValidationSummary(
            is_valid=True,
            total_checks=0,
            passed_checks=0,
            failed_checks=0,
            warnings_count=0,
            errors_count=0,
            critical_count=0
        )
        
        # Validate each field with defined rules
        for field_name, rule in self.rules.items():
            field_value = data.get(field_name)
            field_results = rule.validate(field_value, context)
            
            for result in field_results:
                summary.add_result(result)
        
        # Check for unknown fields if not allowed
        if not self.allow_unknown_fields:
            unknown_fields = set(data.keys()) - set(self.rules.keys())
            for field in unknown_fields:
                summary.add_result(ValidationResult(
                    is_valid=False,
                    field_name=field,
                    severity=ValidationSeverity.WARNING,
                    message=f"Unknown field '{field}' found",
                    actual_value=data[field]
                ))
        
        # Run global validators
        for global_validator in self.global_validators:
            try:
                result = global_validator(data)
                summary.add_result(result)
            except Exception as e:
                summary.add_result(ValidationResult(
                    is_valid=False,
                    severity=ValidationSeverity.CRITICAL,
                    message=f"Global validation error: {e}"
                ))
        
        return summary


class ValidationEngine:
    """Main validation engine."""
    
    def __init__(self):
        self.schemas: Dict[str, ValidationSchema] = {}
        self.default_schema: Optional[ValidationSchema] = None
    
    def create_schema(self, name: str) -> ValidationSchema:
        """Create a new validation schema."""
        schema = ValidationSchema(name)
        self.schemas[name] = schema
        return schema
    
    def get_schema(self, name: str) -> Optional[ValidationSchema]:
        """Get a validation schema by name."""
        return self.schemas.get(name)
    
    def set_default_schema(self, schema: ValidationSchema) -> None:
        """Set the default schema."""
        self.default_schema = schema
    
    def validate_data(self, data: Dict[str, Any], schema_name: Optional[str] = None,
                     context: Optional[Dict[str, Any]] = None) -> ValidationSummary:
        """Validate data using specified or default schema."""
        schema = None
        
        if schema_name:
            schema = self.get_schema(schema_name)
            if not schema:
                raise ValidationError(f"Schema '{schema_name}' not found")
        elif self.default_schema:
            schema = self.default_schema
        else:
            raise ValidationError("No schema specified and no default schema set")
        
        return schema.validate(data, context)
    
    def list_schemas(self) -> List[str]:
        """List all available schemas."""
        return list(self.schemas.keys())
    
    def remove_schema(self, name: str) -> bool:
        """Remove a schema."""
        if name in self.schemas:
            del self.schemas[name]
            return True
        return False
    
    def validate_multiple(self, datasets: List[Dict[str, Any]], 
                         schema_name: Optional[str] = None,
                         context: Optional[Dict[str, Any]] = None) -> List[ValidationSummary]:
        """Validate multiple datasets."""
        results = []
        for data in datasets:
            try:
                result = self.validate_data(data, schema_name, context)
                results.append(result)
            except Exception as e:
                # Create error summary for failed validation
                error_summary = ValidationSummary(
                    is_valid=False,
                    total_checks=1,
                    passed_checks=0,
                    failed_checks=1,
                    warnings_count=0,
                    errors_count=0,
                    critical_count=1
                )
                error_summary.add_result(ValidationResult(
                    is_valid=False,
                    severity=ValidationSeverity.CRITICAL,
                    message=f"Validation system error: {e}"
                ))
                results.append(error_summary)
        
        return results