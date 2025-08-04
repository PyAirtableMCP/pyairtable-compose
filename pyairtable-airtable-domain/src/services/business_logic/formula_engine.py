"""Advanced formula parsing and evaluation engine."""

import ast
import operator
import re
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional, Union, Callable, Set
from dataclasses import dataclass
from abc import ABC, abstractmethod
from enum import Enum

from ...core.logging import get_logger
from ...utils.exceptions import ValidationError, BusinessLogicError

logger = get_logger(__name__)


class FormulaType(Enum):
    """Types of formulas supported."""
    CALCULATION = "calculation"
    VALIDATION = "validation"
    TRANSFORMATION = "transformation"
    CONDITION = "condition"


class DataType(Enum):
    """Data types for formula operations."""
    NUMBER = "number"
    TEXT = "text"
    DATE = "date"
    BOOLEAN = "boolean"
    ARRAY = "array"
    OBJECT = "object"


@dataclass
class FormulaResult:
    """Result of formula evaluation."""
    value: Any
    data_type: DataType
    is_valid: bool = True
    error_message: Optional[str] = None
    warnings: List[str] = None
    
    def __post_init__(self):
        if self.warnings is None:
            self.warnings = []


class FormulaFunction(ABC):
    """Base class for formula functions."""
    
    @property
    @abstractmethod
    def name(self) -> str:
        """Function name."""
        pass
    
    @property
    @abstractmethod 
    def description(self) -> str:
        """Function description."""
        pass
    
    @abstractmethod
    def execute(self, *args: Any, **kwargs: Any) -> Any:
        """Execute the function."""
        pass
    
    @abstractmethod
    def validate_args(self, *args: Any) -> bool:
        """Validate function arguments."""
        pass


class MathFunctions:
    """Mathematical functions for formulas."""
    
    @staticmethod
    def sum(*args: Union[float, int, List[Union[float, int]]]) -> float:
        """Sum function."""
        total = 0
        for arg in args:
            if isinstance(arg, (list, tuple)):
                total += sum(MathFunctions.sum(*arg) for _ in [None])
            elif isinstance(arg, (int, float)):
                total += arg
        return float(total)
    
    @staticmethod
    def average(*args: Union[float, int, List[Union[float, int]]]) -> float:
        """Average function."""
        values = []
        for arg in args:
            if isinstance(arg, (list, tuple)):
                values.extend(arg)
            elif isinstance(arg, (int, float)):
                values.append(arg)
        return sum(values) / len(values) if values else 0
    
    @staticmethod
    def min(*args: Union[float, int, List[Union[float, int]]]) -> float:
        """Minimum function."""
        values = []
        for arg in args:
            if isinstance(arg, (list, tuple)):
                values.extend(arg)
            elif isinstance(arg, (int, float)):
                values.append(arg)
        return min(values) if values else 0
    
    @staticmethod
    def max(*args: Union[float, int, List[Union[float, int]]]) -> float:
        """Maximum function."""
        values = []
        for arg in args:
            if isinstance(arg, (list, tuple)):
                values.extend(arg)
            elif isinstance(arg, (int, float)):
                values.append(arg)
        return max(values) if values else 0
    
    @staticmethod
    def round(value: float, digits: int = 0) -> float:
        """Round function."""
        return round(value, digits)
    
    @staticmethod
    def abs(value: float) -> float:
        """Absolute value function."""
        return abs(value)
    
    @staticmethod
    def sqrt(value: float) -> float:
        """Square root function."""
        return value ** 0.5
    
    @staticmethod
    def power(base: float, exponent: float) -> float:
        """Power function."""
        return base ** exponent


