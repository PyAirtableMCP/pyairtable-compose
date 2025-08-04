"""Calculation service for complex business calculations and aggregations."""

import asyncio
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional, Union, Callable, Tuple
from dataclasses import dataclass, field
from enum import Enum
from collections import defaultdict

from .formula_engine import FormulaEngine, FormulaResult
from ...core.logging import get_logger
from ...utils.exceptions import BusinessLogicError
from ...utils.redis_client import RedisCache

logger = get_logger(__name__)


class AggregationType(Enum):
    """Types of aggregation operations."""
    SUM = "sum"
    AVERAGE = "average"
    COUNT = "count"
    MIN = "min"
    MAX = "max"
    MEDIAN = "median"
    MODE = "mode"
    STANDARD_DEVIATION = "std_dev"
    VARIANCE = "variance"
    PERCENTILE = "percentile"


class CalculationType(Enum):
    """Types of calculations."""
    SIMPLE = "simple"
    AGGREGATE = "aggregate"
    FORMULA = "formula"
    CONDITIONAL = "conditional"
    TIME_BASED = "time_based"
    STATISTICAL = "statistical"


@dataclass
class CalculationRequest:
    """Request for a calculation."""
    calculation_type: CalculationType
    operation: str
    data: Union[List[Dict[str, Any]], Dict[str, Any]]
    parameters: Dict[str, Any] = field(default_factory=dict)
    context: Dict[str, Any] = field(default_factory=dict)
    cache_key: Optional[str] = None
    cache_ttl: int = 300  # 5 minutes default


@dataclass
class CalculationResult:
    """Result of a calculation."""
    value: Any
    calculation_type: CalculationType
    operation: str
    is_cached: bool = False
    calculation_time_ms: Optional[int] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    warnings: List[str] = field(default_factory=list)
    intermediate_results: Dict[str, Any] = field(default_factory=dict)


