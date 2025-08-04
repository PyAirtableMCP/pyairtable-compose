"""Core dashboard engine with widgets and real-time data."""

import asyncio
import json
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Union, Callable, Set
from dataclasses import dataclass, field
from enum import Enum
from abc import ABC, abstractmethod

from ..business_logic import CalculationService
from ...core.logging import get_logger
from ...utils.exceptions import BusinessLogicError
from ...utils.redis_client import RedisCache
from ...services.airtable_service import AirtableService

logger = get_logger(__name__)


class WidgetType(Enum):
    """Types of dashboard widgets."""
    METRIC = "metric"
    CHART = "chart"
    TABLE = "table"
    TEXT = "text"
    PROGRESS = "progress"
    GAUGE = "gauge"
    HEATMAP = "heatmap"
    TIMELINE = "timeline"
    MAP = "map"
    IFRAME = "iframe"


class ChartType(Enum):
    """Types of charts."""
    LINE = "line"
    BAR = "bar"
    PIE = "pie"
    DONUT = "donut"
    AREA = "area"
    SCATTER = "scatter"
    HISTOGRAM = "histogram"
    CANDLESTICK = "candlestick"


class RefreshMode(Enum):
    """Widget refresh modes."""
    MANUAL = "manual"
    SCHEDULED = "scheduled"
    REALTIME = "realtime"
    ON_DEMAND = "on_demand"