class TextFunctions:
    """Text manipulation functions for formulas."""
    
    @staticmethod
    def concatenate(*args: str) -> str:
        """Concatenate strings."""
        return "".join(str(arg) for arg in args)
    
    @staticmethod
    def upper(text: str) -> str:
        """Convert to uppercase."""
        return str(text).upper()
    
    @staticmethod
    def lower(text: str) -> str:
        """Convert to lowercase."""
        return str(text).lower()
    
    @staticmethod
    def length(text: str) -> int:
        """Get text length."""
        return len(str(text))
    
    @staticmethod
    def substring(text: str, start: int, length: Optional[int] = None) -> str:
        """Extract substring."""
        text_str = str(text)
        if length is None:
            return text_str[start:]
        return text_str[start:start + length]
    
    @staticmethod
    def replace(text: str, old: str, new: str) -> str:
        """Replace text."""
        return str(text).replace(old, new)
    
    @staticmethod
    def trim(text: str) -> str:
        """Trim whitespace."""
        return str(text).strip()
    
    @staticmethod
    def contains(text: str, search: str) -> bool:
        """Check if text contains substring."""
        return search in str(text)


class DateFunctions:
    """Date manipulation functions for formulas."""
    
    @staticmethod
    def now() -> datetime:
        """Current datetime."""
        return datetime.now()
    
    @staticmethod
    def today() -> datetime:
        """Today's date."""
        return datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    
    @staticmethod
    def date_add(date: datetime, days: int = 0, months: int = 0, years: int = 0) -> datetime:
        """Add time to date."""
        if not isinstance(date, datetime):
            raise ValueError("First argument must be a datetime")
        
        result = date + timedelta(days=days)
        
        if months or years:
            year = result.year + years + (result.month + months - 1) // 12
            month = ((result.month + months - 1) % 12) + 1
            result = result.replace(year=year, month=month)
        
        return result
    
    @staticmethod
    def date_diff(date1: datetime, date2: datetime, unit: str = "days") -> int:
        """Calculate difference between dates."""
        if not isinstance(date1, datetime) or not isinstance(date2, datetime):
            raise ValueError("Arguments must be datetime objects")
        
        diff = date1 - date2
        
        if unit == "days":
            return diff.days
        elif unit == "hours":
            return int(diff.total_seconds() / 3600)
        elif unit == "minutes":
            return int(diff.total_seconds() / 60)
        elif unit == "seconds":
            return int(diff.total_seconds())
        else:
            raise ValueError(f"Unsupported unit: {unit}")
    
    @staticmethod
    def format_date(date: datetime, format_string: str = "%Y-%m-%d") -> str:
        """Format date as string."""
        if not isinstance(date, datetime):
            raise ValueError("First argument must be a datetime")
        return date.strftime(format_string)


class LogicalFunctions:
    """Logical functions for formulas."""
    
    @staticmethod
    def if_condition(condition: bool, true_value: Any, false_value: Any) -> Any:
        """If condition."""
        return true_value if condition else false_value
    
    @staticmethod
    def and_condition(*args: bool) -> bool:
        """AND condition."""
        return all(args)
    
    @staticmethod
    def or_condition(*args: bool) -> bool:
        """OR condition."""
        return any(args)
    
    @staticmethod
    def not_condition(value: bool) -> bool:
        """NOT condition."""
        return not value
    
    @staticmethod
    def is_empty(value: Any) -> bool:
        """Check if value is empty."""
        if value is None:
            return True
        if isinstance(value, (str, list, dict)):
            return len(value) == 0
        return False
    
    @staticmethod
    def is_number(value: Any) -> bool:
        """Check if value is a number."""
        return isinstance(value, (int, float, Decimal))


