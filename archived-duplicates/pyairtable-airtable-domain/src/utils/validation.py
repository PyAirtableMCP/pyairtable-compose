"""Data validation utilities."""

import re
from typing import Any, Dict, List, Optional, Union
from uuid import UUID

from pydantic import ValidationError, BaseModel


def is_valid_uuid(value: str) -> bool:
    """Check if string is a valid UUID."""
    try:
        UUID(value)
        return True
    except (ValueError, TypeError):
        return False


def is_valid_email(email: str) -> bool:
    """Check if string is a valid email address."""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return bool(re.match(pattern, email))


def is_valid_url(url: str) -> bool:
    """Check if string is a valid URL."""
    pattern = r'^https?://(?:[-\w.])+(?:[:\d]+)?(?:/(?:[\w/_.])*(?:\?(?:[\w&=%.])*)?(?:#(?:\w*))?)?$'
    return bool(re.match(pattern, url))


def is_valid_airtable_id(airtable_id: str, id_type: str = "any") -> bool:
    """Check if string is a valid Airtable ID."""
    patterns = {
        "base": r'^app[a-zA-Z0-9]{14}$',
        "table": r'^tbl[a-zA-Z0-9]{14}$',
        "record": r'^rec[a-zA-Z0-9]{14}$',
        "field": r'^fld[a-zA-Z0-9]{14}$',
        "view": r'^viw[a-zA-Z0-9]{14}$',
        "any": r'^(app|tbl|rec|fld|viw)[a-zA-Z0-9]{14}$'
    }
    
    pattern = patterns.get(id_type, patterns["any"])
    return bool(re.match(pattern, airtable_id))


def validate_json_schema(data: Dict[str, Any], schema: Dict[str, Any]) -> tuple[bool, List[str]]:
    """Validate data against JSON schema."""
    try:
        import jsonschema
        jsonschema.validate(data, schema)
        return True, []
    except ImportError:
        return False, ["jsonschema package not installed"]
    except jsonschema.ValidationError as e:
        return False, [str(e)]
    except Exception as e:
        return False, [f"Validation error: {str(e)}"]


def validate_pydantic_model(data: Dict[str, Any], model_class: type) -> tuple[bool, List[str], Optional[BaseModel]]:
    """Validate data against Pydantic model."""
    try:
        instance = model_class(**data)
        return True, [], instance
    except ValidationError as e:
        errors = [f"{err['loc']}: {err['msg']}" for err in e.errors()]
        return False, errors, None
    except Exception as e:
        return False, [f"Validation error: {str(e)}"], None


def sanitize_string(value: str, max_length: Optional[int] = None) -> str:
    """Sanitize string by removing dangerous characters."""
    if not isinstance(value, str):
        value = str(value)
    
    # Remove control characters
    value = re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '', value)
    
    # Trim whitespace
    value = value.strip()
    
    # Limit length if specified
    if max_length and len(value) > max_length:
        value = value[:max_length]
    
    return value


def validate_airtable_record_fields(fields: Dict[str, Any]) -> tuple[bool, List[str]]:
    """Validate Airtable record fields."""
    errors = []
    
    # Check for empty fields dict
    if not fields:
        errors.append("Fields dictionary cannot be empty")
        return False, errors
    
    # Validate field names and values
    for field_name, field_value in fields.items():
        # Field name validation
        if not isinstance(field_name, str):
            errors.append(f"Field name must be string, got {type(field_name)}")
            continue
        
        if len(field_name) > 255:
            errors.append(f"Field name '{field_name}' too long (max 255 characters)")
        
        # Basic field value validation
        if field_value is not None:
            # Check for extremely large values
            if isinstance(field_value, str) and len(field_value) > 100000:
                errors.append(f"Field '{field_name}' value too long (max 100000 characters)")
            
            # Check for nested depth (Airtable has limits)
            if isinstance(field_value, (dict, list)):
                depth = get_nested_depth(field_value)
                if depth > 10:
                    errors.append(f"Field '{field_name}' has too much nesting (max 10 levels)")
    
    return len(errors) == 0, errors


def get_nested_depth(obj: Union[Dict, List], current_depth: int = 0) -> int:
    """Calculate maximum nesting depth of dict/list structure."""
    if current_depth > 20:  # Prevent infinite recursion
        return current_depth
    
    max_depth = current_depth
    
    if isinstance(obj, dict):
        for value in obj.values():
            if isinstance(value, (dict, list)):
                depth = get_nested_depth(value, current_depth + 1)
                max_depth = max(max_depth, depth)
    elif isinstance(obj, list):
        for item in obj:
            if isinstance(item, (dict, list)):
                depth = get_nested_depth(item, current_depth + 1)
                max_depth = max(max_depth, depth)
    
    return max_depth


def validate_batch_size(items: List[Any], max_size: int = 10) -> tuple[bool, str]:
    """Validate batch size for operations."""
    if not items:
        return False, "Batch cannot be empty"
    
    if len(items) > max_size:
        return False, f"Batch size {len(items)} exceeds maximum {max_size}"
    
    return True, ""


def validate_pagination_params(limit: int, offset: int) -> tuple[bool, List[str]]:
    """Validate pagination parameters."""
    errors = []
    
    if limit < 1:
        errors.append("Limit must be at least 1")
    elif limit > 100:
        errors.append("Limit cannot exceed 100")
    
    if offset < 0:
        errors.append("Offset cannot be negative")
    
    return len(errors) == 0, errors


def validate_cron_expression(cron_expr: str) -> tuple[bool, str]:
    """Validate cron expression format."""
    try:
        import croniter
        croniter.croniter(cron_expr)
        return True, ""
    except ImportError:
        return False, "croniter package not installed"
    except (ValueError, TypeError) as e:
        return False, f"Invalid cron expression: {str(e)}"


def validate_workflow_config(config: Dict[str, Any]) -> tuple[bool, List[str]]:
    """Validate workflow configuration."""
    errors = []
    
    # Check required fields
    required_fields = ["trigger", "actions"]
    for field in required_fields:
        if field not in config:
            errors.append(f"Missing required field: {field}")
    
    # Validate trigger
    if "trigger" in config:
        trigger = config["trigger"]
        if not isinstance(trigger, dict):
            errors.append("Trigger must be a dictionary")
        elif "type" not in trigger:
            errors.append("Trigger must have a type")
    
    # Validate actions
    if "actions" in config:
        actions = config["actions"]
        if not isinstance(actions, list):
            errors.append("Actions must be a list")
        elif len(actions) == 0:
            errors.append("At least one action is required")
        else:
            for i, action in enumerate(actions):
                if not isinstance(action, dict):
                    errors.append(f"Action {i} must be a dictionary")
                elif "type" not in action:
                    errors.append(f"Action {i} must have a type")
    
    return len(errors) == 0, errors