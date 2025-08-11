import os
from typing import Optional
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Service configuration
    port: int = 8006
    debug: bool = False
    log_level: str = "INFO"
    
    # Authentication
    api_key: str = ""
    auth_service_url: str = ""
    
    # Database
    database_url: str = ""
    
    # Redis
    redis_url: str = ""
    redis_password: Optional[str] = None
    
    # File processing
    max_file_size: str = "10MB"
    allowed_extensions: str = "pdf,doc,docx,txt,csv,xlsx"
    upload_dir: str = "/tmp/uploads"
    
    # Workflow settings
    default_workflow_timeout: int = 300  # 5 minutes
    max_workflow_retries: int = 3
    scheduler_check_interval: int = 30  # seconds
    
    # External services
    mcp_server_url: Optional[str] = None
    
    class Config:
        env_file = ".env"
        case_sensitive = False
        validate_default = True
    
    @property
    def max_file_size_bytes(self) -> int:
        """Convert max file size to bytes"""
        size_str = self.max_file_size.upper()
        if size_str.endswith('MB'):
            return int(size_str[:-2]) * 1024 * 1024
        elif size_str.endswith('KB'):
            return int(size_str[:-2]) * 1024
        elif size_str.endswith('GB'):
            return int(size_str[:-2]) * 1024 * 1024 * 1024
        else:
            return int(size_str)
    
    @property
    def allowed_extensions_list(self) -> list[str]:
        """Get allowed extensions as a list"""
        return [ext.strip().lower() for ext in self.allowed_extensions.split(',')]

# Global settings instance
settings = Settings()