class FormulaParser:
    """Parses formula expressions into executable form."""
    
    def __init__(self):
        self.functions = {
            # Math functions
            "SUM": MathFunctions.sum,
            "AVERAGE": MathFunctions.average,
            "MIN": MathFunctions.min,
            "MAX": MathFunctions.max,
            "ROUND": MathFunctions.round,
            "ABS": MathFunctions.abs,
            "SQRT": MathFunctions.sqrt,
            "POWER": MathFunctions.power,
            
            # Text functions
            "CONCATENATE": TextFunctions.concatenate,
            "UPPER": TextFunctions.upper,
            "LOWER": TextFunctions.lower,
            "LENGTH": TextFunctions.length,
            "SUBSTRING": TextFunctions.substring,
            "REPLACE": TextFunctions.replace,
            "TRIM": TextFunctions.trim,
            "CONTAINS": TextFunctions.contains,
            
            # Date functions
            "NOW": DateFunctions.now,
            "TODAY": DateFunctions.today,
            "DATEADD": DateFunctions.date_add,
            "DATEDIFF": DateFunctions.date_diff,
            "FORMATDATE": DateFunctions.format_date,
            
            # Logical functions
            "IF": LogicalFunctions.if_condition,
            "AND": LogicalFunctions.and_condition,
            "OR": LogicalFunctions.or_condition,
            "NOT": LogicalFunctions.not_condition,
            "ISEMPTY": LogicalFunctions.is_empty,
            "ISNUMBER": LogicalFunctions.is_number,
        }
        
        self.operators = {
            "+": operator.add,
            "-": operator.sub,
            "*": operator.mul,
            "/": operator.truediv,
            "//": operator.floordiv,
            "%": operator.mod,
            "**": operator.pow,
            "==": operator.eq,
            "!=": operator.ne,
            "<": operator.lt,
            "<=": operator.le,
            ">": operator.gt,
            ">=": operator.ge,
            "&": operator.and_,
            "|": operator.or_,
        }
    
    def parse(self, formula: str) -> Dict[str, Any]:
        """Parse formula into executable form."""
        try:
            # Clean the formula
            formula = formula.strip()
            if not formula:
                raise ValueError("Empty formula")
            
            # Parse variables (field references)
            variables = self._extract_variables(formula)
            
            # Validate syntax
            self._validate_syntax(formula)
            
            # Convert to Python expression
            python_expr = self._convert_to_python(formula)
            
            return {
                "original": formula,
                "python_expression": python_expr,
                "variables": variables,
                "functions_used": self._extract_functions(formula),
            }
            
        except Exception as e:
            logger.error(f"Formula parsing error: {e}", formula=formula)
            raise BusinessLogicError(f"Invalid formula: {e}")
    
    def _extract_variables(self, formula: str) -> Set[str]:
        """Extract field references from formula."""
        # Field references are in format {field_name} or [field_name]
        pattern = r'[{\[]([^}\]]+)[}\]]'
        matches = re.findall(pattern, formula)
        return set(matches)
    
    def _extract_functions(self, formula: str) -> Set[str]:
        """Extract function names from formula."""
        pattern = r'([A-Z_]+)\s*\('
        matches = re.findall(pattern, formula.upper())
        return set(match for match in matches if match in self.functions)
    
    def _validate_syntax(self, formula: str) -> None:
        """Validate formula syntax."""
        # Check for balanced parentheses
        if formula.count('(') != formula.count(')'):
            raise ValueError("Unbalanced parentheses")
        
        # Check for balanced brackets
        if formula.count('[') != formula.count(']'):
            raise ValueError("Unbalanced brackets")
        
        # Check for balanced braces
        if formula.count('{') != formula.count('}'):
            raise ValueError("Unbalanced braces")
    
    def _convert_to_python(self, formula: str) -> str:
        """Convert formula to Python expression."""
        # Replace field references {field} with context['field']
        formula = re.sub(r'{([^}]+)}', r'context["\1"]', formula)
        formula = re.sub(r'\[([^\]]+)\]', r'context["\1"]', formula)
        
        # Replace function calls
        for func_name in self.functions:
            pattern = rf'\b{func_name}\s*\('
            replacement = f'functions["{func_name}"]('
            formula = re.sub(pattern, replacement, formula, flags=re.IGNORECASE)
        
        return formula