class StatisticalCalculations:
    """Statistical calculation methods."""
    
    @staticmethod
    def mean(values: List[Union[int, float]]) -> float:
        """Calculate mean/average."""
        if not values:
            return 0.0
        return sum(values) / len(values)
    
    @staticmethod
    def median(values: List[Union[int, float]]) -> float:
        """Calculate median."""
        if not values:
            return 0.0
        
        sorted_values = sorted(values)
        n = len(sorted_values)
        
        if n % 2 == 0:
            return (sorted_values[n // 2 - 1] + sorted_values[n // 2]) / 2
        else:
            return sorted_values[n // 2]
    
    @staticmethod
    def mode(values: List[Union[int, float]]) -> Union[float, List[float]]:
        """Calculate mode(s)."""
        if not values:
            return 0.0
        
        frequency = defaultdict(int)
        for value in values:
            frequency[value] += 1
        
        max_freq = max(frequency.values())
        modes = [value for value, freq in frequency.items() if freq == max_freq]
        
        return modes[0] if len(modes) == 1 else modes
    
    @staticmethod
    def variance(values: List[Union[int, float]], sample: bool = True) -> float:
        """Calculate variance."""
        if len(values) < 2:
            return 0.0
        
        mean_value = StatisticalCalculations.mean(values)
        squared_diffs = [(x - mean_value) ** 2 for x in values]
        
        divisor = len(values) - 1 if sample else len(values)
        return sum(squared_diffs) / divisor
    
    @staticmethod
    def standard_deviation(values: List[Union[int, float]], sample: bool = True) -> float:
        """Calculate standard deviation."""
        return StatisticalCalculations.variance(values, sample) ** 0.5
    
    @staticmethod
    def percentile(values: List[Union[int, float]], percentile: float) -> float:
        """Calculate percentile."""
        if not values:
            return 0.0
        
        if not 0 <= percentile <= 100:
            raise ValueError("Percentile must be between 0 and 100")
        
        sorted_values = sorted(values)
        n = len(sorted_values)
        
        if percentile == 100:
            return sorted_values[-1]
        
        index = (percentile / 100) * (n - 1)
        lower_index = int(index)
        upper_index = min(lower_index + 1, n - 1)
        weight = index - lower_index
        
        return sorted_values[lower_index] + weight * (sorted_values[upper_index] - sorted_values[lower_index])
    
    @staticmethod
    def correlation(x_values: List[Union[int, float]], y_values: List[Union[int, float]]) -> float:
        """Calculate Pearson correlation coefficient."""
        if len(x_values) != len(y_values) or len(x_values) < 2:
            return 0.0
        
        n = len(x_values)
        mean_x = StatisticalCalculations.mean(x_values)
        mean_y = StatisticalCalculations.mean(y_values)
        
        numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(x_values, y_values))
        sum_sq_x = sum((x - mean_x) ** 2 for x in x_values)
        sum_sq_y = sum((y - mean_y) ** 2 for y in y_values)
        
        denominator = (sum_sq_x * sum_sq_y) ** 0.5
        
        return numerator / denominator if denominator != 0 else 0.0


class AggregationCalculations:
    """Aggregation calculation methods."""
    
    @staticmethod
    def aggregate_by_field(data: List[Dict[str, Any]], field: str, 
                          aggregation: AggregationType) -> Any:
        """Aggregate data by a specific field."""
        values = []
        for record in data:
            value = record.get(field)
            if value is not None:
                try:
                    if isinstance(value, (int, float)):
                        values.append(float(value))
                    elif isinstance(value, str) and value.replace('.', '').replace('-', '').isdigit():
                        values.append(float(value))
                except (ValueError, TypeError):
                    continue
        
        if not values and aggregation != AggregationType.COUNT:
            return None
        
        if aggregation == AggregationType.SUM:
            return sum(values)
        elif aggregation == AggregationType.AVERAGE:
            return StatisticalCalculations.mean(values)
        elif aggregation == AggregationType.COUNT:
            return len(data)
        elif aggregation == AggregationType.MIN:
            return min(values) if values else None
        elif aggregation == AggregationType.MAX:
            return max(values) if values else None
        elif aggregation == AggregationType.MEDIAN:
            return StatisticalCalculations.median(values)
        elif aggregation == AggregationType.MODE:
            return StatisticalCalculations.mode(values)
        elif aggregation == AggregationType.STANDARD_DEVIATION:
            return StatisticalCalculations.standard_deviation(values)
        elif aggregation == AggregationType.VARIANCE:
            return StatisticalCalculations.variance(values)
        else:
            raise ValueError(f"Unsupported aggregation type: {aggregation}")
    
    @staticmethod
    def group_by_and_aggregate(data: List[Dict[str, Any]], group_by: str, 
                              aggregate_field: str, aggregation: AggregationType) -> Dict[str, Any]:
        """Group data and apply aggregation."""
        groups = defaultdict(list)
        
        for record in data:
            group_value = record.get(group_by, 'Unknown')
            groups[str(group_value)].append(record)
        
        results = {}
        for group_key, group_data in groups.items():
            results[group_key] = AggregationCalculations.aggregate_by_field(
                group_data, aggregate_field, aggregation
            )
        
        return results
    
    @staticmethod
    def multi_field_aggregation(data: List[Dict[str, Any]], 
                               aggregations: Dict[str, AggregationType]) -> Dict[str, Any]:
        """Apply multiple aggregations to different fields."""
        results = {}
        
        for field, aggregation in aggregations.items():
            results[f"{field}_{aggregation.value}"] = AggregationCalculations.aggregate_by_field(
                data, field, aggregation
            )
        
        return results


class TimeBasedCalculations:
    """Time-based calculation methods."""
    
    @staticmethod
    def time_series_aggregation(data: List[Dict[str, Any]], date_field: str, 
                               value_field: str, period: str = "day") -> Dict[str, Any]:
        """Aggregate data by time periods."""
        if period not in ["hour", "day", "week", "month", "year"]:
            raise ValueError(f"Unsupported period: {period}")
        
        groups = defaultdict(list)
        
        for record in data:
            date_value = record.get(date_field)
            if not date_value:
                continue
            
            # Convert to datetime if string
            if isinstance(date_value, str):
                try:
                    date_value = datetime.fromisoformat(date_value.replace('Z', '+00:00'))
                except ValueError:
                    continue
            
            # Group by period
            if period == "hour":
                key = date_value.replace(minute=0, second=0, microsecond=0)
            elif period == "day":
                key = date_value.date()
            elif period == "week":
                key = date_value.date() - timedelta(days=date_value.weekday())
            elif period == "month":
                key = date_value.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
            elif period == "year":
                key = date_value.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
            
            groups[str(key)].append(record)
        
        results = {}
        for period_key, period_data in groups.items():
            results[period_key] = {
                "count": len(period_data),
                "sum": AggregationCalculations.aggregate_by_field(
                    period_data, value_field, AggregationType.SUM
                ),
                "average": AggregationCalculations.aggregate_by_field(
                    period_data, value_field, AggregationType.AVERAGE
                ),
            }
        
        return results
    
    @staticmethod
    def calculate_growth_rate(current_value: float, previous_value: float) -> float:
        """Calculate growth rate between two values."""
        if previous_value == 0:
            return 0.0 if current_value == 0 else float('inf')
        
        return ((current_value - previous_value) / previous_value) * 100
    
    @staticmethod
    def moving_average(values: List[float], window_size: int) -> List[float]:
        """Calculate moving average."""
        if window_size <= 0 or window_size > len(values):
            return values.copy()
        
        moving_averages = []
        for i in range(len(values) - window_size + 1):
            window = values[i:i + window_size]
            moving_averages.append(sum(window) / window_size)
        
        return moving_averages


class CalculationService:
    """Main calculation service."""
    
    def __init__(self, cache: Optional[RedisCache] = None):
        self.cache = cache or RedisCache()
        self.formula_engine = FormulaEngine()
        self._registered_calculators: Dict[str, Callable] = {}
        self._setup_default_calculators()
    
    def _setup_default_calculators(self) -> None:
        """Set up default calculation methods."""
        # Statistical calculators
        self._registered_calculators["mean"] = StatisticalCalculations.mean
        self._registered_calculators["median"] = StatisticalCalculations.median
        self._registered_calculators["mode"] = StatisticalCalculations.mode
        self._registered_calculators["variance"] = StatisticalCalculations.variance
        self._registered_calculators["std_dev"] = StatisticalCalculations.standard_deviation
        self._registered_calculators["percentile"] = StatisticalCalculations.percentile
        self._registered_calculators["correlation"] = StatisticalCalculations.correlation
        
        # Aggregation calculators
        self._registered_calculators["aggregate"] = AggregationCalculations.aggregate_by_field
        self._registered_calculators["group_aggregate"] = AggregationCalculations.group_by_and_aggregate
        self._registered_calculators["multi_aggregate"] = AggregationCalculations.multi_field_aggregation
        
        # Time-based calculators
        self._registered_calculators["time_series"] = TimeBasedCalculations.time_series_aggregation
        self._registered_calculators["growth_rate"] = TimeBasedCalculations.calculate_growth_rate
        self._registered_calculators["moving_average"] = TimeBasedCalculations.moving_average
    
    def register_calculator(self, name: str, calculator_func: Callable) -> None:
        """Register a custom calculator function."""
        self._registered_calculators[name] = calculator_func
        logger.info(f"Registered custom calculator: {name}")
    
    async def calculate(self, request: CalculationRequest) -> CalculationResult:
        """Perform calculation based on request."""
        start_time = datetime.now()
        
        # Check cache first
        if request.cache_key:
            cached_result = await self._get_cached_result(request.cache_key)
            if cached_result:
                return cached_result
        
        try:
            # Perform calculation based on type
            if request.calculation_type == CalculationType.FORMULA:
                result_value = await self._calculate_formula(request)
            elif request.calculation_type == CalculationType.AGGREGATE:
                result_value = await self._calculate_aggregate(request)
            elif request.calculation_type == CalculationType.STATISTICAL:
                result_value = await self._calculate_statistical(request)
            elif request.calculation_type == CalculationType.TIME_BASED:
                result_value = await self._calculate_time_based(request)
            elif request.calculation_type == CalculationType.CONDITIONAL:
                result_value = await self._calculate_conditional(request)
            else:
                result_value = await self._calculate_simple(request)
            
            # Calculate execution time
            execution_time = int((datetime.now() - start_time).total_seconds() * 1000)
            
            # Create result
            result = CalculationResult(
                value=result_value,
                calculation_type=request.calculation_type,
                operation=request.operation,
                calculation_time_ms=execution_time
            )
            
            # Cache result if requested
            if request.cache_key:
                await self._cache_result(request.cache_key, result, request.cache_ttl)
            
            logger.info(
                f"Calculation completed",
                operation=request.operation,
                type=request.calculation_type.value,
                execution_time_ms=execution_time
            )
            
            return result
            
        except Exception as e:
            logger.error(
                f"Calculation failed",
                operation=request.operation,
                type=request.calculation_type.value,
                error=str(e)
            )
            raise BusinessLogicError(f"Calculation failed: {e}")
    
    async def _calculate_formula(self, request: CalculationRequest) -> Any:
        """Calculate using formula engine."""
        formula = request.operation
        context = request.context
        
        # Add data to context if it's a single record
        if isinstance(request.data, dict):
            context.update(request.data)
        
        result = self.formula_engine.execute_formula_direct(formula, context)
        
        if not result.is_valid:
            raise BusinessLogicError(f"Formula error: {result.error_message}")
        
        return result.value
    
    async def _calculate_aggregate(self, request: CalculationRequest) -> Any:
        """Calculate aggregation."""
        if not isinstance(request.data, list):
            raise ValueError("Aggregate calculations require list data")
        
        operation_parts = request.operation.split(":")
        if len(operation_parts) != 2:
            raise ValueError("Aggregate operation format: 'field:aggregation_type'")
        
        field, agg_type = operation_parts
        aggregation = AggregationType(agg_type.lower())
        
        return AggregationCalculations.aggregate_by_field(request.data, field, aggregation)
    
    async def _calculate_statistical(self, request: CalculationRequest) -> Any:
        """Calculate statistical values."""
        if request.operation not in self._registered_calculators:
            raise ValueError(f"Unknown statistical operation: {request.operation}")
        
        calculator = self._registered_calculators[request.operation]
        
        # Extract values based on parameters
        if "field" in request.parameters:
            field = request.parameters["field"]
            values = [record.get(field) for record in request.data if record.get(field) is not None]
            values = [float(v) for v in values if isinstance(v, (int, float)) or 
                     (isinstance(v, str) and v.replace('.', '').replace('-', '').isdigit())]
        else:
            values = request.data
        
        # Call calculator with appropriate parameters
        if request.operation == "percentile":
            percentile = request.parameters.get("percentile", 50)
            return calculator(values, percentile)
        elif request.operation in ["variance", "std_dev"]:
            sample = request.parameters.get("sample", True)
            return calculator(values, sample)
        else:
            return calculator(values)
    
    async def _calculate_time_based(self, request: CalculationRequest) -> Any:
        """Calculate time-based values."""
        if request.operation not in self._registered_calculators:
            raise ValueError(f"Unknown time-based operation: {request.operation}")
        
        calculator = self._registered_calculators[request.operation]
        
        if request.operation == "time_series":
            date_field = request.parameters.get("date_field", "created_at")
            value_field = request.parameters.get("value_field", "value")
            period = request.parameters.get("period", "day")
            return calculator(request.data, date_field, value_field, period)
        elif request.operation == "growth_rate":
            current = request.parameters.get("current_value")
            previous = request.parameters.get("previous_value")
            return calculator(current, previous)
        elif request.operation == "moving_average":
            window_size = request.parameters.get("window_size", 5)
            return calculator(request.data, window_size)
        else:
            return calculator(request.data, **request.parameters)
    
    async def _calculate_conditional(self, request: CalculationRequest) -> Any:
        """Calculate conditional values."""
        conditions = request.parameters.get("conditions", [])
        default_value = request.parameters.get("default_value", 0)
        
        for condition in conditions:
            condition_formula = condition.get("condition")
            value_formula = condition.get("value")
            
            if not condition_formula or not value_formula:
                continue
            
            # Evaluate condition
            condition_result = self.formula_engine.execute_formula_direct(
                condition_formula, request.context
            )
            
            if condition_result.is_valid and condition_result.value:
                # Evaluate value
                value_result = self.formula_engine.execute_formula_direct(
                    value_formula, request.context
                )
                
                if value_result.is_valid:
                    return value_result.value
        
        return default_value
    
    async def _calculate_simple(self, request: CalculationRequest) -> Any:
        """Calculate simple operations."""
        if request.operation not in self._registered_calculators:
            raise ValueError(f"Unknown operation: {request.operation}")
        
        calculator = self._registered_calculators[request.operation]
        return calculator(request.data, **request.parameters)
    
    async def _get_cached_result(self, cache_key: str) -> Optional[CalculationResult]:
        """Get cached calculation result."""
        try:
            cached_data = await self.cache.get(f"calc:{cache_key}")
            if cached_data:
                result = CalculationResult(**cached_data)
                result.is_cached = True
                return result
        except Exception as e:
            logger.warning(f"Cache retrieval failed", cache_key=cache_key, error=str(e))
        
        return None
    
    async def _cache_result(self, cache_key: str, result: CalculationResult, ttl: int) -> None:
        """Cache calculation result."""
        try:
            cache_data = {
                "value": result.value,
                "calculation_type": result.calculation_type,
                "operation": result.operation,
                "calculation_time_ms": result.calculation_time_ms,
                "metadata": result.metadata,
                "warnings": result.warnings,
                "intermediate_results": result.intermediate_results,
            }
            await self.cache.set(f"calc:{cache_key}", cache_data, ttl=ttl)
        except Exception as e:
            logger.warning(f"Cache storage failed", cache_key=cache_key, error=str(e))
    
    async def batch_calculate(self, requests: List[CalculationRequest]) -> List[CalculationResult]:
        """Perform multiple calculations concurrently."""
        tasks = [self.calculate(request) for request in requests]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Convert exceptions to error results
        final_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                error_result = CalculationResult(
                    value=None,
                    calculation_type=requests[i].calculation_type,
                    operation=requests[i].operation,
                    warnings=[f"Calculation failed: {str(result)}"]
                )
                final_results.append(error_result)
            else:
                final_results.append(result)
        
        return final_results
    
    def list_available_operations(self) -> Dict[str, List[str]]:
        """List all available calculation operations."""
        return {
            "registered_calculators": list(self._registered_calculators.keys()),
            "aggregation_types": [agg.value for agg in AggregationType],
            "calculation_types": [calc.value for calc in CalculationType],
        }