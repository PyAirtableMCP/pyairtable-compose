"""Unified configuration management for Airtable Domain Service."""

import os
from functools import lru_cache
from typing import List, Optional

from pydantic import Field, validator
from pydantic_settings import BaseSettings


class DatabaseSettings(BaseSettings):
    """Database configuration."""
    
    url: str = Field(
        default="postgresql+asyncpg://postgres:postgres@localhost:5432/pyairtable",
        description="Database connection URL"
    )
    pool_size: int = Field(default=20, description="Connection pool size")
    max_overflow: int = Field(default=30, description="Maximum overflow connections")
    pool_timeout: int = Field(default=30, description="Pool timeout in seconds")
    pool_recycle: int = Field(default=3600, description="Pool recycle time in seconds")
    echo: bool = Field(default=False, description="Enable SQL query logging")

    class Config:
        env_prefix = "DATABASE_"


class RedisSettings(BaseSettings):
    """Redis configuration."""
    
    url: str = Field(
        default="redis://localhost:6379/0",
        description="Redis connection URL"
    )
    max_connections: int = Field(default=20, description="Maximum Redis connections")
    retry_on_timeout: bool = Field(default=True, description="Retry on timeout")
    socket_keepalive: bool = Field(default=True, description="Enable socket keepalive")
    socket_keepalive_options: dict = Field(
        default_factory=lambda: {"TCP_KEEPINTVL": 1, "TCP_KEEPCNT": 3, "TCP_KEEPIDLE": 1}
    )

    class Config:
        env_prefix = "REDIS_"


class AirtableSettings(BaseSettings):
    """Airtable API configuration."""
    
    token: str = Field(default="", description="Airtable personal access token")
    rate_limit: int = Field(default=5, description="Requests per second")
    timeout: int = Field(default=30, description="Request timeout in seconds")
    retry_attempts: int = Field(default=3, description="Number of retry attempts")
    retry_delay: float = Field(default=1.0, description="Initial retry delay in seconds")
    max_batch_size: int = Field(default=10, description="Maximum batch size for operations")
    cache_ttl: int = Field(default=3600, description="Cache TTL in seconds")

    class Config:
        env_prefix = "AIRTABLE_"


class SecuritySettings(BaseSettings):
    """Security configuration."""
    
    internal_api_key: str = Field(default="", description="Internal API key for service communication")
    jwt_secret_key: str = Field(default="", description="JWT secret key")
    jwt_algorithm: str = Field(default="HS256", description="JWT algorithm")
    jwt_access_token_expire_minutes: int = Field(
        default=30, description="Access token expiration in minutes"
    )
    jwt_refresh_token_expire_days: int = Field(
        default=7, description="Refresh token expiration in days"
    )
    password_min_length: int = Field(default=8, description="Minimum password length")
    bcrypt_rounds: int = Field(default=12, description="Bcrypt hashing rounds")

    class Config:
        env_prefix = "SECURITY_"


class ObservabilitySettings(BaseSettings):
    """Observability and monitoring configuration."""
    
    log_level: str = Field(default="INFO", description="Logging level")
    log_format: str = Field(default="json", description="Log format (json or text)")
    enable_metrics: bool = Field(default=True, description="Enable Prometheus metrics")
    metrics_port: int = Field(default=9090, description="Metrics server port")
    enable_tracing: bool = Field(default=False, description="Enable distributed tracing")
    jaeger_endpoint: Optional[str] = Field(default=None, description="Jaeger endpoint")
    health_check_interval: int = Field(default=30, description="Health check interval in seconds")

    class Config:
        env_prefix = "OBSERVABILITY_"


