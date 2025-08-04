"""Logging configuration for AI domain service"""
import logging
import sys
from typing import Dict, Any
import structlog
from rich.console import Console
from rich.logging import RichHandler

from .config import get_settings


def setup_logging() -> None:
    """Setup structured logging with rich formatting"""
    settings = get_settings()
    
    # Configure standard library logging
    logging.basicConfig(
        level=getattr(logging, settings.log_level.upper()),
        format="%(message)s",
        handlers=[
            RichHandler(
                console=Console(stderr=True),
                show_time=True,
                show_path=True,
                markup=True,
                rich_tracebacks=True,
            )
        ],
    )
    
    # Configure structlog
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.StackInfoRenderer(),
            structlog.dev.set_exc_info,
            structlog.processors.TimeStamper(fmt="ISO"),
            structlog.dev.ConsoleRenderer(colors=True) if settings.debug 
            else structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            getattr(logging, settings.log_level.upper())
        ),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str = __name__) -> structlog.BoundLogger:
    """Get a structured logger instance"""
    return structlog.get_logger(name)


class TokenUsageLogger:
    """Logger specifically for token usage and costs"""
    
    def __init__(self):
        self.logger = get_logger("token_usage")
        self.settings = get_settings()
    
    def log_usage(
        self,
        provider: str,
        model: str,
        prompt_tokens: int,
        completion_tokens: int,
        cost: float,
        user_id: str = None,
        session_id: str = None,
        **kwargs
    ) -> None:
        """Log token usage and cost information"""
        self.logger.info(
            "token_usage",
            provider=provider,
            model=model,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=prompt_tokens + completion_tokens,
            cost_usd=cost,
            user_id=user_id,
            session_id=session_id,
            **kwargs
        )
        
        # Alert if cost exceeds threshold
        if cost > self.settings.cost_alert_threshold:
            self.logger.warning(
                "high_cost_alert",
                cost_usd=cost,
                threshold=self.settings.cost_alert_threshold,
                provider=provider,
                model=model,
                user_id=user_id
            )


class ModelPerformanceLogger:
    """Logger for model performance metrics"""
    
    def __init__(self):
        self.logger = get_logger("model_performance")
    
    def log_inference(
        self,
        model: str,
        provider: str,
        latency_ms: float,
        input_length: int,
        output_length: int,
        success: bool = True,
        error: str = None,
        **kwargs
    ) -> None:
        """Log model inference performance"""
        self.logger.info(
            "model_inference",
            model=model,
            provider=provider,
            latency_ms=latency_ms,
            input_length=input_length,
            output_length=output_length,
            success=success,
            error=error,
            tokens_per_second=output_length / (latency_ms / 1000) if latency_ms > 0 else 0,
            **kwargs
        )


class MCPLogger:
    """Logger for MCP tool execution"""
    
    def __init__(self):
        self.logger = get_logger("mcp_tools")
    
    def log_tool_execution(
        self,
        tool_name: str,
        execution_time_ms: float,
        success: bool = True,
        error: str = None,
        user_id: str = None,
        **kwargs
    ) -> None:
        """Log MCP tool execution"""
        self.logger.info(
            "tool_execution",
            tool_name=tool_name,
            execution_time_ms=execution_time_ms,
            success=success,
            error=error,
            user_id=user_id,
            **kwargs
        )