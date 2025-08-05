"""
PyAirtable Comprehensive Integration Testing Framework
======================================================

This package provides a comprehensive integration testing framework for the PyAirtable
application with synthetic UI agents, API testing, external API integration testing,
and user workflow scenarios.

Main Components:
- UI Agents: Playwright-based synthetic agents for browser automation
- API Testing: Comprehensive testing for all microservices
- External API Testing: Airtable WebAPI and Gemini AI integration testing
- Workflow Scenarios: End-to-end user journey testing
- Data Management: Test data factories and database validation
- Test Reporting: Comprehensive reporting with failure diagnostics
- Test Orchestration: Centralized test execution and continuous testing

Usage:
    # Simple API testing
    from tests.framework import run_smoke_tests
    result = await run_smoke_tests()
    
    # Comprehensive testing
    from tests.framework import TestOrchestrator
    orchestrator = TestOrchestrator()
    report = await orchestrator.run_test_suites(["comprehensive"])
    
    # UI automation
    from tests.framework.ui_agents import ChatInterfaceAgent
    async with ChatInterfaceAgent() as agent:
        result = await agent.test_chat_functionality()
    
    # CLI interface
    python -m tests.framework.cli health
    python -m tests.framework.cli comprehensive --verbose
"""

__version__ = "1.0.0"
__author__ = "PyAirtable Testing Framework"
__description__ = "Comprehensive integration testing framework with synthetic UI agents"

# Core imports for easy access
from .test_config import TestFrameworkConfig, TestEnvironment, TestLevel, get_config, set_config
from .test_orchestrator import (
    TestOrchestrator,
    run_smoke_tests,
    run_integration_tests,
    run_comprehensive_tests,
    run_health_check,
    start_continuous_testing
)
from .test_reporter import TestResult, TestReport
from .ui_agents import (
    SyntheticUIAgent,
    ChatInterfaceAgent,
    DataAnalysisAgent,
    PerformanceTestingAgent,
    UITestOrchestrator
)
from .api_testing import (
    APITestOrchestrator,
    IntegrationAPITester,
    BaseAPITester
)
from .external_api_testing import (
    ExternalAPITestOrchestrator,
    AirtableAPITester,
    GeminiAPITester
)
from .workflow_scenarios import (
    WorkflowTestOrchestrator,
    WorkflowScenarios,
    UserWorkflow,
    WorkflowStep
)
from .data_management import (
    TestDataManager,
    TestDataFactory,
    DatabaseStateValidator,
    RedisStateManager
)

# Framework metadata
FRAMEWORK_INFO = {
    "name": "PyAirtable Integration Testing Framework",
    "version": __version__,
    "description": __description__,
    "components": [
        "UI Automation Agents",
        "API Testing Framework", 
        "External API Integration Testing",
        "User Workflow Scenarios",
        "Test Data Management",
        "Comprehensive Reporting",
        "Continuous Testing"
    ],
    "supported_environments": [
        "local",
        "minikube", 
        "docker-compose",
        "kubernetes"
    ],
    "supported_browsers": [
        "chromium",
        "firefox", 
        "webkit"
    ],
    "external_integrations": [
        "Airtable WebAPI",
        "Gemini AI API",
        "PostgreSQL",
        "Redis"
    ]
}

def get_framework_info():
    """Get framework information"""
    return FRAMEWORK_INFO

def print_framework_info():
    """Print framework information"""
    info = get_framework_info()
    print(f"\n{'='*60}")
    print(f"{info['name']} v{info['version']}")
    print(f"{'='*60}")
    print(f"Description: {info['description']}")
    print(f"\nComponents:")
    for component in info['components']:
        print(f"  • {component}")
    print(f"\nSupported Environments:")
    for env in info['supported_environments']:
        print(f"  • {env}")
    print(f"\nExternal Integrations:")
    for integration in info['external_integrations']:
        print(f"  • {integration}")
    print(f"{'='*60}")

# Quick start functions
async def quick_health_check():
    """Quick health check of the system"""
    return await run_health_check()

async def quick_smoke_test():
    """Quick smoke test execution"""
    return await run_smoke_tests()

async def quick_ui_test():
    """Quick UI test execution"""
    from .ui_agents import UITestOrchestrator
    orchestrator = UITestOrchestrator()
    return await orchestrator.run_all_tests()

async def quick_api_test():
    """Quick API test execution"""
    from .api_testing import APITestOrchestrator
    orchestrator = APITestOrchestrator()
    return await orchestrator.run_comprehensive_api_tests()

# Configuration helpers
def create_local_config(**kwargs):
    """Create configuration for local testing"""
    config = TestFrameworkConfig()
    config.environment = TestEnvironment.LOCAL
    
    # Apply any custom settings
    for key, value in kwargs.items():
        if hasattr(config, key):
            setattr(config, key, value)
    
    return config

def create_minikube_config(**kwargs):
    """Create configuration for minikube testing"""
    config = TestFrameworkConfig()
    config.environment = TestEnvironment.MINIKUBE
    
    # Apply any custom settings
    for key, value in kwargs.items():
        if hasattr(config, key):
            setattr(config, key, value)
    
    return config

# Test suite presets
async def run_developer_tests():
    """Run tests suitable for developer workflow"""
    orchestrator = TestOrchestrator()
    return await orchestrator.run_test_suites(["smoke", "api"])

async def run_ci_tests():
    """Run tests suitable for CI/CD pipeline"""
    orchestrator = TestOrchestrator()
    return await orchestrator.run_test_suites(["integration", "api"])

async def run_qa_tests():
    """Run tests suitable for QA validation"""
    orchestrator = TestOrchestrator()
    return await orchestrator.run_test_suites(["comprehensive"])

async def run_performance_tests():
    """Run performance and stress tests"""
    orchestrator = TestOrchestrator()
    return await orchestrator.run_test_suites(["performance"])

# Export all public interfaces
__all__ = [
    # Version info
    "__version__",
    "FRAMEWORK_INFO",
    "get_framework_info",
    "print_framework_info",
    
    # Core configuration
    "TestFrameworkConfig",
    "TestEnvironment", 
    "TestLevel",
    "get_config",
    "set_config",
    "create_local_config",
    "create_minikube_config",
    
    # Main orchestrator
    "TestOrchestrator",
    "run_smoke_tests",
    "run_integration_tests", 
    "run_comprehensive_tests",
    "run_health_check",
    "start_continuous_testing",
    
    # Test reporting
    "TestResult",
    "TestReport",
    
    # UI automation
    "SyntheticUIAgent",
    "ChatInterfaceAgent",
    "DataAnalysisAgent", 
    "PerformanceTestingAgent",
    "UITestOrchestrator",
    
    # API testing
    "APITestOrchestrator",
    "IntegrationAPITester",
    "BaseAPITester",
    
    # External API testing
    "ExternalAPITestOrchestrator",
    "AirtableAPITester",
    "GeminiAPITester",
    
    # Workflow testing
    "WorkflowTestOrchestrator",
    "WorkflowScenarios",
    "UserWorkflow",
    "WorkflowStep",
    
    # Data management
    "TestDataManager",
    "TestDataFactory",
    "DatabaseStateValidator",
    "RedisStateManager",
    
    # Quick start functions
    "quick_health_check",
    "quick_smoke_test",
    "quick_ui_test", 
    "quick_api_test",
    
    # Test suite presets
    "run_developer_tests",
    "run_ci_tests",
    "run_qa_tests",
    "run_performance_tests"
]