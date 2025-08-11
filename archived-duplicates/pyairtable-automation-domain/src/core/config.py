"""Application configuration management."""

import os
from functools import lru_cache
from typing import List, Optional

from pydantic import Field, validator
from pydantic_settings import BaseSettings


class DatabaseSettings(BaseSettings):
    """Database configuration."""
    
    url: str = Field(
        default="postgresql+asyncpg://postgres:postgres@localhost:5432/pyairtable_automation",
        env="DATABASE_URL"
    )
    pool_size: int = Field(default=10, env="DATABASE_POOL_SIZE")
    max_overflow: int = Field(default=20, env="DATABASE_MAX_OVERFLOW")
    echo: bool = Field(default=False, env="DATABASE_ECHO")
    
    class Config:
        env_prefix = "DATABASE_"


class RedisSettings(BaseSettings):
    """Redis configuration."""
    
    url: str = Field(default="redis://localhost:6379/0", env="REDIS_URL")
    password: Optional[str] = Field(default=None, env="REDIS_PASSWORD")
    max_connections: int = Field(default=20, env="REDIS_MAX_CONNECTIONS")
    retry_on_timeout: bool = Field(default=True, env="REDIS_RETRY_ON_TIMEOUT")
    
    class Config:
        env_prefix = "REDIS_"


class CelerySettings(BaseSettings):
    """Celery configuration."""
    
    broker_url: str = Field(default="redis://localhost:6379/1", env="CELERY_BROKER_URL")
    result_backend: str = Field(default="redis://localhost:6379/2", env="CELERY_RESULT_BACKEND")
    task_serializer: str = Field(default="json", env="CELERY_TASK_SERIALIZER")
    accept_content: List[str] = Field(default=["json"], env="CELERY_ACCEPT_CONTENT")
    result_serializer: str = Field(default="json", env="CELERY_RESULT_SERIALIZER")
    timezone: str = Field(default="UTC", env="CELERY_TIMEZONE")
    enable_utc: bool = Field(default=True, env="CELERY_ENABLE_UTC")
    task_track_started: bool = Field(default=True, env="CELERY_TASK_TRACK_STARTED")
    task_time_limit: int = Field(default=30 * 60, env="CELERY_TASK_TIME_LIMIT")  # 30 minutes
    task_soft_time_limit: int = Field(default=25 * 60, env="CELERY_TASK_SOFT_TIME_LIMIT")  # 25 minutes
    worker_prefetch_multiplier: int = Field(default=1, env="CELERY_WORKER_PREFETCH_MULTIPLIER")
    
    class Config:
        env_prefix = "CELERY_"


class SecuritySettings(BaseSettings):
    """Security configuration."""
    
    internal_api_key: str = Field(env="INTERNAL_API_KEY")
    jwt_secret_key: str = Field(env="JWT_SECRET_KEY")
    jwt_algorithm: str = Field(default="HS256", env="JWT_ALGORITHM")
    jwt_expire_minutes: int = Field(default=30, env="JWT_EXPIRE_MINUTES")
    
    class Config:
        env_prefix = "SECURITY_"


class NotificationSettings(BaseSettings):
    """Notification service configuration."""
    
    smtp_host: str = Field(default="localhost", env="SMTP_HOST")
    smtp_port: int = Field(default=587, env="SMTP_PORT")
    smtp_username: Optional[str] = Field(default=None, env="SMTP_USERNAME")
    smtp_password: Optional[str] = Field(default=None, env="SMTP_PASSWORD")
    smtp_use_tls: bool = Field(default=True, env="SMTP_USE_TLS")
    smtp_use_ssl: bool = Field(default=False, env="SMTP_USE_SSL")
    
    # Default sender
    from_email: str = Field(default="noreply@pyairtable.com", env="NOTIFICATION_FROM_EMAIL")
    from_name: str = Field(default="PyAirtable", env="NOTIFICATION_FROM_NAME")
    
    # Rate limiting
    email_rate_limit: int = Field(default=100, env="EMAIL_RATE_LIMIT")  # emails per hour
    
    class Config:
        env_prefix = "NOTIFICATION_"


