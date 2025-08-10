"""Configuration for Airtable Gateway service"""
import os
from typing import Optional
from pydantic_settings import BaseSettings
from pydantic import Field, validator
from functools import lru_cache


class Settings(BaseSettings):
    """Service configuration"""
    # Service info
    service_name: str = "airtable-gateway"
    service_version: str = "1.0.0"
    
    # Server config
    host: str = "0.0.0.0"
    port: int = 8002
    
    # Airtable config
    airtable_token: str = Field("", description="Airtable API token (required)")
    airtable_rate_limit: int = Field(5, description="Maximum requests per second")
    airtable_timeout: int = Field(30, description="Request timeout in seconds")
    airtable_retry_attempts: int = Field(3, description="Number of retry attempts for failed requests")
    airtable_retry_delay: float = Field(1.0, description="Initial delay between retries in seconds")
    
    # Redis config
    redis_url: str = "redis://localhost:6379/0"
    cache_ttl: int = 3600  # 1 hour default
    
    # Logging
    log_level: str = "INFO"
    
    # CORS
    cors_origins: list[str] = ["*"]
    
    # Security
    internal_api_key: str = ""
    
    @validator('airtable_token')
    def validate_airtable_token(cls, v: str) -> str:
        """Validate Airtable token format"""
        if not v:
            raise ValueError("AIRTABLE_TOKEN is required")
        
        # Check if token has proper format (starts with 'pat' for Personal Access Token)
        if not v.startswith(('pat', 'key')):
            raise ValueError(
                "Invalid Airtable token format. Token should start with 'pat' (Personal Access Token) "
                "or 'key' (API Key). Please check your AIRTABLE_TOKEN environment variable."
            )
        
        # Basic length validation
        if len(v) < 20:
            raise ValueError("Airtable token appears to be too short. Please verify your token.")
        
        return v
    
    @validator('airtable_rate_limit')
    def validate_rate_limit(cls, v: int) -> int:
        """Validate rate limit is reasonable"""
        if v <= 0 or v > 100:
            raise ValueError("Rate limit must be between 1 and 100 requests per second")
        return v
    
    @validator('airtable_retry_attempts')
    def validate_retry_attempts(cls, v: int) -> int:
        """Validate retry attempts"""
        if v < 0 or v > 10:
            raise ValueError("Retry attempts must be between 0 and 10")
        return v
    
    class Config:
        env_file = ".env"
        case_sensitive = False
        
    def get_masked_token(self) -> str:
        """Get masked version of token for logging"""
        if len(self.airtable_token) <= 8:
            return "***"
        return f"{self.airtable_token[:4]}***{self.airtable_token[-4:]}"


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance"""
    return Settings()