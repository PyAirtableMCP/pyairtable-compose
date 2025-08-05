#!/usr/bin/env python3
"""
PyAirtable Integration Testing Framework - Main Execution Script
================================================================

This script provides the main entry point for running the comprehensive PyAirtable
integration testing framework. It can be used for local development, CI/CD pipelines,
and continuous testing scenarios.

Usage Examples:
    # Quick health check
    python tests/run_integration_tests.py --suite health
    
    # Run smoke tests for development
    python tests/run_integration_tests.py --suite smoke --verbose
    
    # Run comprehensive tests for QA
    python tests/run_integration_tests.py --suite comprehensive --environment minikube
    
    # Start continuous testing for local development  
    python tests/run_integration_tests.py --continuous --interval 300
    
    # Run specific workflow scenarios
    python tests/run_integration_tests.py --workflow new_user_onboarding --headless false
"""

import asyncio
import argparse
import json
import logging
import os
import sys
from pathlib import Path
from typing import List, Optional

# Add the tests directory to Python path
tests_dir = Path(__file__).parent
sys.path.insert(0, str(tests_dir))

# Import framework components
from framework import (
    TestFrameworkConfig,
    TestOrchestrator,
    TestEnvironment,
    TestLevel,
    run_health_check,
    print_framework_info,
    FRAMEWORK_INFO
)
from framework.workflow_scenarios import WorkflowScenarios

def setup_logging(verbose: bool = False, log_file: Optional[str] = None):
    """Setup logging configuration"""
    log_level = logging.DEBUG if verbose else logging.INFO
    
    # Create formatter
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Setup console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(log_level)
    console_handler.setFormatter(formatter)
    
    # Setup root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)
    root_logger.addHandler(console_handler)
    
    # Setup file handler if specified
    if log_file:
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(formatter)
        root_logger.addHandler(file_handler)
    
    # Reduce noise from third-party libraries
    for logger_name in ['httpx', 'urllib3', 'asyncio', 'selenium']:
        logging.getLogger(logger_name).setLevel(logging.WARNING)

def load_configuration(config_file: Optional[str] = None, 
                      environment: Optional[str] = None,
                      test_level: Optional[str] = None,
                      **kwargs) -> TestFrameworkConfig:
    """Load and configure the test framework"""
    if config_file and os.path.exists(config_file):
        config = TestFrameworkConfig.from_file(config_file)
        print(f"📁 Loaded configuration from: {config_file}")
    else:
        config = TestFrameworkConfig.from_env()
        print("🔧 Using environment-based configuration")
    
    # Override settings from command line
    if environment:
        try:
            config.environment = TestEnvironment(environment)
            print(f"🌍 Environment set to: {environment}")
        except ValueError:
            print(f"⚠️  Invalid environment '{environment}', using default")
    
    if test_level:
        try:
            config.test_level = TestLevel(test_level)
            print(f"🎯 Test level set to: {test_level}")
        except ValueError:
            print(f"⚠️  Invalid test level '{test_level}', using default")
    
    # Apply additional overrides
    for key, value in kwargs.items():
        if hasattr(config, key):
            setattr(config, key, value)
            print(f"⚙️  Override: {key} = {value}")
    
    # Validate configuration
    issues = config.validate()
    if issues:
        print("⚠️  Configuration issues found:")
        for issue in issues:
            print(f"   • {issue}")
        
        if any("required" in issue.lower() for issue in issues):
            print("❌ Critical configuration issues found. Please fix before running tests.")
            sys.exit(1)
    
    return config

