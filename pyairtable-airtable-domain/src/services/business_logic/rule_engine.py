"""Business rule engine for complex business logic processing."""

import asyncio
from datetime import datetime
from typing import Any, Dict, List, Optional, Union, Callable, Set
from dataclasses import dataclass, field
from enum import Enum
from abc import ABC, abstractmethod

from .formula_engine import FormulaEngine, FormulaResult
from .validation_engine import ValidationEngine, ValidationSummary
from ...core.logging import get_logger
from ...utils.exceptions import BusinessLogicError

logger = get_logger(__name__)


class RuleType(Enum):
    """Types of business rules."""
    VALIDATION = "validation"
    TRANSFORMATION = "transformation"
    AUTHORIZATION = "authorization"
    WORKFLOW = "workflow"
    CALCULATION = "calculation"
    NOTIFICATION = "notification"
    AUTOMATION = "automation"


class RulePriority(Enum):
    """Rule execution priority."""
    CRITICAL = 1
    HIGH = 2
    MEDIUM = 3
    LOW = 4


class RuleStatus(Enum):
    """Rule execution status."""
    PENDING = "pending"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass
class RuleCondition:
    """Condition for rule execution."""
    field: str
    operator: str  # eq, ne, gt, lt, gte, lte, in, not_in, contains, regex
    value: Any
    case_sensitive: bool = True
    
    def evaluate(self, data: Dict[str, Any]) -> bool:
        """Evaluate condition against data."""
        field_value = data.get(self.field)
        
        if field_value is None:
            return self.operator in ["ne", "not_in"]
        
        # Handle case sensitivity for strings
        if isinstance(field_value, str) and isinstance(self.value, str) and not self.case_sensitive:
            field_value = field_value.lower()
            compare_value = self.value.lower()
        else:
            compare_value = self.value
        
        try:
            if self.operator == "eq":
                return field_value == compare_value
            elif self.operator == "ne":
                return field_value != compare_value
            elif self.operator == "gt":
                return field_value > compare_value
            elif self.operator == "lt":
                return field_value < compare_value
            elif self.operator == "gte":
                return field_value >= compare_value
            elif self.operator == "lte":
                return field_value <= compare_value
            elif self.operator == "in":
                return field_value in compare_value
            elif self.operator == "not_in":
                return field_value not in compare_value
            elif self.operator == "contains":
                return str(compare_value) in str(field_value)
            elif self.operator == "regex":
                import re
                pattern = re.compile(str(compare_value))
                return bool(pattern.search(str(field_value)))
            else:
                logger.warning(f"Unknown operator: {self.operator}")
                return False
        except Exception as e:
            logger.error(f"Condition evaluation error: {e}", field=self.field, operator=self.operator)
            return False


@dataclass
class RuleAction:
    """Action to execute when rule conditions are met."""
    action_type: str  # set_field, calculate, validate, notify, webhook, etc.
    parameters: Dict[str, Any] = field(default_factory=dict)
    
    async def execute(self, data: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
        """Execute the action."""
        # This will be implemented by specific action handlers
        raise NotImplementedError(f"Action type '{self.action_type}' not implemented")


@dataclass
class RuleResult:
    """Result of rule execution."""
    rule_id: str
    rule_name: str
    status: RuleStatus
    executed_at: datetime
    execution_time_ms: int
    conditions_met: bool
    actions_executed: int
    actions_failed: int
    output_data: Optional[Dict[str, Any]] = None
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)


