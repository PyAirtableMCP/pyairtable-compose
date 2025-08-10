"""Configuration management for SAGA Orchestrator service."""

import logging
from functools import lru_cache
from typing import List, Optional, Union

from pydantic import Field, PostgresDsn, RedisDsn, validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings."""
    
    # Application
    app_name: str = "PyAirtable SAGA Orchestrator"
    version: str = "0.1.0"
    debug: bool = False
    environment: str = Field(default="development", env="ENVIRONMENT")
    
    # Server
    host: str = "0.0.0.0"
    port: int = 8008
    log_level: str = "INFO"
    
    # Security
    api_key: Optional[str] = Field(default=None, env="API_KEY")
    require_api_key: bool = True
    
    # Database
    database_url: PostgresDsn = Field(
        default="postgresql://postgres:postgres@localhost:5432/pyairtable",
        env="DATABASE_URL"
    )
    
    # Redis
    redis_url: RedisDsn = Field(
        default="redis://localhost:6379",
        env="REDIS_URL"
    )
    redis_password: Optional[str] = Field(default=None, env="REDIS_PASSWORD")
    
    # Kafka Configuration
    kafka_bootstrap_servers: List[str] = Field(
        default=["localhost:9092"],
        env="KAFKA_BOOTSTRAP_SERVERS"
    )
    kafka_schema_registry_url: Optional[str] = Field(
        default=None,
        env="KAFKA_SCHEMA_REGISTRY_URL"
    )
    
    # Use Redis for event bus if Kafka is not available
    use_redis_event_bus: bool = Field(default=True, env="USE_REDIS_EVENT_BUS")
    
    # SAGA Configuration
    saga_timeout_seconds: int = Field(default=3600, env="SAGA_TIMEOUT_SECONDS")  # 1 hour
    saga_retry_attempts: int = Field(default=3, env="SAGA_RETRY_ATTEMPTS")
    saga_step_timeout_seconds: int = Field(default=300, env="SAGA_STEP_TIMEOUT_SECONDS")  # 5 minutes
    
    # Event Store Configuration
    event_store_retention_days: int = Field(default=90, env="EVENT_STORE_RETENTION_DAYS")
    
    # Service URLs for SAGA steps
    auth_service_url: str = Field(default="http://platform-services:8007", env="AUTH_SERVICE_URL")
    user_service_url: str = Field(default="http://platform-services:8007", env="USER_SERVICE_URL")
    permission_service_url: str = Field(default="http://platform-services:8007", env="PERMISSION_SERVICE_URL")
    notification_service_url: str = Field(default="http://automation-services:8006", env="NOTIFICATION_SERVICE_URL")
    airtable_connector_url: str = Field(default="http://airtable-gateway:8002", env="AIRTABLE_CONNECTOR_URL")
    schema_service_url: str = Field(default="http://platform-services:8007", env="SCHEMA_SERVICE_URL")
    webhook_service_url: str = Field(default="http://automation-services:8006", env="WEBHOOK_SERVICE_URL")
    data_sync_service_url: str = Field(default="http://automation-services:8006", env="DATA_SYNC_SERVICE_URL")
    
    # Monitoring and Observability
    enable_metrics: bool = Field(default=True, env="ENABLE_METRICS")
    metrics_port: int = Field(default=9090, env="METRICS_PORT")
    
    # CORS - raw string that gets parsed to list
    cors_origins_raw: str = Field(default="*", env="CORS_ORIGINS")
    
    @validator("kafka_bootstrap_servers", pre=True)
    def parse_kafka_servers(cls, v):
        if isinstance(v, str):
            return [server.strip() for server in v.split(",")]
        return v
    
    @property 
    def cors_origins(self) -> List[str]:
        """Parse CORS origins from raw string to list."""
        v = self.cors_origins_raw
        if not v or not v.strip():
            return ["*"]
        if v.strip() == "*":
            return ["*"]
        return [origin.strip() for origin in v.split(",") if origin.strip()]
    
    @validator("log_level")
    def validate_log_level(cls, v):
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if v.upper() not in valid_levels:
            raise ValueError(f"Log level must be one of: {valid_levels}")
        return v.upper()
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()


def setup_logging(settings: Settings) -> None:
    """Setup application logging."""
    logging.basicConfig(
        level=getattr(logging, settings.log_level),
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        handlers=[
            logging.StreamHandler(),
        ]
    )
    
    # Set specific loggers
    loggers = [
        "saga_orchestrator",
        "uvicorn",
        "fastapi",
        "sqlalchemy.engine",
        "kafka",
        "redis",
    ]
    
    for logger_name in loggers:
        logger = logging.getLogger(logger_name)
        logger.setLevel(getattr(logging, settings.log_level))