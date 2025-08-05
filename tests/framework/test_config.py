"""
Comprehensive Integration Testing Framework Configuration
========================================================

This module provides configuration management for the PyAirtable integration testing framework.
It supports both local development and minikube deployment testing with environment-specific settings.
"""

import os
import json
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, field
from pathlib import Path
from enum import Enum

class TestEnvironment(Enum):
    """Test environment types"""
    LOCAL = "local"
    MINIKUBE = "minikube"
    DOCKER_COMPOSE = "docker-compose"
    KUBERNETES = "kubernetes"

class TestLevel(Enum):
    """Test execution levels"""
    UNIT = "unit"
    INTEGRATION = "integration"
    E2E = "e2e"
    PERFORMANCE = "performance"
    SECURITY = "security"

@dataclass
class ServiceConfig:
    """Configuration for individual services"""
    name: str
    url: str
    health_endpoint: str = "/health"
    timeout: int = 30
    retry_attempts: int = 3
    required: bool = True

@dataclass
class DatabaseConfig:
    """Database configuration for testing"""
    host: str = "localhost"
    port: int = 5432
    database: str = "pyairtablemcp"
    username: str = "admin"
    password: str = "changeme"
    cleanup_after_test: bool = True
    connection_timeout: int = 30

@dataclass
class BrowserConfig:
    """Browser configuration for UI testing"""
    browser_type: str = "chromium"  # chromium, firefox, webkit
    headless: bool = True
    viewport_width: int = 1920
    viewport_height: int = 1080
    slow_mo: int = 0  # Milliseconds to slow down operations
    video: bool = False
    screenshot_on_failure: bool = True
    trace: bool = False

@dataclass
class AirtableConfig:
    """Airtable API configuration"""
    base_id: str = "appVLUAubH5cFWhMV"
    api_key: str = "pya_d7f8e9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6"
    webhook_secret: Optional[str] = None
    rate_limit_per_second: int = 5
    timeout: int = 30

@dataclass
class GeminiConfig:
    """Gemini AI API configuration"""
    api_key: str = ""
    model: str = "gemini-2.5-flash"
    temperature: float = 0.7
    max_tokens: int = 8192
    timeout: int = 60

