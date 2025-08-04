"""Business logic processing endpoints."""

from typing import Any, Dict, List, Optional
from datetime import datetime

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field

from ..services.business_logic import (
    FormulaEngine, ValidationEngine, CalculationService, RuleEngine,
    FormulaResult, ValidationSummary, CalculationType,
    RuleType, RulePriority, BusinessRule
)
from ..services.business_logic.calculation_service import CalculationRequest as CalcRequest
from ..utils.exceptions import BusinessLogicError, ValidationError

router = APIRouter()

# Global instances (in production, these would be dependency-injected)
formula_engine = FormulaEngine()
validation_engine = ValidationEngine()
calculation_service = CalculationService()
rule_engine = RuleEngine()


class FormulaRequest(BaseModel):
    """Request for formula execution."""
    formula: str
    context: Dict[str, Any] = Field(default_factory=dict)
    compile: bool = False
    name: Optional[str] = None


class FormulaValidationRequest(BaseModel):
    """Request for formula validation."""
    formula: str


class ValidationRequest(BaseModel):
    """Request for data validation."""
    schema_name: str
    data: Dict[str, Any]
    context: Optional[Dict[str, Any]] = None
    strict: bool = True


class ValidationSchemaRequest(BaseModel):
    """Request to create a validation schema."""
    schema_name: str
    rules: Dict[str, Any]  # Field name -> validation rules
    allow_unknown_fields: bool = True


class CalculationRequest(BaseModel):
    """Request for calculation."""
    calculation_type: str  # CalculationType enum value
    operation: str
    data: Any
    parameters: Dict[str, Any] = Field(default_factory=dict)
    context: Dict[str, Any] = Field(default_factory=dict)
    cache_key: Optional[str] = None
    cache_ttl: int = 300


class BusinessRuleRequest(BaseModel):
    """Request for business rule execution."""
    rule_set_name: str
    rule_id: Optional[str] = None  # If None, execute all rules in set
    data: Dict[str, Any]
    context: Optional[Dict[str, Any]] = None


class CreateRuleSetRequest(BaseModel):
    """Request to create a rule set."""
    name: str
    description: str = ""


class CreateRuleRequest(BaseModel):
    """Request to create a business rule."""
    rule_set_name: str
    rule_id: str
    name: str
    rule_type: str  # RuleType enum value
    priority: str = "medium"  # RulePriority enum value
    conditions: List[Dict[str, Any]] = Field(default_factory=list)
    actions: List[Dict[str, Any]] = Field(default_factory=list)
    require_all_conditions: bool = True


