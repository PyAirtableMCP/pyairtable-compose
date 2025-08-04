"""Logging configuration and utilities."""

import logging
import sys
from functools import lru_cache
from typing import Any, Dict

import structlog
from rich.console import Console
from rich.logging import RichHandler

from .config import get_settings


def configure_logging() -> None:
    """Configure application logging."""
    settings = get_settings()
    
    # Configure standard library logging
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, settings.observability.log_level.upper()),
        handlers=[RichHandler(console=Console(stderr=False), rich_tracebacks=True)]
        if settings.is_development else [],
    )
    
    # Configure structlog
    processors = [
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.StackInfoRenderer(),
        structlog.dev.set_exc_info,
    ]
    
    if settings.observability.structured_logging:
        processors.extend([
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.JSONRenderer(),
        ])
    else:
        processors.extend([
            structlog.dev.ConsoleRenderer(),
        ])
    
    structlog.configure(
        processors=processors,
        wrapper_class=structlog.make_filtering_bound_logger(
            getattr(logging, settings.observability.log_level.upper())
        ),
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )


@lru_cache()
def get_logger(name: str = __name__) -> structlog.BoundLogger:
    """Get a configured logger instance."""
    return structlog.get_logger(name)


def log_function_call(func_name: str, **kwargs: Any) -> None:
    """Log a function call with parameters."""
    logger = get_logger()
    logger.debug("Function called", function=func_name, **kwargs)


def log_function_result(func_name: str, result: Any = None, **kwargs: Any) -> None:
    """Log a function result."""
    logger = get_logger()
    logger.debug("Function completed", function=func_name, result=result, **kwargs)


def log_error(error: Exception, context: Dict[str, Any] = None) -> None:
    """Log an error with context."""
    logger = get_logger()
    logger.error(
        "Error occurred",
        error=str(error),
        error_type=type(error).__name__,
        **(context or {})
    )