class WebhookSettings(BaseSettings):
    """Webhook service configuration."""
    
    max_retries: int = Field(default=3, env="WEBHOOK_MAX_RETRIES")
    retry_delay: int = Field(default=60, env="WEBHOOK_RETRY_DELAY")  # seconds
    timeout: int = Field(default=30, env="WEBHOOK_TIMEOUT")  # seconds
    verify_ssl: bool = Field(default=True, env="WEBHOOK_VERIFY_SSL")
    
    # Webhook signing
    secret_key: str = Field(env="WEBHOOK_SECRET_KEY")
    signature_header: str = Field(default="X-Webhook-Signature", env="WEBHOOK_SIGNATURE_HEADER")
    
    class Config:
        env_prefix = "WEBHOOK_"


class ObservabilitySettings(BaseSettings):
    """Observability configuration."""
    
    enable_metrics: bool = Field(default=True, env="ENABLE_METRICS")
    enable_tracing: bool = Field(default=True, env="ENABLE_TRACING")
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    structured_logging: bool = Field(default=True, env="STRUCTURED_LOGGING")
    
    # Metrics
    metrics_port: int = Field(default=9090, env="METRICS_PORT")
    
    # Tracing
    jaeger_endpoint: Optional[str] = Field(default=None, env="JAEGER_ENDPOINT")
    trace_sample_rate: float = Field(default=0.1, env="TRACE_SAMPLE_RATE")
    
    class Config:
        env_prefix = "OBSERVABILITY_"


class Settings(BaseSettings):
    """Main application settings."""
    
    # Service info
    service_name: str = Field(default="PyAirtable Automation Domain", env="SERVICE_NAME")
    service_version: str = Field(default="1.0.0", env="SERVICE_VERSION")
    description: str = Field(
        default="Consolidated automation domain service for workflow, notification, and webhook management",
        env="SERVICE_DESCRIPTION"
    )
    
    # Server config
    host: str = Field(default="0.0.0.0", env="HOST")
    port: int = Field(default=8090, env="PORT")
    workers: int = Field(default=1, env="WORKERS")
    reload: bool = Field(default=False, env="RELOAD")
    
    # Environment
    environment: str = Field(default="development", env="ENVIRONMENT")
    debug: bool = Field(default=False, env="DEBUG")
    
    # CORS
    cors_origins: List[str] = Field(default=["*"], env="CORS_ORIGINS")
    cors_allow_credentials: bool = Field(default=True, env="CORS_ALLOW_CREDENTIALS")
    cors_allow_methods: List[str] = Field(default=["*"], env="CORS_ALLOW_METHODS")
    cors_allow_headers: List[str] = Field(default=["*"], env="CORS_ALLOW_HEADERS")
    
    # Component settings
    database: DatabaseSettings = Field(default_factory=DatabaseSettings)
    redis: RedisSettings = Field(default_factory=RedisSettings)
    celery: CelerySettings = Field(default_factory=CelerySettings)
    security: SecuritySettings = Field(default_factory=SecuritySettings)
    notification: NotificationSettings = Field(default_factory=NotificationSettings)
    webhook: WebhookSettings = Field(default_factory=WebhookSettings)
    observability: ObservabilitySettings = Field(default_factory=ObservabilitySettings)
    
    @validator("cors_origins", pre=True)
    def parse_cors_origins(cls, v):
        """Parse CORS origins from string."""
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(",")]
        return v
    
    @validator("cors_allow_methods", pre=True)
    def parse_cors_methods(cls, v):
        """Parse CORS methods from string."""
        if isinstance(v, str):
            return [method.strip() for method in v.split(",")]
        return v
    
    @validator("cors_allow_headers", pre=True)
    def parse_cors_headers(cls, v):
        """Parse CORS headers from string."""
        if isinstance(v, str):
            return [header.strip() for header in v.split(",")]
        return v
    
    @property
    def is_development(self) -> bool:
        """Check if running in development mode."""
        return self.environment.lower() in ("development", "dev", "local")
    
    @property
    def is_production(self) -> bool:
        """Check if running in production mode."""
        return self.environment.lower() in ("production", "prod")
    
    @property
    def is_testing(self) -> bool:
        """Check if running in testing mode."""
        return self.environment.lower() in ("testing", "test")
    
    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    """Get cached application settings."""
    return Settings()