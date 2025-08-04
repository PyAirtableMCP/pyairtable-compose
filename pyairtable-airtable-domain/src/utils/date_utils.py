"""Date and time utilities."""

from datetime import datetime, timezone, timedelta
from typing import Optional, Union

import croniter


def utc_now() -> datetime:
    """Get current UTC datetime."""
    return datetime.now(timezone.utc)


def to_utc(dt: datetime) -> datetime:
    """Convert datetime to UTC."""
    if dt.tzinfo is None:
        # Assume naive datetime is UTC
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def from_timestamp(timestamp: Union[int, float]) -> datetime:
    """Convert Unix timestamp to UTC datetime."""
    return datetime.fromtimestamp(timestamp, tz=timezone.utc)


def to_timestamp(dt: datetime) -> float:
    """Convert datetime to Unix timestamp."""
    return dt.timestamp()


def format_iso(dt: datetime) -> str:
    """Format datetime as ISO 8601 string."""
    return dt.isoformat()


def parse_iso(iso_string: str) -> datetime:
    """Parse ISO 8601 string to datetime."""
    return datetime.fromisoformat(iso_string.replace('Z', '+00:00'))


def add_days(dt: datetime, days: int) -> datetime:
    """Add days to datetime."""
    return dt + timedelta(days=days)


def add_hours(dt: datetime, hours: int) -> datetime:
    """Add hours to datetime."""
    return dt + timedelta(hours=hours)


def add_minutes(dt: datetime, minutes: int) -> datetime:
    """Add minutes to datetime."""
    return dt + timedelta(minutes=minutes)


def get_next_cron_time(
    cron_expression: str,
    base_time: Optional[datetime] = None,
    timezone_name: str = "UTC"
) -> datetime:
    """Get next execution time for cron expression."""
    if base_time is None:
        base_time = utc_now()
    
    # Convert to the specified timezone for cron calculation
    if timezone_name != "UTC":
        import pytz
        tz = pytz.timezone(timezone_name)
        base_time = base_time.astimezone(tz)
    
    cron = croniter.croniter(cron_expression, base_time)
    next_time = cron.get_next(datetime)
    
    # Convert back to UTC
    if timezone_name != "UTC":
        next_time = next_time.astimezone(timezone.utc)
    
    return next_time


def validate_cron_expression(cron_expression: str) -> bool:
    """Validate cron expression format."""
    try:
        croniter.croniter(cron_expression)
        return True
    except (ValueError, TypeError):
        return False


def time_until(target_time: datetime, from_time: Optional[datetime] = None) -> timedelta:
    """Calculate time remaining until target time."""
    if from_time is None:
        from_time = utc_now()
    return target_time - from_time


def time_since(past_time: datetime, to_time: Optional[datetime] = None) -> timedelta:
    """Calculate time elapsed since past time."""
    if to_time is None:
        to_time = utc_now()
    return to_time - past_time


def format_duration(duration: timedelta) -> str:
    """Format timedelta as human-readable string."""
    total_seconds = int(duration.total_seconds())
    
    if total_seconds < 60:
        return f"{total_seconds}s"
    elif total_seconds < 3600:
        minutes = total_seconds // 60
        seconds = total_seconds % 60
        return f"{minutes}m {seconds}s"
    elif total_seconds < 86400:
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        return f"{hours}h {minutes}m"
    else:
        days = total_seconds // 86400
        hours = (total_seconds % 86400) // 3600
        return f"{days}d {hours}h"


def is_future(dt: datetime, reference_time: Optional[datetime] = None) -> bool:
    """Check if datetime is in the future."""
    if reference_time is None:
        reference_time = utc_now()
    return dt > reference_time


def is_past(dt: datetime, reference_time: Optional[datetime] = None) -> bool:
    """Check if datetime is in the past."""
    if reference_time is None:
        reference_time = utc_now()
    return dt < reference_time


def start_of_day(dt: datetime) -> datetime:
    """Get start of day for datetime."""
    return dt.replace(hour=0, minute=0, second=0, microsecond=0)


def end_of_day(dt: datetime) -> datetime:
    """Get end of day for datetime."""
    return dt.replace(hour=23, minute=59, second=59, microsecond=999999)


def start_of_week(dt: datetime) -> datetime:
    """Get start of week (Monday) for datetime."""
    days_since_monday = dt.weekday()
    return start_of_day(dt - timedelta(days=days_since_monday))


def end_of_week(dt: datetime) -> datetime:
    """Get end of week (Sunday) for datetime."""
    days_until_sunday = 6 - dt.weekday()
    return end_of_day(dt + timedelta(days=days_until_sunday))