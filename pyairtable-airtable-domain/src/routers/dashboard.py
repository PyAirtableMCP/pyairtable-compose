"""Dashboard management and real-time data endpoints."""

from typing import Any, Dict, List, Optional
from datetime import datetime

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field

from ..services.dashboard import DashboardEngine, Dashboard, Widget, WidgetType, RefreshMode
from ..services.airtable_service import AirtableService
from ..utils.exceptions import BusinessLogicError
from ..utils.redis_client import RedisCache

router = APIRouter()

# Global instances (in production, these would be dependency-injected)
_dashboard_engine: Optional[DashboardEngine] = None


def get_dashboard_engine() -> DashboardEngine:
    """Get or create dashboard engine instance."""
    global _dashboard_engine
    if _dashboard_engine is None:
        # In production, these would be properly injected
        from ..core.config import get_airtable_settings
        airtable_service = AirtableService()
        cache = RedisCache()
        _dashboard_engine = DashboardEngine(airtable_service, cache)
    return _dashboard_engine


class CreateDashboardRequest(BaseModel):
    """Request to create a dashboard."""
    dashboard_id: str
    name: str
    description: str = ""
    layout_columns: int = 12
    auto_refresh: bool = True
    refresh_interval: int = 30
    tags: List[str] = Field(default_factory=list)
    is_public: bool = False
    owner_id: Optional[str] = None
    shared_with: List[str] = Field(default_factory=list)


class UpdateDashboardRequest(BaseModel):
    """Request to update a dashboard."""
    name: Optional[str] = None
    description: Optional[str] = None
    layout_columns: Optional[int] = None
    auto_refresh: Optional[bool] = None
    refresh_interval: Optional[int] = None
    tags: Optional[List[str]] = None
    is_public: Optional[bool] = None
    shared_with: Optional[List[str]] = None


class CreateWidgetRequest(BaseModel):
    """Request to create a widget."""
    dashboard_id: str
    widget_id: str
    title: str
    widget_type: str  # WidgetType enum value
    description: str = ""
    data_source: Optional[Dict[str, Any]] = None
    layout: Dict[str, Any] = Field(default_factory=dict)
    configuration: Dict[str, Any] = Field(default_factory=dict)
    refresh_mode: str = "manual"  # RefreshMode enum value
    refresh_interval: Optional[int] = None


class UpdateWidgetRequest(BaseModel):
    """Request to update a widget."""
    title: Optional[str] = None
    description: Optional[str] = None
    data_source: Optional[Dict[str, Any]] = None
    layout: Optional[Dict[str, Any]] = None
    configuration: Optional[Dict[str, Any]] = None
    refresh_mode: Optional[str] = None
    refresh_interval: Optional[int] = None
    enabled: Optional[bool] = None


class RefreshRequest(BaseModel):
    """Request to refresh dashboard or widget."""
    parameters: Dict[str, Any] = Field(default_factory=dict)
    force_refresh: bool = False


# Dashboard management endpoints
@router.post("/dashboards", response_model=Dict[str, Any])
async def create_dashboard(request: CreateDashboardRequest):
    """Create a new dashboard."""
    try:
        engine = get_dashboard_engine()
        
        dashboard = engine.create_dashboard(
            dashboard_id=request.dashboard_id,
            name=request.name,
            description=request.description,
            layout_columns=request.layout_columns,
            auto_refresh=request.auto_refresh,
            refresh_interval=request.refresh_interval,
            tags=request.tags,
            is_public=request.is_public,
            owner_id=request.owner_id,
            shared_with=request.shared_with
        )
        
        return {
            "success": True,
            "dashboard_id": request.dashboard_id,
            "message": f"Dashboard '{request.dashboard_id}' created successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/dashboards", response_model=Dict[str, Any])