class CelerySettings(BaseSettings):
    """Celery configuration for background tasks."""
    
    broker_url: str = Field(
        default="redis://localhost:6379/1",
        description="Celery broker URL"
    )
    result_backend: str = Field(
        default="redis://localhost:6379/1",
        description="Celery result backend URL"
    )
    task_always_eager: bool = Field(
        default=False, description="Execute tasks synchronously for testing"
    )
    task_serializer: str = Field(default="json", description="Task serialization format")
    result_serializer: str = Field(default="json", description="Result serialization format")
    accept_content: List[str] = Field(
        default_factory=lambda: ["json"], description="Accepted content types"
    )
    timezone: str = Field(default="UTC", description="Timezone for scheduled tasks")
    enable_utc: bool = Field(default=True, description="Enable UTC timestamps")
    worker_prefetch_multiplier: int = Field(
        default=1, description="Worker prefetch multiplier"
    )
    task_acks_late: bool = Field(default=True, description="Acknowledge tasks late")
    worker_disable_rate_limits: bool = Field(
        default=False, description="Disable worker rate limits"
    )

    class Config:
        env_prefix = "CELERY_"


class Settings(BaseSettings):
    """Main application settings."""
    
    # Service information
    service_name: str = Field(default="pyairtable-airtable-domain", description="Service name")
    service_version: str = Field(default="1.0.0", description="Service version")
    description: str = Field(
        default="Consolidated Airtable domain service",
        description="Service description"
    )
    
    # Server configuration
    host: str = Field(default="0.0.0.0", description="Server host")
    port: int = Field(default=8000, description="Server port")
    workers: int = Field(default=1, description="Number of worker processes")
    reload: bool = Field(default=False, description="Enable auto-reload in development")
    
    # Environment
    environment: str = Field(default="production", description="Environment (development/production)")
    debug: bool = Field(default=False, description="Enable debug mode")
    
    # CORS configuration
    cors_origins: List[str] = Field(
        default_factory=lambda: ["*"], description="Allowed CORS origins"
    )
    cors_allow_credentials: bool = Field(default=True, description="Allow CORS credentials")
    cors_allow_methods: List[str] = Field(
        default_factory=lambda: ["*"], description="Allowed CORS methods"
    )
    cors_allow_headers: List[str] = Field(
        default_factory=lambda: ["*"], description="Allowed CORS headers"
    )
    
    # Component settings
    database: DatabaseSettings = Field(default_factory=DatabaseSettings)
    redis: RedisSettings = Field(default_factory=RedisSettings)
    airtable: AirtableSettings = Field(default_factory=AirtableSettings)
    security: SecuritySettings = Field(default_factory=SecuritySettings)
    observability: ObservabilitySettings = Field(default_factory=ObservabilitySettings)
    celery: CelerySettings = Field(default_factory=CelerySettings)

    @validator("environment")
    def validate_environment(cls, v: str) -> str:
        """Validate environment value."""
        allowed_envs = {"development", "staging", "production", "testing"}
        if v.lower() not in allowed_envs:
            raise ValueError(f"Environment must be one of: {allowed_envs}")
        return v.lower()

    @validator("debug", pre=True)
    def validate_debug(cls, v, values) -> bool:
        """Auto-enable debug in development environment."""
        if "environment" in values and values["environment"] == "development":
            return True
        return bool(v)

    @property
    def is_development(self) -> bool:
        """Check if running in development mode."""
        return self.environment == "development"

    @property
    def is_production(self) -> bool:
        """Check if running in production mode."""
        return self.environment == "production"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False
        # Allow nested settings
        env_nested_delimiter = "__"


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()


def get_database_settings() -> DatabaseSettings:
    """Get database settings."""
    return get_settings().database


def get_redis_settings() -> RedisSettings:
    """Get Redis settings."""
    return get_settings().redis


def get_airtable_settings() -> AirtableSettings:
    """Get Airtable settings."""
    return get_settings().airtable


def get_security_settings() -> SecuritySettings:
    """Get security settings."""
    return get_settings().security


def get_observability_settings() -> ObservabilitySettings:
    """Get observability settings."""
    return get_settings().observability


def get_celery_settings() -> CelerySettings:
    """Get Celery settings."""
    return get_settings().celery