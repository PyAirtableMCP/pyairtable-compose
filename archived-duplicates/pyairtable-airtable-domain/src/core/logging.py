"""Structured logging configuration."""

import sys
from typing import Any, Dict

import structlog
from rich.console import Console
from rich.logging import RichHandler

from .config import get_observability_settings


def configure_logging() -> None:
    """Configure structured logging for the application."""
    settings = get_observability_settings()
    
    # Configure structlog
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            _create_processor(settings.log_format),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            _log_level_to_int(settings.log_level)
        ),
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )


def _create_processor(log_format: str):
    """Create appropriate log processor based on format."""
    if log_format.lower() == "json":
        return structlog.processors.JSONRenderer()
    else:
        # Use Rich for colored console output in text format
        console = Console(file=sys.stderr, width=120)
        return structlog.dev.ConsoleRenderer(
            colors=True,
            exception_formatter=structlog.dev.plain_traceback,
        )


def _log_level_to_int(log_level: str) -> int:
    """Convert log level string to integer."""
    levels = {
        "CRITICAL": 50,
        "ERROR": 40,
        "WARNING": 30,
        "INFO": 20,
        "DEBUG": 10,
        "NOTSET": 0,
    }
    return levels.get(log_level.upper(), 20)


def get_logger(name: str = None) -> structlog.BoundLogger:
    """Get a configured logger instance."""
    return structlog.get_logger(name)


def add_context(**kwargs: Any) -> None:
    """Add context to all subsequent log messages in this context."""
    structlog.contextvars.bind_contextvars(**kwargs)


def clear_context() -> None:
    """Clear all contextual variables."""
    structlog.contextvars.clear_contextvars()


def log_request_context(request_id: str, user_id: str = None, **kwargs: Any) -> None:
    """Add request-specific context to logs."""
    context = {"request_id": request_id, **kwargs}
    if user_id:
        context["user_id"] = user_id
    add_context(**context)