@dataclass
class TestFrameworkConfig:
    """Main configuration class for the testing framework"""
    
    # Environment settings
    environment: TestEnvironment = TestEnvironment.LOCAL
    test_level: TestLevel = TestLevel.INTEGRATION
    parallel_execution: bool = True
    max_workers: int = 4
    
    # Service configurations
    services: Dict[str, ServiceConfig] = field(default_factory=dict)
    
    # Database configuration
    database: DatabaseConfig = field(default_factory=DatabaseConfig)
    
    # Browser configuration for UI tests
    browser: BrowserConfig = field(default_factory=BrowserConfig)
    
    # External API configurations
    airtable: AirtableConfig = field(default_factory=AirtableConfig)
    gemini: GeminiConfig = field(default_factory=GeminiConfig)
    
    # Test execution settings
    timeout: int = 300  # Overall test timeout in seconds
    retry_attempts: int = 3
    retry_delay: float = 2.0
    fail_fast: bool = False
    
    # Reporting settings
    generate_html_report: bool = True
    generate_json_report: bool = True
    save_screenshots: bool = True
    save_traces: bool = False
    save_videos: bool = False
    
    # Test data settings
    use_test_data_factories: bool = True
    cleanup_test_data: bool = True
    preserve_data_on_failure: bool = True
    
    # Performance testing settings
    load_test_users: int = 10
    load_test_duration: int = 60
    performance_threshold_ms: int = 1000
    
    # Security testing settings
    enable_security_scans: bool = True
    check_sql_injection: bool = True
    check_xss: bool = True
    check_csrf: bool = True
    
    def __post_init__(self):
        """Initialize default service configurations"""
        if not self.services:
            self._initialize_default_services()
    
    def _initialize_default_services(self):
        """Initialize default service configurations based on environment"""
        base_urls = self._get_base_urls()
        
        self.services = {
            "api_gateway": ServiceConfig(
                name="API Gateway",
                url=base_urls["api_gateway"],
                health_endpoint="/api/health"
            ),
            "llm_orchestrator": ServiceConfig(
                name="LLM Orchestrator",
                url=base_urls["llm_orchestrator"],
                health_endpoint="/health"
            ),
            "mcp_server": ServiceConfig(
                name="MCP Server",
                url=base_urls["mcp_server"],
                health_endpoint="/health"
            ),
            "airtable_gateway": ServiceConfig(
                name="Airtable Gateway",
                url=base_urls["airtable_gateway"],
                health_endpoint="/health"
            ),
            "platform_services": ServiceConfig(
                name="Platform Services",
                url=base_urls["platform_services"],
                health_endpoint="/health"
            ),
            "automation_services": ServiceConfig(
                name="Automation Services",
                url=base_urls["automation_services"],
                health_endpoint="/health"
            ),
            "saga_orchestrator": ServiceConfig(
                name="SAGA Orchestrator",
                url=base_urls["saga_orchestrator"],
                health_endpoint="/health"
            ),
            "frontend": ServiceConfig(
                name="Frontend",
                url=base_urls["frontend"],
                health_endpoint="/api/health"
            )
        }
    
    def _get_base_urls(self) -> Dict[str, str]:
        """Get base URLs based on environment"""
        if self.environment == TestEnvironment.LOCAL:
            return {
                "api_gateway": "http://localhost:8000",
                "llm_orchestrator": "http://localhost:8003",
                "mcp_server": "http://localhost:8001",
                "airtable_gateway": "http://localhost:8002",
                "platform_services": "http://localhost:8007",
                "automation_services": "http://localhost:8006",
                "saga_orchestrator": "http://localhost:8008",
                "frontend": "http://localhost:3000"
            }
        elif self.environment == TestEnvironment.MINIKUBE:
            # Get minikube IP
            minikube_ip = self._get_minikube_ip()
            return {
                "api_gateway": f"http://{minikube_ip}:30800",
                "llm_orchestrator": f"http://{minikube_ip}:30803",
                "mcp_server": f"http://{minikube_ip}:30801",
                "airtable_gateway": f"http://{minikube_ip}:30802",
                "platform_services": f"http://{minikube_ip}:30807",
                "automation_services": f"http://{minikube_ip}:30806",
                "saga_orchestrator": f"http://{minikube_ip}:30808",
                "frontend": f"http://{minikube_ip}:30300"
            }
        else:
            # Default to localhost for other environments
            return self._get_base_urls_for_local()
    
    def _get_minikube_ip(self) -> str:
        """Get minikube IP address"""
        try:
            import subprocess
            result = subprocess.run(
                ["minikube", "ip"], 
                capture_output=True, 
                text=True, 
                check=True
            )
            return result.stdout.strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            return "192.168.49.2"  # Default minikube IP
    
    def _get_base_urls_for_local(self) -> Dict[str, str]:
        """Fallback method for local URLs"""
        return {
            "api_gateway": "http://localhost:8000",
            "llm_orchestrator": "http://localhost:8003",
            "mcp_server": "http://localhost:8001",
            "airtable_gateway": "http://localhost:8002",
            "platform_services": "http://localhost:8007",
            "automation_services": "http://localhost:8006",
            "saga_orchestrator": "http://localhost:8008",
            "frontend": "http://localhost:3000"
        }
    
    @classmethod
    def from_file(cls, config_path: str) -> 'TestFrameworkConfig':
        """Load configuration from JSON file"""
        config_file = Path(config_path)
        if not config_file.exists():
            raise FileNotFoundError(f"Configuration file not found: {config_path}")
        
        with open(config_file, 'r') as f:
            config_data = json.load(f)
        
        return cls.from_dict(config_data)
    
    @classmethod
    def from_dict(cls, config_dict: Dict[str, Any]) -> 'TestFrameworkConfig':
        """Create configuration from dictionary"""
        config = cls()
        
        # Update environment settings
        if 'environment' in config_dict:
            config.environment = TestEnvironment(config_dict['environment'])
        
        if 'test_level' in config_dict:
            config.test_level = TestLevel(config_dict['test_level'])
        
        # Update other settings
        for key, value in config_dict.items():
            if hasattr(config, key) and key not in ['environment', 'test_level']:
                if key == 'database' and isinstance(value, dict):
                    config.database = DatabaseConfig(**value)
                elif key == 'browser' and isinstance(value, dict):
                    config.browser = BrowserConfig(**value)
                elif key == 'airtable' and isinstance(value, dict):
                    config.airtable = AirtableConfig(**value)
                elif key == 'gemini' and isinstance(value, dict):
                    config.gemini = GeminiConfig(**value)
                elif key == 'services' and isinstance(value, dict):
                    config.services = {
                        name: ServiceConfig(**service_config)
                        for name, service_config in value.items()
                    }
                else:
                    setattr(config, key, value)
        
        return config
    
    @classmethod
    def from_env(cls) -> 'TestFrameworkConfig':
        """Create configuration from environment variables"""
        config = cls()
        
        # Environment settings
        if os.getenv('TEST_ENVIRONMENT'):
            config.environment = TestEnvironment(os.getenv('TEST_ENVIRONMENT'))
        
        if os.getenv('TEST_LEVEL'):
            config.test_level = TestLevel(os.getenv('TEST_LEVEL'))
        
        # Database settings
        if os.getenv('POSTGRES_HOST'):
            config.database.host = os.getenv('POSTGRES_HOST')
        if os.getenv('POSTGRES_PORT'):
            config.database.port = int(os.getenv('POSTGRES_PORT'))
        if os.getenv('POSTGRES_DB'):
            config.database.database = os.getenv('POSTGRES_DB')
        if os.getenv('POSTGRES_USER'):
            config.database.username = os.getenv('POSTGRES_USER')
        if os.getenv('POSTGRES_PASSWORD'):
            config.database.password = os.getenv('POSTGRES_PASSWORD')
        
        # Browser settings
        if os.getenv('BROWSER_TYPE'):
            config.browser.browser_type = os.getenv('BROWSER_TYPE')
        if os.getenv('HEADLESS'):
            config.browser.headless = os.getenv('HEADLESS').lower() == 'true'
        
        # API keys
        if os.getenv('AIRTABLE_TOKEN'):
            config.airtable.api_key = os.getenv('AIRTABLE_TOKEN')
        if os.getenv('AIRTABLE_BASE'):
            config.airtable.base_id = os.getenv('AIRTABLE_BASE')
        if os.getenv('GEMINI_API_KEY'):
            config.gemini.api_key = os.getenv('GEMINI_API_KEY')
        
        # Test execution settings
        if os.getenv('TEST_TIMEOUT'):
            config.timeout = int(os.getenv('TEST_TIMEOUT'))
        if os.getenv('TEST_PARALLEL'):
            config.parallel_execution = os.getenv('TEST_PARALLEL').lower() == 'true'
        if os.getenv('MAX_WORKERS'):
            config.max_workers = int(os.getenv('MAX_WORKERS'))
        
        return config
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert configuration to dictionary"""
        return {
            'environment': self.environment.value,
            'test_level': self.test_level.value,
            'parallel_execution': self.parallel_execution,
            'max_workers': self.max_workers,
            'services': {
                name: {
                    'name': service.name,
                    'url': service.url,
                    'health_endpoint': service.health_endpoint,
                    'timeout': service.timeout,
                    'retry_attempts': service.retry_attempts,
                    'required': service.required
                }
                for name, service in self.services.items()
            },
            'database': {
                'host': self.database.host,
                'port': self.database.port,
                'database': self.database.database,
                'username': self.database.username,
                'password': self.database.password,
                'cleanup_after_test': self.database.cleanup_after_test,
                'connection_timeout': self.database.connection_timeout
            },
            'browser': {
                'browser_type': self.browser.browser_type,
                'headless': self.browser.headless,
                'viewport_width': self.browser.viewport_width,
                'viewport_height': self.browser.viewport_height,
                'slow_mo': self.browser.slow_mo,
                'video': self.browser.video,
                'screenshot_on_failure': self.browser.screenshot_on_failure,
                'trace': self.browser.trace
            },
            'airtable': {
                'base_id': self.airtable.base_id,
                'api_key': self.airtable.api_key,
                'webhook_secret': self.airtable.webhook_secret,
                'rate_limit_per_second': self.airtable.rate_limit_per_second,
                'timeout': self.airtable.timeout
            },
            'gemini': {
                'api_key': self.gemini.api_key,
                'model': self.gemini.model,
                'temperature': self.gemini.temperature,
                'max_tokens': self.gemini.max_tokens,
                'timeout': self.gemini.timeout
            },
            'timeout': self.timeout,
            'retry_attempts': self.retry_attempts,
            'retry_delay': self.retry_delay,
            'fail_fast': self.fail_fast,
            'generate_html_report': self.generate_html_report,
            'generate_json_report': self.generate_json_report,
            'save_screenshots': self.save_screenshots,
            'save_traces': self.save_traces,
            'save_videos': self.save_videos,
            'use_test_data_factories': self.use_test_data_factories,
            'cleanup_test_data': self.cleanup_test_data,
            'preserve_data_on_failure': self.preserve_data_on_failure,
            'load_test_users': self.load_test_users,
            'load_test_duration': self.load_test_duration,
            'performance_threshold_ms': self.performance_threshold_ms,
            'enable_security_scans': self.enable_security_scans,
            'check_sql_injection': self.check_sql_injection,
            'check_xss': self.check_xss,
            'check_csrf': self.check_csrf
        }
    
    def save_to_file(self, config_path: str):
        """Save configuration to JSON file"""
        config_file = Path(config_path)
        config_file.parent.mkdir(parents=True, exist_ok=True)
        
        with open(config_file, 'w') as f:
            json.dump(self.to_dict(), f, indent=2)
    
    def validate(self) -> List[str]:
        """Validate configuration and return list of issues"""
        issues = []
        
        # Validate required services
        required_services = ['api_gateway', 'frontend']
        for service_name in required_services:
            if service_name not in self.services:
                issues.append(f"Required service '{service_name}' not configured")
        
        # Validate API keys
        if not self.airtable.api_key:
            issues.append("Airtable API key is required")
        
        if not self.gemini.api_key:
            issues.append("Gemini API key is required")
        
        # Validate timeouts
        if self.timeout <= 0:
            issues.append("Timeout must be positive")
        
        if self.retry_attempts < 0:
            issues.append("Retry attempts cannot be negative")
        
        # Validate browser settings
        valid_browsers = ['chromium', 'firefox', 'webkit']
        if self.browser.browser_type not in valid_browsers:
            issues.append(f"Browser type must be one of: {valid_browsers}")
        
        return issues

# Global configuration instance
_config = None

def get_config() -> TestFrameworkConfig:
    """Get the global configuration instance"""
    global _config
    if _config is None:
        _config = TestFrameworkConfig.from_env()
    return _config

def set_config(config: TestFrameworkConfig):
    """Set the global configuration instance"""
    global _config
    _config = config

def load_config_from_file(config_path: str) -> TestFrameworkConfig:
    """Load and set configuration from file"""
    config = TestFrameworkConfig.from_file(config_path)
    set_config(config)
    return config