@dataclass
class WidgetDataSource:
    """Data source configuration for a widget."""
    source_type: str  # airtable, database, api, formula
    configuration: Dict[str, Any] = field(default_factory=dict)
    query: Optional[str] = None
    filters: Dict[str, Any] = field(default_factory=dict)
    transformations: List[str] = field(default_factory=list)
    cache_ttl: int = 300  # 5 minutes default
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary representation."""
        return {
            "source_type": self.source_type,
            "configuration": self.configuration,
            "query": self.query,
            "filters": self.filters,
            "transformations": self.transformations,
            "cache_ttl": self.cache_ttl
        }


@dataclass
class WidgetLayout:
    """Layout configuration for a widget."""
    x: int = 0
    y: int = 0
    width: int = 4
    height: int = 3
    min_width: int = 2
    min_height: int = 2
    max_width: Optional[int] = None
    max_height: Optional[int] = None
    is_resizable: bool = True
    is_draggable: bool = True


class Widget:
    """Individual dashboard widget."""
    
    def __init__(self, widget_id: str, title: str, widget_type: WidgetType):
        self.widget_id = widget_id
        self.title = title
        self.widget_type = widget_type
        self.description = ""
        self.data_source: Optional[WidgetDataSource] = None
        self.layout = WidgetLayout()
        self.configuration: Dict[str, Any] = {}
        self.refresh_mode = RefreshMode.MANUAL
        self.refresh_interval: Optional[int] = None  # seconds
        self.last_refresh: Optional[datetime] = None
        self.last_data: Optional[Any] = None
        self.enabled = True
        self.created_at = datetime.now()
        self.updated_at = datetime.now()
    
    def set_data_source(self, source_type: str, **configuration) -> 'Widget':
        """Set the data source for the widget."""
        self.data_source = WidgetDataSource(
            source_type=source_type,
            configuration=configuration
        )
        self.updated_at = datetime.now()
        return self
    
    def set_layout(self, x: int = 0, y: int = 0, width: int = 4, height: int = 3, **kwargs) -> 'Widget':
        """Set the layout for the widget."""
        self.layout = WidgetLayout(x=x, y=y, width=width, height=height, **kwargs)
        self.updated_at = datetime.now()
        return self
    
    def set_refresh(self, mode: RefreshMode, interval: Optional[int] = None) -> 'Widget':
        """Set refresh configuration."""
        self.refresh_mode = mode
        self.refresh_interval = interval
        self.updated_at = datetime.now()
        return self
    
    def configure(self, **configuration) -> 'Widget':
        """Set widget configuration."""
        self.configuration.update(configuration)
        self.updated_at = datetime.now()
        return self
    
    def needs_refresh(self) -> bool:
        """Check if widget needs refresh based on its configuration."""
        if not self.enabled:
            return False
        
        if self.refresh_mode == RefreshMode.MANUAL:
            return False
        elif self.refresh_mode == RefreshMode.REALTIME:
            return True
        elif self.refresh_mode == RefreshMode.SCHEDULED and self.refresh_interval:
            if not self.last_refresh:
                return True
            return (datetime.now() - self.last_refresh).total_seconds() >= self.refresh_interval
        
        return False
    
    def mark_refreshed(self, data: Any) -> None:
        """Mark widget as refreshed with new data."""
        self.last_refresh = datetime.now()
        self.last_data = data
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert widget to dictionary."""
        return {
            "widget_id": self.widget_id,
            "title": self.title,
            "widget_type": self.widget_type.value,
            "description": self.description,
            "data_source": {
                "source_type": self.data_source.source_type,
                "configuration": self.data_source.configuration,
                "query": self.data_source.query,
                "filters": self.data_source.filters,
                "transformations": self.data_source.transformations,
                "cache_ttl": self.data_source.cache_ttl
            } if self.data_source else None,
            "layout": {
                "x": self.layout.x,
                "y": self.layout.y,
                "width": self.layout.width,
                "height": self.layout.height,
                "min_width": self.layout.min_width,
                "min_height": self.layout.min_height,
                "max_width": self.layout.max_width,
                "max_height": self.layout.max_height,
                "is_resizable": self.layout.is_resizable,
                "is_draggable": self.layout.is_draggable
            },
            "configuration": self.configuration,
            "refresh_mode": self.refresh_mode.value,
            "refresh_interval": self.refresh_interval,
            "last_refresh": self.last_refresh.isoformat() if self.last_refresh else None,
            "enabled": self.enabled,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat()
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Widget':
        """Create widget from dictionary."""
        widget = cls(
            widget_id=data["widget_id"],
            title=data["title"],
            widget_type=WidgetType(data["widget_type"])
        )
        
        widget.description = data.get("description", "")
        widget.configuration = data.get("configuration", {})
        widget.refresh_mode = RefreshMode(data.get("refresh_mode", "manual"))
        widget.refresh_interval = data.get("refresh_interval")
        widget.enabled = data.get("enabled", True)
        
        # Set data source
        if data.get("data_source"):
            ds_data = data["data_source"]
            widget.data_source = WidgetDataSource(
                source_type=ds_data["source_type"],
                configuration=ds_data.get("configuration", {}),
                query=ds_data.get("query"),
                filters=ds_data.get("filters", {}),
                transformations=ds_data.get("transformations", []),
                cache_ttl=ds_data.get("cache_ttl", 300)
            )
        
        # Set layout
        if data.get("layout"):
            layout_data = data["layout"]
            widget.layout = WidgetLayout(
                x=layout_data.get("x", 0),
                y=layout_data.get("y", 0),
                width=layout_data.get("width", 4),
                height=layout_data.get("height", 3),
                min_width=layout_data.get("min_width", 2),
                min_height=layout_data.get("min_height", 2),
                max_width=layout_data.get("max_width"),
                max_height=layout_data.get("max_height"),
                is_resizable=layout_data.get("is_resizable", True),
                is_draggable=layout_data.get("is_draggable", True)
            )
        
        # Set timestamps
        if data.get("last_refresh"):
            widget.last_refresh = datetime.fromisoformat(data["last_refresh"])
        if data.get("created_at"):
            widget.created_at = datetime.fromisoformat(data["created_at"])
        if data.get("updated_at"):
            widget.updated_at = datetime.fromisoformat(data["updated_at"])
        
        return widget


class Dashboard:
    """Dashboard containing multiple widgets."""
    
    def __init__(self, dashboard_id: str, name: str):
        self.dashboard_id = dashboard_id
        self.name = name
        self.description = ""
        self.widgets: Dict[str, Widget] = {}
        self.layout_columns = 12  # Grid system columns
        self.auto_refresh = True
        self.refresh_interval = 30  # seconds
        self.last_refresh: Optional[datetime] = None
        self.tags: List[str] = []
        self.is_public = False
        self.owner_id: Optional[str] = None
        self.shared_with: List[str] = []
        self.created_at = datetime.now()
        self.updated_at = datetime.now()
    
    def add_widget(self, widget: Widget) -> 'Dashboard':
        """Add a widget to the dashboard."""
        self.widgets[widget.widget_id] = widget
        self.updated_at = datetime.now()
        return self
    
    def remove_widget(self, widget_id: str) -> bool:
        """Remove a widget from the dashboard."""
        if widget_id in self.widgets:
            del self.widgets[widget_id]
            self.updated_at = datetime.now()
            return True
        return False
    
    def get_widget(self, widget_id: str) -> Optional[Widget]:
        """Get a widget by ID."""
        return self.widgets.get(widget_id)
    
    def list_widgets(self, widget_type: Optional[WidgetType] = None, enabled_only: bool = True) -> List[Widget]:
        """List widgets, optionally filtered."""
        widgets = list(self.widgets.values())
        
        if enabled_only:
            widgets = [w for w in widgets if w.enabled]
        
        if widget_type:
            widgets = [w for w in widgets if w.widget_type == widget_type]
        
        # Sort by layout position
        widgets.sort(key=lambda w: (w.layout.y, w.layout.x))
        
        return widgets
    
    def get_widgets_needing_refresh(self) -> List[Widget]:
        """Get widgets that need refresh."""
        return [widget for widget in self.widgets.values() if widget.needs_refresh()]
    
    def update_layout(self, widget_id: str, layout_update: Dict[str, Any]) -> bool:
        """Update widget layout."""
        widget = self.get_widget(widget_id)
        if not widget:
            return False
        
        for key, value in layout_update.items():
            if hasattr(widget.layout, key):
                setattr(widget.layout, key, value)
        
        widget.updated_at = datetime.now()
        self.updated_at = datetime.now()
        return True
    
    def needs_refresh(self) -> bool:
        """Check if dashboard needs refresh."""
        if not self.auto_refresh:
            return False
        
        if not self.last_refresh:
            return True
        
        return (datetime.now() - self.last_refresh).total_seconds() >= self.refresh_interval
    
    def mark_refreshed(self) -> None:
        """Mark dashboard as refreshed."""
        self.last_refresh = datetime.now()
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert dashboard to dictionary."""
        return {
            "dashboard_id": self.dashboard_id,
            "name": self.name,
            "description": self.description,
            "widgets": {widget_id: widget.to_dict() for widget_id, widget in self.widgets.items()},
            "layout_columns": self.layout_columns,
            "auto_refresh": self.auto_refresh,
            "refresh_interval": self.refresh_interval,
            "last_refresh": self.last_refresh.isoformat() if self.last_refresh else None,
            "tags": self.tags,
            "is_public": self.is_public,
            "owner_id": self.owner_id,
            "shared_with": self.shared_with,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat()
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Dashboard':
        """Create dashboard from dictionary."""
        dashboard = cls(
            dashboard_id=data["dashboard_id"],
            name=data["name"]
        )
        
        dashboard.description = data.get("description", "")
        dashboard.layout_columns = data.get("layout_columns", 12)
        dashboard.auto_refresh = data.get("auto_refresh", True)
        dashboard.refresh_interval = data.get("refresh_interval", 30)
        dashboard.tags = data.get("tags", [])
        dashboard.is_public = data.get("is_public", False)
        dashboard.owner_id = data.get("owner_id")
        dashboard.shared_with = data.get("shared_with", [])
        
        # Add widgets
        for widget_data in data.get("widgets", {}).values():
            widget = Widget.from_dict(widget_data)
            dashboard.add_widget(widget)
        
        # Set timestamps
        if data.get("last_refresh"):
            dashboard.last_refresh = datetime.fromisoformat(data["last_refresh"])
        if data.get("created_at"):
            dashboard.created_at = datetime.fromisoformat(data["created_at"])
        if data.get("updated_at"):
            dashboard.updated_at = datetime.fromisoformat(data["updated_at"])
        
        return dashboard


class WidgetDataProcessor:
    """Processes data for different widget types."""
    
    def __init__(self, airtable_service: AirtableService, calculation_service: CalculationService):
        self.airtable_service = airtable_service
        self.calculation_service = calculation_service
    
    async def process_widget_data(self, widget: Widget, parameters: Optional[Dict[str, Any]] = None) -> Any:
        """Process data for a widget."""
        if not widget.data_source:
            return None
        
        # Fetch raw data
        raw_data = await self._fetch_raw_data(widget.data_source, parameters or {})
        
        # Process based on widget type
        if widget.widget_type == WidgetType.METRIC:
            return await self._process_metric_data(raw_data, widget.configuration)
        elif widget.widget_type == WidgetType.CHART:
            return await self._process_chart_data(raw_data, widget.configuration)
        elif widget.widget_type == WidgetType.TABLE:
            return await self._process_table_data(raw_data, widget.configuration)
        elif widget.widget_type == WidgetType.PROGRESS:
            return await self._process_progress_data(raw_data, widget.configuration)
        elif widget.widget_type == WidgetType.GAUGE:
            return await self._process_gauge_data(raw_data, widget.configuration)
        else:
            return raw_data
    
    async def _fetch_raw_data(self, data_source: WidgetDataSource, parameters: Dict[str, Any]) -> Any:
        """Fetch raw data from data source."""
        if data_source.source_type == "airtable":
            config = data_source.configuration
            base_id = config.get("base_id") or parameters.get("base_id")
            table_id = config.get("table_id") or parameters.get("table_id")
            
            if not base_id or not table_id:
                raise BusinessLogicError("Airtable data source requires base_id and table_id")
            
            # Build query parameters
            query_params = {}
            
            # Apply filters
            if data_source.filters.get("formula"):
                query_params["filter_by_formula"] = data_source.filters["formula"]
            
            if data_source.filters.get("view"):
                query_params["view"] = data_source.filters["view"]
            
            if data_source.filters.get("fields"):
                query_params["fields"] = data_source.filters["fields"]
            
            if data_source.filters.get("max_records"):
                query_params["max_records"] = data_source.filters["max_records"]
            
            # Fetch data
            result = await self.airtable_service.list_records(
                base_id=base_id,
                table_id=table_id,
                **query_params
            )
            
            return result.get("records", [])
        
        elif data_source.source_type == "formula":
            # Handle formula-based data sources
            return {"value": 0}  # Placeholder
        
        else:
            raise BusinessLogicError(f"Unsupported data source type: {data_source.source_type}")
    
    async def _process_metric_data(self, data: List[Dict[str, Any]], config: Dict[str, Any]) -> Dict[str, Any]:
        """Process data for metric widget."""
        metric_type = config.get("metric_type", "count")
        field = config.get("field")
        
        if metric_type == "count":
            value = len(data)
        elif metric_type == "sum" and field:
            value = sum(
                float(record.get("fields", {}).get(field, 0) or 0)
                for record in data
            )
        elif metric_type == "average" and field:
            values = [
                float(record.get("fields", {}).get(field, 0) or 0)
                for record in data
            ]
            value = sum(values) / len(values) if values else 0
        elif metric_type == "max" and field:
            values = [
                float(record.get("fields", {}).get(field, 0) or 0)
                for record in data
            ]
            value = max(values) if values else 0
        elif metric_type == "min" and field:
            values = [
                float(record.get("fields", {}).get(field, 0) or 0)
                for record in data
            ]
            value = min(values) if values else 0
        else:
            value = len(data)  # Default to count
        
        # Calculate trend if previous value is available
        trend = None
        previous_value = config.get("previous_value")
        if previous_value is not None:
            trend = {
                "direction": "up" if value > previous_value else "down" if value < previous_value else "flat",
                "percentage": ((value - previous_value) / previous_value * 100) if previous_value != 0 else 0,
                "absolute": value - previous_value
            }
        
        return {
            "value": value,
            "formatted_value": self._format_value(value, config.get("format")),
            "trend": trend,
            "metric_type": metric_type,
            "field": field
        }
    
    async def _process_chart_data(self, data: List[Dict[str, Any]], config: Dict[str, Any]) -> Dict[str, Any]:
        """Process data for chart widget."""
        chart_type = config.get("chart_type", ChartType.BAR.value)
        x_field = config.get("x_field")
        y_field = config.get("y_field")
        
        if not x_field or not y_field:
            return {"error": "Chart requires x_field and y_field configuration"}
        
        # Group and aggregate data
        chart_data = {}
        
        for record in data:
            fields = record.get("fields", {})
            x_value = str(fields.get(x_field, "Unknown"))
            y_value = fields.get(y_field, 0)
            
            try:
                y_value = float(y_value) if y_value is not None else 0
            except (ValueError, TypeError):
                y_value = 0
            
            if x_value not in chart_data:
                chart_data[x_value] = []
            chart_data[x_value].append(y_value)
        
        # Aggregate values
        aggregation = config.get("aggregation", "sum")
        aggregated_data = {}
        
        for x_value, y_values in chart_data.items():
            if aggregation == "sum":
                aggregated_data[x_value] = sum(y_values)
            elif aggregation == "average":
                aggregated_data[x_value] = sum(y_values) / len(y_values)
            elif aggregation == "count":
                aggregated_data[x_value] = len(y_values)
            elif aggregation == "max":
                aggregated_data[x_value] = max(y_values)
            elif aggregation == "min":
                aggregated_data[x_value] = min(y_values)
            else:
                aggregated_data[x_value] = sum(y_values)
        
        # Sort data if needed
        sort_by = config.get("sort_by", "x")
        if sort_by == "y":
            sorted_items = sorted(aggregated_data.items(), key=lambda x: x[1], reverse=config.get("sort_desc", False))
        else:
            sorted_items = sorted(aggregated_data.items(), key=lambda x: x[0])
        
        return {
            "chart_type": chart_type,
            "data": dict(sorted_items),
            "x_field": x_field,
            "y_field": y_field,
            "aggregation": aggregation,
            "labels": [item[0] for item in sorted_items],
            "values": [item[1] for item in sorted_items]
        }
    
    async def _process_table_data(self, data: List[Dict[str, Any]], config: Dict[str, Any]) -> Dict[str, Any]:
        """Process data for table widget."""
        # Apply limit
        limit = config.get("limit", 10)
        if limit > 0:
            data = data[:limit]
        
        # Apply sorting
        sort_field = config.get("sort_field")
        if sort_field:
            try:
                reverse = config.get("sort_desc", False)
                data = sorted(data, 
                            key=lambda x: x.get("fields", {}).get(sort_field, ""),
                            reverse=reverse)
            except Exception as e:
                logger.warning(f"Table sorting failed: {e}")
        
        # Filter columns
        columns = config.get("columns")
        if columns:
            filtered_data = []
            for record in data:
                filtered_record = {
                    "id": record.get("id"),
                    "createdTime": record.get("createdTime"),
                    "fields": {}
                }
                
                for column in columns:
                    field_name = column.get("field") if isinstance(column, dict) else column
                    if field_name in record.get("fields", {}):
                        filtered_record["fields"][field_name] = record["fields"][field_name]
                
                filtered_data.append(filtered_record)
            
            data = filtered_data
        
        return {
            "data": data,
            "total_count": len(data),
            "columns": columns or list(data[0].get("fields", {}).keys()) if data else []
        }
    
    async def _process_progress_data(self, data: List[Dict[str, Any]], config: Dict[str, Any]) -> Dict[str, Any]:
        """Process data for progress widget."""
        current_field = config.get("current_field")
        target_field = config.get("target_field")
        target_value = config.get("target_value")
        
        if not current_field:
            return {"error": "Progress widget requires current_field configuration"}
        
        # Calculate current value
        current_values = [
            float(record.get("fields", {}).get(current_field, 0) or 0)
            for record in data
        ]
        current = sum(current_values)
        
        # Get target value
        if target_field:
            target_values = [
                float(record.get("fields", {}).get(target_field, 0) or 0)
                for record in data
            ]
            target = sum(target_values)
        elif target_value:
            target = float(target_value)
        else:
            target = max(current_values) if current_values else 100
        
        # Calculate percentage
        percentage = (current / target * 100) if target > 0 else 0
        
        return {
            "current": current,
            "target": target,
            "percentage": min(percentage, 100),  # Cap at 100%
            "status": "complete" if percentage >= 100 else "in_progress",
            "formatted_current": self._format_value(current, config.get("format")),
            "formatted_target": self._format_value(target, config.get("format"))
        }
    
    async def _process_gauge_data(self, data: List[Dict[str, Any]], config: Dict[str, Any]) -> Dict[str, Any]:
        """Process data for gauge widget."""
        value_field = config.get("value_field")
        if not value_field:
            return {"error": "Gauge widget requires value_field configuration"}
        
        # Calculate value
        values = [
            float(record.get("fields", {}).get(value_field, 0) or 0)
            for record in data
        ]
        
        aggregation = config.get("aggregation", "sum")
        if aggregation == "sum":
            value = sum(values)
        elif aggregation == "average":
            value = sum(values) / len(values) if values else 0
        elif aggregation == "max":
            value = max(values) if values else 0
        elif aggregation == "min":
            value = min(values) if values else 0
        else:
            value = sum(values)
        
        # Get range configuration
        min_value = config.get("min_value", 0)
        max_value = config.get("max_value", 100)
        
        # Calculate percentage
        range_size = max_value - min_value
        percentage = ((value - min_value) / range_size * 100) if range_size > 0 else 0
        percentage = max(0, min(100, percentage))  # Clamp between 0 and 100
        
        # Determine status based on thresholds
        status = "normal"
        thresholds = config.get("thresholds", {})
        if "critical" in thresholds and value >= thresholds["critical"]:
            status = "critical"
        elif "warning" in thresholds and value >= thresholds["warning"]:
            status = "warning"
        elif "good" in thresholds and value >= thresholds["good"]:
            status = "good"
        
        return {
            "value": value,
            "percentage": percentage,
            "min_value": min_value,
            "max_value": max_value,
            "status": status,
            "thresholds": thresholds,
            "formatted_value": self._format_value(value, config.get("format"))
        }
    
    def _format_value(self, value: Union[int, float], format_type: Optional[str] = None) -> str:
        """Format value based on format type."""
        if format_type == "currency":
            return f"${value:,.2f}"
        elif format_type == "percentage":
            return f"{value:.1f}%"
        elif format_type == "integer":
            return f"{int(value):,}"
        elif format_type == "decimal":
            return f"{value:.2f}"
        else:
            return str(value)


class DashboardEngine:
    """Main dashboard engine."""
    
    def __init__(self, airtable_service: AirtableService, cache: Optional[RedisCache] = None):
        self.airtable_service = airtable_service
        self.cache = cache or RedisCache()
        self.calculation_service = CalculationService(cache)
        self.data_processor = WidgetDataProcessor(airtable_service, self.calculation_service)
        
        self.dashboards: Dict[str, Dashboard] = {}
        self.refresh_tasks: Dict[str, asyncio.Task] = {}
        
        # Start background refresh task
        self._refresh_task = asyncio.create_task(self._background_refresh())
    
    def create_dashboard(self, dashboard_id: str, name: str, **kwargs) -> Dashboard:
        """Create a new dashboard."""
        dashboard = Dashboard(dashboard_id, name)
        
        # Set optional properties
        for key, value in kwargs.items():
            if hasattr(dashboard, key):
                setattr(dashboard, key, value)
        
        self.dashboards[dashboard_id] = dashboard
        logger.info(f"Created dashboard: {dashboard_id}")
        return dashboard
    
    def get_dashboard(self, dashboard_id: str) -> Optional[Dashboard]:
        """Get a dashboard by ID."""
        return self.dashboards.get(dashboard_id)
    
    def list_dashboards(self, owner_id: Optional[str] = None, 
                       tags: Optional[List[str]] = None) -> List[Dashboard]:
        """List dashboards, optionally filtered."""
        dashboards = list(self.dashboards.values())
        
        if owner_id:
            dashboards = [d for d in dashboards if d.owner_id == owner_id]
        
        if tags:
            dashboards = [d for d in dashboards if any(tag in d.tags for tag in tags)]
        
        return sorted(dashboards, key=lambda d: d.updated_at, reverse=True)
    
    def delete_dashboard(self, dashboard_id: str) -> bool:
        """Delete a dashboard."""
        if dashboard_id in self.dashboards:
            # Cancel any refresh tasks
            if dashboard_id in self.refresh_tasks:
                self.refresh_tasks[dashboard_id].cancel()
                del self.refresh_tasks[dashboard_id]
            
            del self.dashboards[dashboard_id]
            logger.info(f"Deleted dashboard: {dashboard_id}")
            return True
        return False
    
    async def refresh_widget(self, dashboard_id: str, widget_id: str, 
                            parameters: Optional[Dict[str, Any]] = None) -> Any:
        """Refresh a specific widget."""
        dashboard = self.get_dashboard(dashboard_id)
        if not dashboard:
            raise BusinessLogicError(f"Dashboard {dashboard_id} not found")
        
        widget = dashboard.get_widget(widget_id)
        if not widget:
            raise BusinessLogicError(f"Widget {widget_id} not found")
        
        # Check cache first
        cache_key = self._generate_widget_cache_key(dashboard_id, widget_id, parameters)
        cached_data = await self.cache.get(cache_key)
        
        if cached_data and widget.data_source:
            logger.debug(f"Using cached data for widget {widget_id}")
            widget.mark_refreshed(cached_data)
            return cached_data
        
        # Process widget data
        try:
            data = await self.data_processor.process_widget_data(widget, parameters)
            widget.mark_refreshed(data)
            
            # Cache the result
            if widget.data_source:
                await self.cache.set(cache_key, data, ttl=widget.data_source.cache_ttl)
            
            logger.debug(f"Refreshed widget {widget_id} in dashboard {dashboard_id}")
            return data
            
        except Exception as e:
            logger.error(f"Widget refresh failed", dashboard_id=dashboard_id, widget_id=widget_id, error=str(e))
            raise BusinessLogicError(f"Widget refresh failed: {e}")
    
    async def refresh_dashboard(self, dashboard_id: str, 
                               parameters: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Refresh all widgets in a dashboard."""
        dashboard = self.get_dashboard(dashboard_id)
        if not dashboard:
            raise BusinessLogicError(f"Dashboard {dashboard_id} not found")
        
        start_time = datetime.now()
        results = {}
        errors = []
        
        # Refresh all enabled widgets
        widgets = dashboard.list_widgets(enabled_only=True)
        
        # Process widgets concurrently
        tasks = [
            self.refresh_widget(dashboard_id, widget.widget_id, parameters)
            for widget in widgets
        ]
        
        widget_results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Collect results and errors
        for i, result in enumerate(widget_results):
            widget_id = widgets[i].widget_id
            if isinstance(result, Exception):
                errors.append(f"Widget {widget_id}: {str(result)}")
                results[widget_id] = {"error": str(result)}
            else:
                results[widget_id] = result
        
        dashboard.mark_refreshed()
        
        refresh_time = int((datetime.now() - start_time).total_seconds() * 1000)
        
        logger.info(
            f"Dashboard refreshed",
            dashboard_id=dashboard_id,
            widgets_count=len(widgets),
            errors_count=len(errors),
            refresh_time_ms=refresh_time
        )
        
        return {
            "dashboard_id": dashboard_id,
            "widgets": results,
            "refresh_time_ms": refresh_time,
            "errors": errors,
            "refreshed_at": datetime.now().isoformat()
        }
    
    async def get_dashboard_data(self, dashboard_id: str, 
                                parameters: Optional[Dict[str, Any]] = None,
                                force_refresh: bool = False) -> Dict[str, Any]:
        """Get dashboard data, optionally forcing refresh."""
        dashboard = self.get_dashboard(dashboard_id)
        if not dashboard:
            raise BusinessLogicError(f"Dashboard {dashboard_id} not found")
        
        if force_refresh or dashboard.needs_refresh():
            return await self.refresh_dashboard(dashboard_id, parameters)
        else:
            # Return cached data
            results = {}
            for widget in dashboard.list_widgets(enabled_only=True):
                if widget.last_data is not None:
                    results[widget.widget_id] = widget.last_data
                else:
                    # Widget has no cached data, refresh it
                    try:
                        results[widget.widget_id] = await self.refresh_widget(
                            dashboard_id, widget.widget_id, parameters
                        )
                    except Exception as e:
                        results[widget.widget_id] = {"error": str(e)}
            
            return {
                "dashboard_id": dashboard_id,
                "widgets": results,
                "last_refresh": dashboard.last_refresh.isoformat() if dashboard.last_refresh else None,
                "from_cache": True
            }
    
    def _generate_widget_cache_key(self, dashboard_id: str, widget_id: str, 
                                  parameters: Optional[Dict[str, Any]]) -> str:
        """Generate cache key for widget data."""
        import hashlib
        
        key_data = f"{dashboard_id}:{widget_id}:{json.dumps(parameters or {}, sort_keys=True)}"
        hash_key = hashlib.md5(key_data.encode()).hexdigest()
        return f"dashboard_widget:{hash_key}"
    
    async def _background_refresh(self) -> None:
        """Background task to refresh dashboards that need it."""
        while True:
            try:
                for dashboard_id, dashboard in self.dashboards.items():
                    if dashboard.needs_refresh():
                        # Create refresh task if not already running
                        if dashboard_id not in self.refresh_tasks or self.refresh_tasks[dashboard_id].done():
                            self.refresh_tasks[dashboard_id] = asyncio.create_task(
                                self.refresh_dashboard(dashboard_id)
                            )
                
                # Sleep for a short interval
                await asyncio.sleep(10)  # Check every 10 seconds
                
            except Exception as e:
                logger.error(f"Background refresh error: {e}")
                await asyncio.sleep(30)  # Sleep longer on error
    
    async def cleanup(self) -> None:
        """Cleanup resources."""
        # Cancel background refresh task
        if hasattr(self, '_refresh_task'):
            self._refresh_task.cancel()
        
        # Cancel all refresh tasks
        for task in self.refresh_tasks.values():
            task.cancel()
        
        self.refresh_tasks.clear()
        logger.info("Dashboard engine cleaned up")