async def list_dashboards(owner_id: Optional[str] = None, tags: Optional[str] = None):
    """List all dashboards, optionally filtered."""
    try:
        engine = get_dashboard_engine()
        
        filter_tags = tags.split(",") if tags else None
        dashboards = engine.list_dashboards(owner_id=owner_id, tags=filter_tags)
        
        return {
            "success": True,
            "dashboards": [
                {
                    "dashboard_id": dashboard.dashboard_id,
                    "name": dashboard.name,
                    "description": dashboard.description,
                    "widgets_count": len(dashboard.widgets),
                    "auto_refresh": dashboard.auto_refresh,
                    "refresh_interval": dashboard.refresh_interval,
                    "tags": dashboard.tags,
                    "is_public": dashboard.is_public,
                    "owner_id": dashboard.owner_id,
                    "last_refresh": dashboard.last_refresh.isoformat() if dashboard.last_refresh else None,
                    "created_at": dashboard.created_at.isoformat(),
                    "updated_at": dashboard.updated_at.isoformat()
                }
                for dashboard in dashboards
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/dashboards/{dashboard_id}", response_model=Dict[str, Any])
async def get_dashboard(dashboard_id: str):
    """Get a specific dashboard."""
    try:
        engine = get_dashboard_engine()
        dashboard = engine.get_dashboard(dashboard_id)
        
        if not dashboard:
            raise HTTPException(status_code=404, detail=f"Dashboard '{dashboard_id}' not found")
        
        return {
            "success": True,
            "dashboard": dashboard.to_dict()
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/dashboards/{dashboard_id}", response_model=Dict[str, Any])
async def update_dashboard(dashboard_id: str, request: UpdateDashboardRequest):
    """Update a dashboard."""
    try:
        engine = get_dashboard_engine()
        dashboard = engine.get_dashboard(dashboard_id)
        
        if not dashboard:
            raise HTTPException(status_code=404, detail=f"Dashboard '{dashboard_id}' not found")
        
        # Update dashboard properties
        if request.name is not None:
            dashboard.name = request.name
        if request.description is not None:
            dashboard.description = request.description
        if request.layout_columns is not None:
            dashboard.layout_columns = request.layout_columns
        if request.auto_refresh is not None:
            dashboard.auto_refresh = request.auto_refresh
        if request.refresh_interval is not None:
            dashboard.refresh_interval = request.refresh_interval
        if request.tags is not None:
            dashboard.tags = request.tags
        if request.is_public is not None:
            dashboard.is_public = request.is_public
        if request.shared_with is not None:
            dashboard.shared_with = request.shared_with
        
        dashboard.updated_at = datetime.now()
        
        return {
            "success": True,
            "dashboard_id": dashboard_id,
            "message": f"Dashboard '{dashboard_id}' updated successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/dashboards/{dashboard_id}", response_model=Dict[str, Any])
async def delete_dashboard(dashboard_id: str):
    """Delete a dashboard."""
    try:
        engine = get_dashboard_engine()
        success = engine.delete_dashboard(dashboard_id)
        
        if success:
            return {
                "success": True,
                "message": f"Dashboard '{dashboard_id}' deleted successfully"
            }
        else:
            raise HTTPException(status_code=404, detail=f"Dashboard '{dashboard_id}' not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Widget management endpoints
@router.post("/dashboards/{dashboard_id}/widgets", response_model=Dict[str, Any])
async def create_widget(dashboard_id: str, request: CreateWidgetRequest):
    """Create a new widget in a dashboard."""
    try:
        engine = get_dashboard_engine()
        dashboard = engine.get_dashboard(dashboard_id)
        
        if not dashboard:
            raise HTTPException(status_code=404, detail=f"Dashboard '{dashboard_id}' not found")
        
        # Create widget
        widget = Widget(
            widget_id=request.widget_id,
            title=request.title,
            widget_type=WidgetType(request.widget_type)
        )
        
        widget.description = request.description
        widget.configuration = request.configuration
        widget.refresh_mode = RefreshMode(request.refresh_mode)
        widget.refresh_interval = request.refresh_interval
        
        # Set data source
        if request.data_source:
            from ..services.dashboard.dashboard_engine import WidgetDataSource
            widget.data_source = WidgetDataSource(
                source_type=request.data_source["source_type"],
                configuration=request.data_source.get("configuration", {}),
                query=request.data_source.get("query"),
                filters=request.data_source.get("filters", {}),
                transformations=request.data_source.get("transformations", []),
                cache_ttl=request.data_source.get("cache_ttl", 300)
            )
        
        # Set layout
        if request.layout:
            from ..services.dashboard.dashboard_engine import WidgetLayout
            widget.layout = WidgetLayout(**request.layout)
        
        # Add widget to dashboard
        dashboard.add_widget(widget)
        
        return {
            "success": True,
            "widget_id": request.widget_id,
            "message": f"Widget '{request.widget_id}' created successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/dashboards/{dashboard_id}/widgets", response_model=Dict[str, Any])
async def list_widgets(dashboard_id: str, widget_type: Optional[str] = None, enabled_only: bool = True):
    """List widgets in a dashboard."""
    try:
        engine = get_dashboard_engine()
        dashboard = engine.get_dashboard(dashboard_id)
        
        if not dashboard:
            raise HTTPException(status_code=404, detail=f"Dashboard '{dashboard_id}' not found")
        
        filter_type = WidgetType(widget_type) if widget_type else None
        widgets = dashboard.list_widgets(widget_type=filter_type, enabled_only=enabled_only)
        
        return {
            "success": True,
            "widgets": [
                {
                    "widget_id": widget.widget_id,
                    "title": widget.title,
                    "widget_type": widget.widget_type.value,
                    "description": widget.description,
                    "layout": {
                        "x": widget.layout.x,
                        "y": widget.layout.y,
                        "width": widget.layout.width,
                        "height": widget.layout.height
                    },
                    "refresh_mode": widget.refresh_mode.value,
                    "refresh_interval": widget.refresh_interval,
                    "last_refresh": widget.last_refresh.isoformat() if widget.last_refresh else None,
                    "enabled": widget.enabled,
                    "created_at": widget.created_at.isoformat(),
                    "updated_at": widget.updated_at.isoformat()
                }
                for widget in widgets
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/dashboards/{dashboard_id}/widgets/{widget_id}", response_model=Dict[str, Any])
async def get_widget(dashboard_id: str, widget_id: str):
    """Get a specific widget."""
    try:
        engine = get_dashboard_engine()
        dashboard = engine.get_dashboard(dashboard_id)
        
        if not dashboard:
            raise HTTPException(status_code=404, detail=f"Dashboard '{dashboard_id}' not found")
        
        widget = dashboard.get_widget(widget_id)
        if not widget:
            raise HTTPException(status_code=404, detail=f"Widget '{widget_id}' not found")
        
        return {
            "success": True,
            "widget": widget.to_dict()
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/dashboards/{dashboard_id}/widgets/{widget_id}", response_model=Dict[str, Any])
async def update_widget(dashboard_id: str, widget_id: str, request: UpdateWidgetRequest):
    """Update a widget."""
    try:
        engine = get_dashboard_engine()
        dashboard = engine.get_dashboard(dashboard_id)
        
        if not dashboard:
            raise HTTPException(status_code=404, detail=f"Dashboard '{dashboard_id}' not found")
        
        widget = dashboard.get_widget(widget_id)
        if not widget:
            raise HTTPException(status_code=404, detail=f"Widget '{widget_id}' not found")
        
        # Update widget properties
        if request.title is not None:
            widget.title = request.title
        if request.description is not None:
            widget.description = request.description
        if request.configuration is not None:
            widget.configuration.update(request.configuration)
        if request.refresh_mode is not None:
            widget.refresh_mode = RefreshMode(request.refresh_mode)
        if request.refresh_interval is not None:
            widget.refresh_interval = request.refresh_interval
        if request.enabled is not None:
            widget.enabled = request.enabled
        
        # Update data source
        if request.data_source is not None:
            from ..services.dashboard.dashboard_engine import WidgetDataSource
            widget.data_source = WidgetDataSource(
                source_type=request.data_source["source_type"],
                configuration=request.data_source.get("configuration", {}),
                query=request.data_source.get("query"),
                filters=request.data_source.get("filters", {}),
                transformations=request.data_source.get("transformations", []),
                cache_ttl=request.data_source.get("cache_ttl", 300)
            )
        
        # Update layout
        if request.layout is not None:
            for key, value in request.layout.items():
                if hasattr(widget.layout, key):
                    setattr(widget.layout, key, value)
        
        widget.updated_at = datetime.now()
        
        return {
            "success": True,
            "widget_id": widget_id,
            "message": f"Widget '{widget_id}' updated successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/dashboards/{dashboard_id}/widgets/{widget_id}", response_model=Dict[str, Any])
async def delete_widget(dashboard_id: str, widget_id: str):
    """Delete a widget from a dashboard."""
    try:
        engine = get_dashboard_engine()
        dashboard = engine.get_dashboard(dashboard_id)
        
        if not dashboard:
            raise HTTPException(status_code=404, detail=f"Dashboard '{dashboard_id}' not found")
        
        success = dashboard.remove_widget(widget_id)
        
        if success:
            return {
                "success": True,
                "message": f"Widget '{widget_id}' deleted successfully"
            }
        else:
            raise HTTPException(status_code=404, detail=f"Widget '{widget_id}' not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Data and refresh endpoints
@router.get("/dashboards/{dashboard_id}/data", response_model=Dict[str, Any])
async def get_dashboard_data(dashboard_id: str, force_refresh: bool = False):
    """Get dashboard data with all widget data."""
    try:
        engine = get_dashboard_engine()
        parameters = {}  # Could be passed as query parameters
        
        data = await engine.get_dashboard_data(
            dashboard_id=dashboard_id,
            parameters=parameters,
            force_refresh=force_refresh
        )
        
        return {
            "success": True,
            "dashboard_data": data
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/dashboards/{dashboard_id}/refresh", response_model=Dict[str, Any])
async def refresh_dashboard(dashboard_id: str, request: RefreshRequest):
    """Refresh all widgets in a dashboard."""
    try:
        engine = get_dashboard_engine()
        
        if request.force_refresh:
            data = await engine.refresh_dashboard(dashboard_id, request.parameters)
        else:
            data = await engine.get_dashboard_data(
                dashboard_id=dashboard_id,
                parameters=request.parameters,
                force_refresh=False
            )
        
        return {
            "success": True,
            "dashboard_data": data
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/dashboards/{dashboard_id}/widgets/{widget_id}/refresh", response_model=Dict[str, Any])
async def refresh_widget(dashboard_id: str, widget_id: str, request: RefreshRequest):
    """Refresh a specific widget."""
    try:
        engine = get_dashboard_engine()
        
        data = await engine.refresh_widget(
            dashboard_id=dashboard_id,
            widget_id=widget_id,
            parameters=request.parameters
        )
        
        return {
            "success": True,
            "widget_id": widget_id,
            "data": data
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/dashboards/{dashboard_id}/widgets/{widget_id}/data", response_model=Dict[str, Any])
async def get_widget_data(dashboard_id: str, widget_id: str):
    """Get data for a specific widget."""
    try:
        engine = get_dashboard_engine()
        dashboard = engine.get_dashboard(dashboard_id)
        
        if not dashboard:
            raise HTTPException(status_code=404, detail=f"Dashboard '{dashboard_id}' not found")
        
        widget = dashboard.get_widget(widget_id)
        if not widget:
            raise HTTPException(status_code=404, detail=f"Widget '{widget_id}' not found")
        
        return {
            "success": True,
            "widget_id": widget_id,
            "data": widget.last_data,
            "last_refresh": widget.last_refresh.isoformat() if widget.last_refresh else None
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Layout management endpoints
@router.put("/dashboards/{dashboard_id}/widgets/{widget_id}/layout", response_model=Dict[str, Any])
async def update_widget_layout(dashboard_id: str, widget_id: str, layout_update: Dict[str, Any]):
    """Update widget layout."""
    try:
        engine = get_dashboard_engine()
        dashboard = engine.get_dashboard(dashboard_id)
        
        if not dashboard:
            raise HTTPException(status_code=404, detail=f"Dashboard '{dashboard_id}' not found")
        
        success = dashboard.update_layout(widget_id, layout_update)
        
        if success:
            return {
                "success": True,
                "widget_id": widget_id,
                "message": f"Widget '{widget_id}' layout updated successfully"
            }
        else:
            raise HTTPException(status_code=404, detail=f"Widget '{widget_id}' not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# Utility endpoints
@router.get("/widget-types", response_model=Dict[str, Any])
async def list_widget_types():
    """List all available widget types."""
    return {
        "success": True,
        "widget_types": [
            {
                "value": wt.value,
                "name": wt.name,
                "description": {
                    "metric": "Single value metric with trend",
                    "chart": "Various chart types (line, bar, pie, etc.)",
                    "table": "Data table with sorting and filtering",
                    "text": "Static or dynamic text content",
                    "progress": "Progress bar with current/target values",
                    "gauge": "Gauge visualization with thresholds",
                    "heatmap": "Heat map visualization",
                    "timeline": "Timeline visualization",
                    "map": "Geographic map visualization",
                    "iframe": "Embedded iframe content"
                }.get(wt.value, "")
            }
            for wt in WidgetType
        ]
    }


@router.get("/refresh-modes", response_model=Dict[str, Any])
async def list_refresh_modes():
    """List all available refresh modes."""
    return {
        "success": True,
        "refresh_modes": [
            {
                "value": rm.value,
                "name": rm.name,
                "description": {
                    "manual": "Refresh only when explicitly requested",
                    "scheduled": "Refresh at regular intervals",
                    "realtime": "Real-time updates when data changes",
                    "on_demand": "Refresh when conditions are met"
                }.get(rm.value, "")
            }
            for rm in RefreshMode
        ]
    }