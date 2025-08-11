"""Unit tests for configuration management."""

import os
import pytest

from src.core.config import Settings, get_settings


@pytest.mark.unit
def test_settings_creation():
    """Test settings object creation."""
    settings = Settings()
    
    assert settings.service_name == "PyAirtable Automation Domain"
    assert settings.service_version == "1.0.0"
    assert settings.host == "0.0.0.0"
    assert settings.port == 8090


@pytest.mark.unit
def test_environment_detection():
    """Test environment detection."""
    # Test development
    os.environ["ENV"] = "development"
    settings = Settings()
    assert settings.is_development is True
    assert settings.is_production is False
    assert settings.is_testing is False
    
    # Test production
    os.environ["ENV"] = "production"
    settings = Settings()
    assert settings.is_development is False
    assert settings.is_production is True
    assert settings.is_testing is False
    
    # Test testing
    os.environ["ENV"] = "testing"
    settings = Settings()
    assert settings.is_development is False
    assert settings.is_production is False
    assert settings.is_testing is True


@pytest.mark.unit
def test_database_settings():
    """Test database configuration."""
    settings = Settings()
    
    assert settings.database.pool_size == 10
    assert settings.database.max_overflow == 20
    assert settings.database.echo is False


@pytest.mark.unit
def test_redis_settings():
    """Test Redis configuration."""
    settings = Settings()
    
    assert settings.redis.max_connections == 20
    assert settings.redis.retry_on_timeout is True


@pytest.mark.unit
def test_celery_settings():
    """Test Celery configuration."""
    settings = Settings()
    
    assert settings.celery.task_serializer == "json"
    assert settings.celery.timezone == "UTC"
    assert settings.celery.enable_utc is True
    assert settings.celery.task_time_limit == 30 * 60  # 30 minutes
    assert settings.celery.worker_prefetch_multiplier == 1


@pytest.mark.unit
def test_notification_settings():
    """Test notification configuration."""
    settings = Settings()
    
    assert settings.notification.smtp_port == 587
    assert settings.notification.smtp_use_tls is True
    assert settings.notification.from_email == "noreply@pyairtable.com"
    assert settings.notification.email_rate_limit == 100


@pytest.mark.unit
def test_webhook_settings():
    """Test webhook configuration."""
    settings = Settings()
    
    assert settings.webhook.max_retries == 3
    assert settings.webhook.retry_delay == 60
    assert settings.webhook.timeout == 30
    assert settings.webhook.verify_ssl is True
    assert settings.webhook.signature_header == "X-Webhook-Signature"


@pytest.mark.unit
def test_observability_settings():
    """Test observability configuration."""
    settings = Settings()
    
    assert settings.observability.enable_metrics is True
    assert settings.observability.enable_tracing is True
    assert settings.observability.log_level == "INFO"
    assert settings.observability.structured_logging is True


@pytest.mark.unit
def test_cors_parsing():
    """Test CORS configuration parsing."""
    # Test string parsing
    os.environ["CORS_ORIGINS"] = "http://localhost:3000,https://app.example.com"
    settings = Settings()
    
    assert "http://localhost:3000" in settings.cors_origins
    assert "https://app.example.com" in settings.cors_origins
    
    # Test methods parsing
    os.environ["CORS_ALLOW_METHODS"] = "GET,POST,PUT,DELETE"
    settings = Settings()
    
    assert "GET" in settings.cors_allow_methods
    assert "POST" in settings.cors_allow_methods
    assert "PUT" in settings.cors_allow_methods
    assert "DELETE" in settings.cors_allow_methods


@pytest.mark.unit
def test_get_settings_cached():
    """Test that get_settings returns cached instance."""
    settings1 = get_settings()
    settings2 = get_settings()
    
    # Should be the same instance due to lru_cache
    assert settings1 is settings2