# Formula endpoints
@router.post("/formulas/execute", response_model=Dict[str, Any])
async def execute_formula(request: FormulaRequest):
    """Execute a formula with given context."""
    try:
        if request.compile and request.name:
            # Compile and store the formula
            formula_engine.compile_formula(request.name, request.formula)
            result = formula_engine.execute_formula(request.name, request.context)
        else:
            # Execute formula directly
            result = formula_engine.execute_formula_direct(request.formula, request.context)
        
        return {
            "success": True,
            "result": {
                "value": result.value,
                "data_type": result.data_type.value,
                "is_valid": result.is_valid,
                "error_message": result.error_message,
                "warnings": result.warnings
            }
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/formulas/validate", response_model=Dict[str, Any])
async def validate_formula(request: FormulaValidationRequest):
    """Validate formula syntax."""
    try:
        validation_info = formula_engine.validate_formula(request.formula)
        return {
            "success": True,
            "validation": validation_info
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/formulas", response_model=List[str])
async def list_compiled_formulas():
    """List all compiled formulas."""
    return formula_engine.list_compiled_formulas()


@router.get("/formulas/{name}", response_model=Dict[str, Any])
async def get_formula_info(name: str):
    """Get information about a compiled formula."""
    info = formula_engine.get_formula_info(name)
    if not info:
        raise HTTPException(status_code=404, detail=f"Formula '{name}' not found")
    return info


# Validation endpoints
@router.post("/validation/validate", response_model=Dict[str, Any])
async def validate_data(request: ValidationRequest):
    """Validate data against a schema."""
    try:
        result = validation_engine.validate_data(
            request.data, 
            request.schema_name, 
            request.context
        )
        
        return {
            "success": True,
            "validation": {
                "is_valid": result.is_valid,
                "total_checks": result.total_checks,
                "passed_checks": result.passed_checks,
                "failed_checks": result.failed_checks,
                "warnings_count": result.warnings_count,
                "errors_count": result.errors_count,
                "critical_count": result.critical_count,
                "results": [
                    {
                        "is_valid": r.is_valid,
                        "field_name": r.field_name,
                        "validation_type": r.validation_type.value if r.validation_type else None,
                        "severity": r.severity.value,
                        "message": r.message,
                        "expected_value": r.expected_value,
                        "actual_value": r.actual_value
                    }
                    for r in result.results
                ]
            }
        }
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/validation/schemas", response_model=Dict[str, Any])
async def create_validation_schema(request: ValidationSchemaRequest):
    """Create a new validation schema."""
    try:
        schema = validation_engine.create_schema(request.schema_name)
        schema.allow_unknown_fields = request.allow_unknown_fields
        
        # Add field rules
        for field_name, field_rules in request.rules.items():
            rule = schema.field(field_name)
            
            # Parse and add validation rules
            if field_rules.get("required"):
                rule.required()
            
            if field_rules.get("type"):
                # Map string types to Python types
                type_mapping = {
                    "string": str,
                    "integer": int,
                    "float": float,
                    "boolean": bool,
                    "list": list,
                    "dict": dict
                }
                expected_type = type_mapping.get(field_rules["type"], str)
                rule.type_check(expected_type)
            
            if field_rules.get("min_length") or field_rules.get("max_length"):
                rule.length_check(
                    min_length=field_rules.get("min_length"),
                    max_length=field_rules.get("max_length")
                )
            
            if field_rules.get("min_value") or field_rules.get("max_value"):
                rule.range_check(
                    min_value=field_rules.get("min_value"),
                    max_value=field_rules.get("max_value")
                )
            
            if field_rules.get("pattern"):
                rule.pattern_check(field_rules["pattern"])
            
            if field_rules.get("email"):
                rule.email_format()
            
            if field_rules.get("phone"):
                rule.phone_format()
            
            if field_rules.get("url"):
                rule.url_format()
        
        return {
            "success": True,
            "schema_name": request.schema_name,
            "message": f"Validation schema '{request.schema_name}' created successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/validation/schemas", response_model=List[str])
async def list_validation_schemas():
    """List all validation schemas."""
    return validation_engine.list_schemas()


# Calculation endpoints
@router.post("/calculations/execute", response_model=Dict[str, Any])
async def execute_calculation(request: CalculationRequest):
    """Execute a calculation."""
    try:
        calc_request = CalcRequest(
            calculation_type=CalculationType(request.calculation_type),
            operation=request.operation,
            data=request.data,
            parameters=request.parameters,
            context=request.context,
            cache_key=request.cache_key,
            cache_ttl=request.cache_ttl
        )
        
        result = await calculation_service.calculate(calc_request)
        
        return {
            "success": True,
            "result": {
                "value": result.value,
                "calculation_type": result.calculation_type.value,
                "operation": result.operation,
                "is_cached": result.is_cached,
                "calculation_time_ms": result.calculation_time_ms,
                "metadata": result.metadata,
                "warnings": result.warnings,
                "intermediate_results": result.intermediate_results
            }
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/calculations/operations", response_model=Dict[str, List[str]])
async def list_calculation_operations():
    """List all available calculation operations."""
    return calculation_service.list_available_operations()


# Business rule endpoints
@router.post("/rules/rule-sets", response_model=Dict[str, Any])
async def create_rule_set(request: CreateRuleSetRequest):
    """Create a new rule set."""
    try:
        rule_set = rule_engine.create_rule_set(request.name, request.description)
        return {
            "success": True,
            "rule_set_name": request.name,
            "message": f"Rule set '{request.name}' created successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/rules/rules", response_model=Dict[str, Any])
async def create_business_rule(request: CreateRuleRequest):
    """Create a new business rule."""
    try:
        rule = rule_engine.create_rule(
            rule_set_name=request.rule_set_name,
            rule_id=request.rule_id,
            name=request.name,
            rule_type=RuleType(request.rule_type),
            priority=RulePriority[request.priority.upper()]
        )
        
        rule.require_all_conditions = request.require_all_conditions
        
        # Add conditions
        for condition in request.conditions:
            rule.add_condition(
                field=condition["field"],
                operator=condition["operator"],
                value=condition["value"],
                case_sensitive=condition.get("case_sensitive", True)
            )
        
        # Add actions
        for action in request.actions:
            rule.add_action(
                action_type=action["action_type"],
                **action.get("parameters", {})
            )
        
        return {
            "success": True,
            "rule_id": request.rule_id,
            "message": f"Business rule '{request.rule_id}' created successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/rules/execute", response_model=Dict[str, Any])
async def execute_business_rules(request: BusinessRuleRequest):
    """Execute business rules."""
    try:
        if request.rule_id:
            # Execute single rule
            result = await rule_engine.execute_single_rule(
                request.rule_set_name,
                request.rule_id,
                request.data,
                request.context
            )
            results = [result]
        else:
            # Execute all rules in set
            results = await rule_engine.execute_rule_set(
                request.rule_set_name,
                request.data,
                request.context
            )
        
        return {
            "success": True,
            "results": [
                {
                    "rule_id": r.rule_id,
                    "rule_name": r.rule_name,
                    "status": r.status.value,
                    "executed_at": r.executed_at.isoformat(),
                    "execution_time_ms": r.execution_time_ms,
                    "conditions_met": r.conditions_met,
                    "actions_executed": r.actions_executed,
                    "actions_failed": r.actions_failed,
                    "output_data": r.output_data,
                    "errors": r.errors,
                    "warnings": r.warnings,
                    "metadata": r.metadata
                }
                for r in results
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/rules/rule-sets", response_model=List[str])
async def list_rule_sets():
    """List all rule sets."""
    return rule_engine.list_rule_sets()


@router.get("/rules/rule-sets/{rule_set_name}/rules", response_model=List[Dict[str, Any]])
async def list_rules_in_set(rule_set_name: str, rule_type: Optional[str] = None):
    """List rules in a rule set."""
    try:
        filter_type = RuleType(rule_type) if rule_type else None
        rules = rule_engine.list_rules(rule_set_name, filter_type)
        
        return [
            {
                "rule_id": rule.rule_id,
                "name": rule.name,
                "rule_type": rule.rule_type.value,
                "priority": rule.priority.value,
                "enabled": rule.enabled,
                "conditions_count": len(rule.conditions),
                "actions_count": len(rule.actions),
                "created_at": rule.created_at.isoformat(),
                "updated_at": rule.updated_at.isoformat()
            }
            for rule in rules
        ]
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/rules/rule-sets/{rule_set_name}/export", response_model=Dict[str, Any])
async def export_rule_set(rule_set_name: str):
    """Export rule set configuration."""
    try:
        config = rule_engine.export_rules(rule_set_name)
        return {
            "success": True,
            "config": config
        }
    except Exception as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/rules/rule-sets/import", response_model=Dict[str, Any])
async def import_rule_set(config: Dict[str, Any]):
    """Import rule set configuration."""
    try:
        rule_set = rule_engine.import_rules(config)
        return {
            "success": True,
            "rule_set_name": rule_set.name,
            "message": f"Rule set '{rule_set.name}' imported successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# Legacy endpoints for backward compatibility
@router.post("/transform")
async def transform_data(request: Dict[str, Any]):
    """Apply data transformations (legacy endpoint)."""
    # Convert to new calculation format
    calc_request = CalculationRequest(
        calculation_type="simple",
        operation=request.get("operation", "transform"),
        data=request.get("data", {}),
        parameters=request.get("parameters", {}),
        context={}
    )
    
    try:
        result = await execute_calculation(calc_request)
        return result
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/validate")
async def validate_data_legacy(request: Dict[str, Any]):
    """Validate data against business rules (legacy endpoint)."""
    validation_request = ValidationRequest(
        schema_name=request.get("schema_name", "default"),
        data=request.get("data", {}),
        strict=request.get("strict", True)
    )
    
    try:
        return await validate_data(validation_request)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/transforms")
async def list_transforms():
    """List available data transformations."""
    return {
        "transforms": [
            "filter", "sort", "group", "aggregate", "map", "reduce",
            "join", "pivot", "unpivot", "normalize", "denormalize"
        ]
    }


@router.get("/schemas")
async def list_schemas():
    """List available validation schemas."""
    return await list_validation_schemas()