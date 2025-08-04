"""Dashboard module with real-time data aggregation and caching."""

from .dashboard_engine import DashboardEngine, Dashboard, Widget
from .realtime_service import RealtimeService, RealtimeConnection
from .aggregation_service import AggregationService, AggregationQuery
from .cache_manager import DashboardCacheManager

__all__ = [
    "DashboardEngine",
    "Dashboard",
    "Widget",
    "RealtimeService",
    "RealtimeConnection",
    "AggregationService",
    "AggregationQuery",
    "DashboardCacheManager",
]