async def run_test_suite(suite_name: str, config: TestFrameworkConfig) -> int:
    """Run a specific test suite"""
    print(f"\n🚀 Starting {suite_name} test suite...")
    print(f"Environment: {config.environment.value}")
    print(f"Test Level: {config.test_level.value}")
    
    try:
        if suite_name == "health":
            # Special case for health check
            health_status = await run_health_check(config)
            
            print("\n" + "="*60)
            print("HEALTH CHECK RESULTS")
            print("="*60)
            
            overall_status = health_status.get("overall_status", "unknown")
            status_emoji = {
                "healthy": "✅",
                "warning": "⚠️", 
                "unhealthy": "❌",
                "error": "💥"
            }.get(overall_status, "❓")
            
            print(f"Overall Status: {status_emoji} {overall_status.upper()}")
            
            if "services" in health_status:
                print("\nService Status:")
                for service, status in health_status["services"].items():
                    service_emoji = "✅" if status.get("status") == "passed" else "❌"
                    response_time = status.get("response_time", 0)
                    print(f"  {service_emoji} {service}: {response_time:.3f}s")
            
            if health_status.get("issues"):
                print("\nIssues:")
                for issue in health_status["issues"]:
                    print(f"  ⚠️  {issue}")
            
            print("="*60)
            
            return 0 if overall_status in ["healthy", "warning"] else 1
        
        else:
            # Regular test suite execution
            orchestrator = TestOrchestrator(config)
            
            if suite_name == "all":
                suites_to_run = ["comprehensive"]
            else:
                suites_to_run = [suite_name]
            
            report = await orchestrator.run_test_suites(suites_to_run)
            
            # Print summary
            summary = report.get_summary_stats()
            print_test_summary(summary, suite_name)
            
            # Determine exit code based on success rate
            success_rate = summary.get("success_rate", 0)
            if suite_name == "smoke":
                threshold = 90
            elif suite_name in ["api", "integration"]:
                threshold = 85
            elif suite_name == "ui":
                threshold = 75
            elif suite_name == "workflows":
                threshold = 70
            else:
                threshold = 75
            
            return 0 if success_rate >= threshold else 1
    
    except KeyboardInterrupt:
        print("\n✋ Test execution interrupted by user")
        return 130
    
    except Exception as e:
        print(f"\n❌ Test execution failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

async def run_specific_workflow(workflow_id: str, config: TestFrameworkConfig) -> int:
    """Run a specific workflow scenario"""
    print(f"\n🔄 Running workflow: {workflow_id}")
    
    try:
        from framework.workflow_scenarios import WorkflowTestOrchestrator
        
        orchestrator = WorkflowTestOrchestrator(config)
        results = await orchestrator.run_specific_workflows([workflow_id])
        
        if not results:
            print(f"❌ Workflow '{workflow_id}' not found")
            return 1
        
        result = list(results.values())[0]
        success = result.status == "passed"
        
        duration = getattr(result, 'duration', 0)
        issues_count = len(getattr(result, 'issues_found', []))
        
        status_emoji = "✅" if success else "❌"
        print(f"\n{status_emoji} Workflow Result: {result.status.upper()}")
        print(f"Duration: {duration:.2f}s")
        print(f"Issues Found: {issues_count}")
        
        if hasattr(result, 'issues_found') and result.issues_found:
            print("\nIssues:")
            for issue in result.issues_found:
                severity_emoji = {
                    "critical": "🔴",
                    "high": "🟠", 
                    "medium": "🟡",
                    "low": "🟢"
                }.get(issue.get("severity", "medium"), "⚪")
                print(f"  {severity_emoji} {issue.get('title', 'Unknown')}: {issue.get('description', '')}")
        
        return 0 if success else 1
    
    except Exception as e:
        print(f"❌ Workflow execution failed: {e}")
        return 1

async def start_continuous_testing(config: TestFrameworkConfig, interval: int) -> int:
    """Start continuous testing mode"""
    print(f"\n⏰ Starting continuous testing (interval: {interval}s)")
    print("Press Ctrl+C to stop...")
    
    try:
        orchestrator = TestOrchestrator(config)
        await orchestrator.start_continuous_testing(interval)
        return 0
    
    except KeyboardInterrupt:
        print("\n✋ Continuous testing stopped by user")
        return 0
    
    except Exception as e:
        print(f"❌ Continuous testing failed: {e}")
        return 1

def print_test_summary(summary: dict, suite_name: str):
    """Print formatted test summary"""
    print(f"\n{'='*60}")
    print(f"{suite_name.upper()} TEST RESULTS")
    print(f"{'='*60}")
    
    success_rate = summary.get("success_rate", 0)
    total_tests = summary.get("total_tests", 0)
    passed_tests = summary.get("status_counts", {}).get("passed", 0)
    failed_tests = summary.get("status_counts", {}).get("failed", 0)
    
    # Overall status
    status_emoji = "✅" if success_rate >= 75 else "⚠️" if success_rate >= 50 else "❌"
    print(f"Result: {status_emoji} {success_rate:.1f}% Success Rate")
    print(f"Tests: {passed_tests} passed, {failed_tests} failed, {total_tests} total")
    print(f"Duration: {summary.get('total_duration', 0):.2f}s")
    
    # Issues breakdown
    severity_counts = summary.get('severity_counts', {})
    if any(count > 0 for count in severity_counts.values()):
        print(f"\nIssues by Severity:")
        for severity, count in severity_counts.items():
            if count > 0:
                severity_emoji = {
                    "critical": "🔴",
                    "high": "🟠",
                    "medium": "🟡", 
                    "low": "🟢"
                }.get(severity, "⚪")
                print(f"  {severity_emoji} {severity.title()}: {count}")
    
    print(f"{'='*60}")

def list_available_options():
    """List available test suites and workflows"""
    print(f"\n{'='*60}")
    print("AVAILABLE TEST SUITES")
    print(f"{'='*60}")
    
    suites = {
        "health": "Quick system health check",
        "smoke": "Fast smoke tests for basic functionality",
        "api": "API and service communication tests", 
        "ui": "User interface automation tests",
        "integration": "Integration tests across services",
        "workflows": "End-to-end user workflow scenarios",
        "comprehensive": "Complete test suite (all components)",
        "performance": "Performance and stress testing"
    }
    
    for suite_id, description in suites.items():
        print(f"  🧪 {suite_id:<15} - {description}")
    
    print(f"\n{'='*60}")
    print("AVAILABLE WORKFLOWS")
    print(f"{'='*60}")
    
    workflows = WorkflowScenarios.get_all_workflows()
    for workflow in workflows:
        print(f"  🔄 {workflow.workflow_id:<20} - {workflow.description}")
        print(f"     Steps: {len(workflow.steps)}, Tags: {', '.join(workflow.tags[:3])}")
    
    print(f"{'='*60}")

def create_parser():
    """Create command line argument parser"""
    parser = argparse.ArgumentParser(
        description="PyAirtable Integration Testing Framework",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --suite health                    # Quick health check
  %(prog)s --suite smoke --verbose           # Smoke tests with verbose output
  %(prog)s --suite comprehensive --config config.json
  %(prog)s --workflow new_user_onboarding   # Run specific workflow
  %(prog)s --continuous --interval 600      # Continuous testing every 10 minutes
  %(prog)s --list                          # List available options
        """
    )
    
    # Main execution options
    parser.add_argument(
        "--suite", "-s",
        choices=["health", "smoke", "api", "ui", "integration", "workflows", "comprehensive", "performance", "all"],
        help="Test suite to run"
    )
    
    parser.add_argument(
        "--workflow", "-w", 
        help="Specific workflow to run (use --list to see available workflows)"
    )
    
    parser.add_argument(
        "--continuous", "-c",
        action="store_true",
        help="Start continuous testing mode"
    )
    
    parser.add_argument(
        "--interval",
        type=int,
        default=300,
        help="Interval for continuous testing in seconds (default: 300)"
    )
    
    # Configuration options
    parser.add_argument(
        "--config",
        help="Path to configuration file"
    )
    
    parser.add_argument(
        "--environment", "-e",
        choices=["local", "minikube", "docker-compose", "kubernetes"],
        help="Target environment for testing"
    )
    
    parser.add_argument(
        "--test-level",
        choices=["unit", "integration", "e2e", "performance", "security"],
        help="Test level to execute"
    )
    
    # Browser options
    parser.add_argument(
        "--headless",
        type=lambda x: x.lower() in ['true', '1', 'yes'],
        default=True,
        help="Run browser tests in headless mode (default: true)"
    )
    
    parser.add_argument(
        "--browser",
        choices=["chromium", "firefox", "webkit"],
        default="chromium",
        help="Browser to use for UI tests"
    )
    
    # Output and logging options
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output"
    )
    
    parser.add_argument(
        "--log-file",
        help="Write logs to file"
    )
    
    parser.add_argument(
        "--output-dir",
        default="test-results",
        help="Output directory for test results and reports"
    )
    
    # Information options
    parser.add_argument(
        "--list", "-l",
        action="store_true",
        help="List available test suites and workflows"
    )
    
    parser.add_argument(
        "--info",
        action="store_true", 
        help="Show framework information"
    )
    
    parser.add_argument(
        "--version",
        action="version",
        version=f"PyAirtable Testing Framework v{FRAMEWORK_INFO['version']}"
    )
    
    return parser

async def main():
    """Main entry point"""
    parser = create_parser()
    args = parser.parse_args()
    
    # Handle information requests
    if args.info:
        print_framework_info()
        return 0
    
    if args.list:
        list_available_options()
        return 0
    
    # Validate required arguments
    if not args.suite and not args.workflow and not args.continuous:
        print("❌ Error: Must specify --suite, --workflow, or --continuous")
        print("Use --list to see available options or --help for usage")
        return 1
    
    # Setup logging
    setup_logging(args.verbose, args.log_file)
    
    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Load configuration
    config_overrides = {
        "browser": {
            "headless": args.headless,
            "browser_type": args.browser
        }
    }
    
    config = load_configuration(
        args.config,
        args.environment, 
        args.test_level,
        **config_overrides
    )
    
    # Execute requested operation
    try:
        if args.continuous:
            return await start_continuous_testing(config, args.interval)
        elif args.workflow:
            return await run_specific_workflow(args.workflow, config)
        elif args.suite:
            return await run_test_suite(args.suite, config)
        else:
            print("❌ No valid operation specified")
            return 1
    
    except Exception as e:
        print(f"❌ Execution failed: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1

if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)