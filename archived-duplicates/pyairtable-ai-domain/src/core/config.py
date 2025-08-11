"""Configuration management for AI domain service"""
import os
from functools import lru_cache
from typing import Optional, List, Dict, Any
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """AI Domain Service Settings"""
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="allow"
    )
    
    # Service configuration
    service_name: str = "pyairtable-ai-domain"
    service_version: str = "1.0.0"
    port: int = Field(default=8080, ge=1, le=65535)
    host: str = "0.0.0.0"
    debug: bool = False
    log_level: str = "INFO"
    
    # Database
    database_url: str = Field(
        default="postgresql://postgres:password@localhost:5432/pyairtable_ai",
        description="PostgreSQL database URL"
    )
    
    # Redis
    redis_url: str = Field(
        default="redis://localhost:6379/0",
        description="Redis URL for caching and session storage"
    )
    
    # LLM Provider Settings
    
    # OpenAI
    openai_api_key: Optional[str] = None
    openai_organization: Optional[str] = None
    openai_base_url: Optional[str] = None
    
    # Anthropic
    anthropic_api_key: Optional[str] = None
    
    # Google Gemini
    gemini_api_key: Optional[str] = None
    gemini_model: str = "gemini-2.0-flash-exp"
    
    # Azure OpenAI
    azure_openai_api_key: Optional[str] = None
    azure_openai_endpoint: Optional[str] = None
    azure_openai_api_version: str = "2024-02-01"
    
    # Ollama
    ollama_base_url: str = "http://localhost:11434"
    
    # Model Configuration
    default_model: str = "gpt-4o-mini"
    max_tokens: int = 4096
    temperature: float = 0.7
    thinking_budget: int = 20000  # For Gemini flash models
    
    # Cost tracking
    enable_cost_tracking: bool = True
    cost_alert_threshold: float = 100.0  # USD
    
    # Token limits
    max_prompt_tokens: int = 128000
    max_completion_tokens: int = 4096
    token_buffer: int = 1000
    
    # Embedding Settings
    embedding_model: str = "text-embedding-3-small"
    embedding_dimensions: int = 1536
    batch_size: int = 100
    
    # Vector Database Settings
    vector_db_provider: str = "qdrant"  # qdrant, pinecone, weaviate, chroma
    
    # Qdrant
    qdrant_url: str = "http://localhost:6333"
    qdrant_api_key: Optional[str] = None
    qdrant_collection: str = "embeddings"
    
    # Pinecone
    pinecone_api_key: Optional[str] = None
    pinecone_environment: str = "us-east-1-aws"
    pinecone_index_name: str = "pyairtable-embeddings"
    
    # Weaviate
    weaviate_url: str = "http://localhost:8080"
    weaviate_api_key: Optional[str] = None
    weaviate_class_name: str = "Document"
    
    # ChromaDB
    chroma_host: str = "localhost"
    chroma_port: int = 8000
    chroma_collection: str = "embeddings"
    
    # Model Serving Settings
    model_cache_size: int = 5  # Number of models to keep in memory
    model_cache_ttl: int = 3600  # Cache TTL in seconds
    enable_model_warming: bool = True
    
    # MCP Settings
    mcp_mode: str = "hybrid"  # rpc, rest, hybrid
    mcp_tools_enabled: List[str] = Field(
        default_factory=lambda: [
            "airtable_list_bases",
            "airtable_get_schema",
            "airtable_list_records",
            "airtable_get_record",
            "airtable_create_records",
            "airtable_update_records",
            "airtable_delete_records",
            "calculate",
            "search",
            "query_database",
        ]
    )
    
    # External Service URLs
    airtable_gateway_url: str = "http://localhost:8001"
    auth_service_url: str = "http://localhost:8002"
    
    # Rate Limiting
    rate_limit_requests_per_minute: int = 100
    rate_limit_tokens_per_minute: int = 100000
    
    # Monitoring
    enable_metrics: bool = True
    metrics_port: int = 9090
    
    # Session Management
    session_ttl: int = 3600  # seconds
    max_session_history: int = 100  # messages per session
    
    # Response Caching
    enable_response_caching: bool = True
    cache_ttl: int = 300  # seconds
    cache_key_include_user: bool = True
    
    # Security
    jwt_secret_key: str = Field(
        default="your-secret-key-change-in-production",
        description="JWT secret key"
    )
    jwt_algorithm: str = "HS256"
    jwt_expiration_hours: int = 24
    
    # API Keys for internal services
    internal_api_key: Optional[str] = None
    
    # Features flags
    enable_streaming: bool = True
    enable_function_calling: bool = True
    enable_multi_modal: bool = True
    enable_fine_tuning: bool = False
    
    @property
    def available_providers(self) -> List[str]:
        """Get list of available LLM providers based on configured API keys"""
        providers = []
        if self.openai_api_key:
            providers.append("openai")
        if self.anthropic_api_key:
            providers.append("anthropic")
        if self.gemini_api_key:
            providers.append("google")
        if self.azure_openai_api_key:
            providers.append("azure")
        providers.append("ollama")  # Always available if running locally
        return providers
    
    @property
    def cost_tracking_config(self) -> Dict[str, Any]:
        """Get cost tracking configuration"""
        return {
            "enabled": self.enable_cost_tracking,
            "alert_threshold": self.cost_alert_threshold,
            "providers": {
                "openai": {
                    "gpt-4o": {"input": 2.50/1_000_000, "output": 10.00/1_000_000},
                    "gpt-4o-mini": {"input": 0.15/1_000_000, "output": 0.60/1_000_000},
                    "gpt-4": {"input": 30.00/1_000_000, "output": 60.00/1_000_000},
                    "gpt-3.5-turbo": {"input": 0.50/1_000_000, "output": 1.50/1_000_000},
                },
                "anthropic": {
                    "claude-3-5-sonnet": {"input": 3.00/1_000_000, "output": 15.00/1_000_000},
                    "claude-3-opus": {"input": 15.00/1_000_000, "output": 75.00/1_000_000},
                    "claude-3-haiku": {"input": 0.25/1_000_000, "output": 1.25/1_000_000},
                },
                "google": {
                    "gemini-2.0-flash-exp": {"input": 0.25/1_000_000, "output": 1.00/1_000_000},
                    "gemini-1.5-pro": {"input": 3.50/1_000_000, "output": 14.00/1_000_000},
                }
            }
        }


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance"""
    return Settings()