class BusinessRule:
    """Individual business rule."""
    
    def __init__(self, rule_id: str, name: str, rule_type: RuleType, 
                 priority: RulePriority = RulePriority.MEDIUM):
        self.rule_id = rule_id
        self.name = name
        self.rule_type = rule_type
        self.priority = priority
        self.enabled = True
        self.conditions: List[RuleCondition] = []
        self.actions: List[RuleAction] = []
        self.require_all_conditions = True  # AND vs OR logic
        self.metadata: Dict[str, Any] = {}
        self.created_at = datetime.now()
        self.updated_at = datetime.now()
    
    def add_condition(self, field: str, operator: str, value: Any, 
                     case_sensitive: bool = True) -> 'BusinessRule':
        """Add a condition to the rule."""
        condition = RuleCondition(
            field=field,
            operator=operator,
            value=value,
            case_sensitive=case_sensitive
        )
        self.conditions.append(condition)
        self.updated_at = datetime.now()
        return self
    
    def add_action(self, action_type: str, **parameters) -> 'BusinessRule':
        """Add an action to the rule."""
        action = RuleAction(
            action_type=action_type,
            parameters=parameters
        )
        self.actions.append(action)
        self.updated_at = datetime.now()
        return self
    
    def evaluate_conditions(self, data: Dict[str, Any]) -> bool:
        """Evaluate all conditions for the rule."""
        if not self.conditions:
            return True
        
        results = [condition.evaluate(data) for condition in self.conditions]
        
        if self.require_all_conditions:
            return all(results)
        else:
            return any(results)
    
    async def execute(self, data: Dict[str, Any], context: Optional[Dict[str, Any]] = None) -> RuleResult:
        """Execute the rule against provided data."""
        start_time = datetime.now()
        execution_context = context or {}
        
        try:
            # Check if rule is enabled
            if not self.enabled:
                return RuleResult(
                    rule_id=self.rule_id,
                    rule_name=self.name,
                    status=RuleStatus.SKIPPED,
                    executed_at=start_time,
                    execution_time_ms=0,
                    conditions_met=False,
                    actions_executed=0,
                    actions_failed=0,
                    warnings=["Rule is disabled"]
                )
            
            # Evaluate conditions
            conditions_met = self.evaluate_conditions(data)
            
            if not conditions_met:
                execution_time = int((datetime.now() - start_time).total_seconds() * 1000)
                return RuleResult(
                    rule_id=self.rule_id,
                    rule_name=self.name,
                    status=RuleStatus.SUCCESS,
                    executed_at=start_time,
                    execution_time_ms=execution_time,
                    conditions_met=False,
                    actions_executed=0,
                    actions_failed=0
                )
            
            # Execute actions
            actions_executed = 0
            actions_failed = 0
            errors = []
            warnings = []
            output_data = data.copy()
            
            for action in self.actions:
                try:
                    # Execute action (this would be handled by action processors)
                    result = await self._execute_action(action, output_data, execution_context)
                    if result:
                        output_data.update(result)
                    actions_executed += 1
                except Exception as e:
                    actions_failed += 1
                    errors.append(f"Action {action.action_type} failed: {str(e)}")
                    logger.error(f"Action execution failed", rule_id=self.rule_id, action=action.action_type, error=str(e))
            
            execution_time = int((datetime.now() - start_time).total_seconds() * 1000)
            status = RuleStatus.SUCCESS if actions_failed == 0 else RuleStatus.FAILED
            
            return RuleResult(
                rule_id=self.rule_id,
                rule_name=self.name,
                status=status,
                executed_at=start_time,
                execution_time_ms=execution_time,
                conditions_met=True,
                actions_executed=actions_executed,
                actions_failed=actions_failed,
                output_data=output_data,
                errors=errors,
                warnings=warnings
            )
            
        except Exception as e:
            execution_time = int((datetime.now() - start_time).total_seconds() * 1000)
            logger.error(f"Rule execution failed", rule_id=self.rule_id, error=str(e))
            
            return RuleResult(
                rule_id=self.rule_id,
                rule_name=self.name,
                status=RuleStatus.FAILED,
                executed_at=start_time,
                execution_time_ms=execution_time,
                conditions_met=False,
                actions_executed=0,
                actions_failed=len(self.actions),
                errors=[f"Rule execution error: {str(e)}"]
            )
    
    async def _execute_action(self, action: RuleAction, data: Dict[str, Any], 
                             context: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Execute a specific action. This would be extended by action processors."""
        # Basic action implementations
        if action.action_type == "set_field":
            field_name = action.parameters.get("field")
            value = action.parameters.get("value")
            if field_name and value is not None:
                return {field_name: value}
        
        elif action.action_type == "log":
            message = action.parameters.get("message", "Rule action executed")
            level = action.parameters.get("level", "info")
            getattr(logger, level)(message, rule_id=self.rule_id, data=data)
        
        # Other action types would be handled by specific processors
        return None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert rule to dictionary representation."""
        return {
            "rule_id": self.rule_id,
            "name": self.name,
            "rule_type": self.rule_type.value,
            "priority": self.priority.value,
            "enabled": self.enabled,
            "require_all_conditions": self.require_all_conditions,
            "conditions": [
                {
                    "field": c.field,
                    "operator": c.operator,
                    "value": c.value,
                    "case_sensitive": c.case_sensitive
                }
                for c in self.conditions
            ],
            "actions": [
                {
                    "action_type": a.action_type,
                    "parameters": a.parameters
                }
                for a in self.actions
            ],
            "metadata": self.metadata,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat()
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'BusinessRule':
        """Create rule from dictionary representation."""
        rule = cls(
            rule_id=data["rule_id"],
            name=data["name"],
            rule_type=RuleType(data["rule_type"]),
            priority=RulePriority(data["priority"])
        )
        
        rule.enabled = data.get("enabled", True)
        rule.require_all_conditions = data.get("require_all_conditions", True)
        rule.metadata = data.get("metadata", {})
        
        # Add conditions
        for condition_data in data.get("conditions", []):
            rule.add_condition(
                field=condition_data["field"],
                operator=condition_data["operator"],
                value=condition_data["value"],
                case_sensitive=condition_data.get("case_sensitive", True)
            )
        
        # Add actions
        for action_data in data.get("actions", []):
            rule.add_action(
                action_type=action_data["action_type"],
                **action_data.get("parameters", {})
            )
        
        # Set timestamps
        if "created_at" in data:
            rule.created_at = datetime.fromisoformat(data["created_at"])
        if "updated_at" in data:
            rule.updated_at = datetime.fromisoformat(data["updated_at"])
        
        return rule


class RuleSet:
    """Collection of related business rules."""
    
    def __init__(self, name: str, description: str = ""):
        self.name = name
        self.description = description
        self.rules: Dict[str, BusinessRule] = {}
        self.enabled = True
        self.created_at = datetime.now()
        self.updated_at = datetime.now()
    
    def add_rule(self, rule: BusinessRule) -> None:
        """Add a rule to the set."""
        self.rules[rule.rule_id] = rule
        self.updated_at = datetime.now()
    
    def remove_rule(self, rule_id: str) -> bool:
        """Remove a rule from the set."""
        if rule_id in self.rules:
            del self.rules[rule_id]
            self.updated_at = datetime.now()
            return True
        return False
    
    def get_rule(self, rule_id: str) -> Optional[BusinessRule]:
        """Get a rule by ID."""
        return self.rules.get(rule_id)
    
    def list_rules(self, rule_type: Optional[RuleType] = None, 
                  enabled_only: bool = True) -> List[BusinessRule]:
        """List rules, optionally filtered by type and status."""
        rules = list(self.rules.values())
        
        if enabled_only:
            rules = [rule for rule in rules if rule.enabled]
        
        if rule_type:
            rules = [rule for rule in rules if rule.rule_type == rule_type]
        
        # Sort by priority
        rules.sort(key=lambda r: r.priority.value)
        
        return rules
    
    async def execute_rules(self, data: Dict[str, Any], context: Optional[Dict[str, Any]] = None,
                           rule_type: Optional[RuleType] = None) -> List[RuleResult]:
        """Execute all applicable rules in the set."""
        if not self.enabled:
            return []
        
        applicable_rules = self.list_rules(rule_type=rule_type, enabled_only=True)
        
        if not applicable_rules:
            return []
        
        # Execute rules concurrently within priority groups
        results = []
        current_data = data.copy()
        execution_context = context or {}
        
        # Group rules by priority
        priority_groups = {}
        for rule in applicable_rules:
            priority = rule.priority.value
            if priority not in priority_groups:
                priority_groups[priority] = []
            priority_groups[priority].append(rule)
        
        # Execute priority groups in order
        for priority in sorted(priority_groups.keys()):
            group_rules = priority_groups[priority]
            
            # Execute rules in priority group concurrently
            tasks = [rule.execute(current_data, execution_context) for rule in group_rules]
            group_results = await asyncio.gather(*tasks, return_exceptions=True)
            
            # Process results
            for i, result in enumerate(group_results):
                if isinstance(result, Exception):
                    # Create error result
                    error_result = RuleResult(
                        rule_id=group_rules[i].rule_id,
                        rule_name=group_rules[i].name,
                        status=RuleStatus.FAILED,
                        executed_at=datetime.now(),
                        execution_time_ms=0,
                        conditions_met=False,
                        actions_executed=0,
                        actions_failed=1,
                        errors=[f"Rule execution exception: {str(result)}"]
                    )
                    results.append(error_result)
                else:
                    results.append(result)
                    
                    # Update current data with rule output for subsequent rules
                    if result.output_data and result.status == RuleStatus.SUCCESS:
                        current_data.update(result.output_data)
        
        return results


class ActionProcessor(ABC):
    """Base class for rule action processors."""
    
    @property
    @abstractmethod
    def action_type(self) -> str:
        """The action type this processor handles."""
        pass
    
    @abstractmethod
    async def process(self, action: RuleAction, data: Dict[str, Any], 
                     context: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Process the action and return any data modifications."""
        pass


class FormulaActionProcessor(ActionProcessor):
    """Processor for formula-based actions."""
    
    def __init__(self, formula_engine: FormulaEngine):
        self.formula_engine = formula_engine
    
    @property
    def action_type(self) -> str:
        return "formula"
    
    async def process(self, action: RuleAction, data: Dict[str, Any], 
                     context: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        formula = action.parameters.get("formula")
        target_field = action.parameters.get("target_field")
        
        if not formula or not target_field:
            raise ValueError("Formula action requires 'formula' and 'target_field' parameters")
        
        # Prepare formula context
        formula_context = {**data, **context}
        
        # Execute formula
        result = self.formula_engine.execute_formula_direct(formula, formula_context)
        
        if not result.is_valid:
            raise BusinessLogicError(f"Formula execution failed: {result.error_message}")
        
        return {target_field: result.value}


class ValidationActionProcessor(ActionProcessor):
    """Processor for validation actions."""
    
    def __init__(self, validation_engine: ValidationEngine):
        self.validation_engine = validation_engine
    
    @property
    def action_type(self) -> str:
        return "validate"
    
    async def process(self, action: RuleAction, data: Dict[str, Any], 
                     context: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        schema_name = action.parameters.get("schema")
        fail_on_error = action.parameters.get("fail_on_error", False)
        
        if not schema_name:
            raise ValueError("Validation action requires 'schema' parameter")
        
        # Perform validation
        validation_result = self.validation_engine.validate_data(data, schema_name, context)
        
        if fail_on_error and not validation_result.is_valid:
            errors = [result.message for result in validation_result.results if not result.is_valid]
            raise BusinessLogicError(f"Validation failed: {'; '.join(errors)}")
        
        return {
            "_validation_result": {
                "is_valid": validation_result.is_valid,
                "errors_count": validation_result.errors_count,
                "warnings_count": validation_result.warnings_count
            }
        }


class RuleEngine:
    """Main business rule engine."""
    
    def __init__(self, formula_engine: Optional[FormulaEngine] = None,
                 validation_engine: Optional[ValidationEngine] = None):
        self.formula_engine = formula_engine or FormulaEngine()
        self.validation_engine = validation_engine or ValidationEngine()
        self.rule_sets: Dict[str, RuleSet] = {}
        self.action_processors: Dict[str, ActionProcessor] = {}
        
        # Register default action processors
        self._register_default_processors()
    
    def _register_default_processors(self) -> None:
        """Register default action processors."""
        self.register_action_processor(FormulaActionProcessor(self.formula_engine))
        self.register_action_processor(ValidationActionProcessor(self.validation_engine))
    
    def register_action_processor(self, processor: ActionProcessor) -> None:
        """Register a custom action processor."""
        self.action_processors[processor.action_type] = processor
        logger.info(f"Registered action processor: {processor.action_type}")
    
    def create_rule_set(self, name: str, description: str = "") -> RuleSet:
        """Create a new rule set."""
        rule_set = RuleSet(name, description)
        self.rule_sets[name] = rule_set
        return rule_set
    
    def get_rule_set(self, name: str) -> Optional[RuleSet]:
        """Get a rule set by name."""
        return self.rule_sets.get(name)
    
    def create_rule(self, rule_set_name: str, rule_id: str, name: str, 
                   rule_type: RuleType, priority: RulePriority = RulePriority.MEDIUM) -> BusinessRule:
        """Create a new rule in a rule set."""
        rule_set = self.get_rule_set(rule_set_name)
        if not rule_set:
            raise BusinessLogicError(f"Rule set '{rule_set_name}' not found")
        
        rule = BusinessRule(rule_id, name, rule_type, priority)
        rule_set.add_rule(rule)
        return rule
    
    async def execute_rule_set(self, rule_set_name: str, data: Dict[str, Any],
                              context: Optional[Dict[str, Any]] = None,
                              rule_type: Optional[RuleType] = None) -> List[RuleResult]:
        """Execute a rule set against data."""
        rule_set = self.get_rule_set(rule_set_name)
        if not rule_set:
            raise BusinessLogicError(f"Rule set '{rule_set_name}' not found")
        
        return await rule_set.execute_rules(data, context, rule_type)
    
    async def execute_single_rule(self, rule_set_name: str, rule_id: str,
                                 data: Dict[str, Any], context: Optional[Dict[str, Any]] = None) -> RuleResult:
        """Execute a single rule."""
        rule_set = self.get_rule_set(rule_set_name)
        if not rule_set:
            raise BusinessLogicError(f"Rule set '{rule_set_name}' not found")
        
        rule = rule_set.get_rule(rule_id)
        if not rule:
            raise BusinessLogicError(f"Rule '{rule_id}' not found in rule set '{rule_set_name}'")
        
        return await rule.execute(data, context)
    
    def list_rule_sets(self) -> List[str]:
        """List all rule sets."""
        return list(self.rule_sets.keys())
    
    def list_rules(self, rule_set_name: str, rule_type: Optional[RuleType] = None) -> List[BusinessRule]:
        """List rules in a rule set."""
        rule_set = self.get_rule_set(rule_set_name)
        if not rule_set:
            return []
        
        return rule_set.list_rules(rule_type=rule_type)
    
    def export_rules(self, rule_set_name: str) -> Dict[str, Any]:
        """Export rule set configuration."""
        rule_set = self.get_rule_set(rule_set_name)
        if not rule_set:
            raise BusinessLogicError(f"Rule set '{rule_set_name}' not found")
        
        return {
            "name": rule_set.name,
            "description": rule_set.description,
            "enabled": rule_set.enabled,
            "rules": [rule.to_dict() for rule in rule_set.rules.values()],
            "created_at": rule_set.created_at.isoformat(),
            "updated_at": rule_set.updated_at.isoformat()
        }
    
    def import_rules(self, config: Dict[str, Any]) -> RuleSet:
        """Import rule set configuration."""
        rule_set = RuleSet(
            name=config["name"],
            description=config.get("description", "")
        )
        rule_set.enabled = config.get("enabled", True)
        
        # Import rules
        for rule_data in config.get("rules", []):
            rule = BusinessRule.from_dict(rule_data)
            rule_set.add_rule(rule)
        
        # Set timestamps
        if "created_at" in config:
            rule_set.created_at = datetime.fromisoformat(config["created_at"])
        if "updated_at" in config:
            rule_set.updated_at = datetime.fromisoformat(config["updated_at"])
        
        self.rule_sets[rule_set.name] = rule_set
        return rule_set