class FormulaEvaluator:
    """Evaluates parsed formulas with context data."""
    
    def __init__(self, parser: Optional[FormulaParser] = None):
        self.parser = parser or FormulaParser()
        self.safe_names = {
            "__builtins__": {},
            "functions": self.parser.functions,
            "operators": self.parser.operators,
        }
    
    def evaluate(self, formula: str, context: Dict[str, Any]) -> FormulaResult:
        """Evaluate formula with given context."""
        try:
            # Parse formula
            parsed = self.parser.parse(formula)
            
            # Check if all required variables are in context
            missing_vars = parsed["variables"] - set(context.keys())
            if missing_vars:
                return FormulaResult(
                    value=None,
                    data_type=DataType.OBJECT,
                    is_valid=False,
                    error_message=f"Missing variables: {', '.join(missing_vars)}"
                )
            
            # Prepare evaluation context
            eval_context = {
                **self.safe_names,
                "context": context,
            }
            
            # Evaluate expression
            result = eval(parsed["python_expression"], eval_context)
            
            # Determine data type
            data_type = self._infer_data_type(result)
            
            return FormulaResult(
                value=result,
                data_type=data_type,
                is_valid=True
            )
            
        except Exception as e:
            logger.error(f"Formula evaluation error: {e}", formula=formula, context=context)
            return FormulaResult(
                value=None,
                data_type=DataType.OBJECT,
                is_valid=False,
                error_message=str(e)
            )
    
    def _infer_data_type(self, value: Any) -> DataType:
        """Infer data type from value."""
        if isinstance(value, bool):
            return DataType.BOOLEAN
        elif isinstance(value, (int, float, Decimal)):
            return DataType.NUMBER
        elif isinstance(value, str):
            return DataType.TEXT
        elif isinstance(value, datetime):
            return DataType.DATE
        elif isinstance(value, (list, tuple)):
            return DataType.ARRAY
        else:
            return DataType.OBJECT


class FormulaEngine:
    """Main formula engine combining parsing and evaluation."""
    
    def __init__(self):
        self.parser = FormulaParser()
        self.evaluator = FormulaEvaluator(self.parser)
        self._compiled_formulas: Dict[str, Dict[str, Any]] = {}
    
    def compile_formula(self, name: str, formula: str) -> None:
        """Compile and cache a formula."""
        try:
            parsed = self.parser.parse(formula)
            self._compiled_formulas[name] = parsed
            logger.info(f"Formula compiled successfully", name=name, formula=formula)
        except Exception as e:
            logger.error(f"Formula compilation failed", name=name, formula=formula, error=str(e))
            raise
    
    def execute_formula(self, name: str, context: Dict[str, Any]) -> FormulaResult:
        """Execute a compiled formula."""
        if name not in self._compiled_formulas:
            raise BusinessLogicError(f"Formula '{name}' not found")
        
        compiled_formula = self._compiled_formulas[name]
        return self.evaluator.evaluate(compiled_formula["original"], context)
    
    def execute_formula_direct(self, formula: str, context: Dict[str, Any]) -> FormulaResult:
        """Execute formula directly without compilation."""
        return self.evaluator.evaluate(formula, context)
    
    def list_compiled_formulas(self) -> List[str]:
        """List all compiled formulas."""
        return list(self._compiled_formulas.keys())
    
    def get_formula_info(self, name: str) -> Optional[Dict[str, Any]]:
        """Get information about a compiled formula."""
        return self._compiled_formulas.get(name)
    
    def validate_formula(self, formula: str) -> Dict[str, Any]:
        """Validate formula syntax and return analysis."""
        try:
            parsed = self.parser.parse(formula)
            return {
                "is_valid": True,
                "variables": list(parsed["variables"]),
                "functions": list(parsed["functions_used"]),
                "complexity_score": self._calculate_complexity(formula)
            }
        except Exception as e:
            return {
                "is_valid": False,
                "error": str(e),
                "variables": [],
                "functions": [],
                "complexity_score": 0
            }
    
    def _calculate_complexity(self, formula: str) -> int:
        """Calculate formula complexity score."""
        score = 0
        score += len(re.findall(r'[+\-*/]', formula))  # Operators
        score += len(re.findall(r'[A-Z_]+\s*\(', formula))  # Functions
        score += len(re.findall(r'if|and|or|not', formula, re.IGNORECASE))  # Logic
        score += formula.count('(')  # Nesting level
        return score