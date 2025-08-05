#!/usr/bin/env python3
"""
PyAirtable Integration Testing Framework CLI
===========================================

Command-line interface for the comprehensive PyAirtable integration testing framework.
Provides easy access to all testing capabilities including UI automation, API testing,
external API integration, and user workflow scenarios.
"""

import asyncio
import argparse
import json
import logging
import os
import sys
from pathlib import Path
from typing import Dict, Any

# Add the framework to the Python path
sys.path.insert(0, str(Path(__file__).parent))

from test_config import TestFrameworkConfig, TestEnvironment, TestLevel
from test_orchestrator import TestOrchestrator, run_health_check
from ui_agents import UITestOrchestrator
from api_testing import APITestOrchestrator
from external_api_testing import ExternalAPITestOrchestrator
from workflow_scenarios import WorkflowTestOrchestrator, WorkflowScenarios

# Configure logging
def setup_logging(verbose: bool = False, log_file: str = None):
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
    
    # Suppress some noisy loggers
    logging.getLogger('httpx').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)
    logging.getLogger('asyncio').setLevel(logging.WARNING)

def load_config(config_file: str = None, environment: str = None) -> TestFrameworkConfig:
    """Load test configuration"""
    if config_file and os.path.exists(config_file):
        config = TestFrameworkConfig.from_file(config_file)
    else:
        config = TestFrameworkConfig.from_env()
    
    # Override environment if specified
    if environment:
        try:
            config.environment = TestEnvironment(environment)
        except ValueError:
            print(f"Warning: Invalid environment '{environment}', using default")
    
    return config

async def cmd_health(args):
    """Run system health check"""
    print("🏥 Running system health check...")
    config = load_config(args.config, args.environment)
    
    health_status = await run_health_check(config)
    
    print(f"\n{'='*60}")
    print("SYSTEM HEALTH CHECK RESULTS")
    print(f"{'='*60}")
    
    # Overall status
    status_emoji = "✅" if health_status["overall_status"] == "healthy" else "⚠️" if health_status["overall_status"] == "warning" else "❌"
    print(f"Overall Status: {status_emoji} {health_status['overall_status'].upper()}")
    
    # Configuration
    config_emoji = "✅" if health_status["config_valid"] else "❌"
    print(f"Configuration: {config_emoji} {'Valid' if health_status['config_valid'] else 'Invalid'}")
    
    # Services
    if "services" in health_status:
        print(f"\n🔧 SERVICE STATUS:")
        for service_name, service_status in health_status["services"].items():
            if service_status["status"] == "passed":
                status_emoji = "✅"
                response_time = service_status.get("response_time", 0)
                print(f"  {status_emoji} {service_name}: Healthy ({response_time:.3f}s)")
            else:
                status_emoji = "❌"
                error = service_status.get("error", "Unknown error")
                print(f"  {status_emoji} {service_name}: {error}")
    
    # Issues
    if health_status.get("issues"):
        print(f"\n⚠️  ISSUES FOUND:")
        for issue in health_status["issues"]:
            print(f"  • {issue}")
    
    print(f"{'='*60}")
    
    # Return appropriate exit code
    return 0 if health_status["overall_status"] in ["healthy", "warning"] else 1

async def cmd_smoke(args):
    """Run smoke tests"""
    print("💨 Running smoke tests...")
    config = load_config(args.config, args.environment)
    
    orchestrator = TestOrchestrator(config)
    report = await orchestrator.run_test_suites(["smoke"])
    
    summary = report.get_summary_stats()
    print_test_summary(summary, "Smoke Tests")
    
    return 0 if summary["success_rate"] >= 90 else 1

async def cmd_integration(args):
    """Run integration tests"""
    print("🔗 Running integration tests...")
    config = load_config(args.config, args.environment)
    
    orchestrator = TestOrchestrator(config)
    report = await orchestrator.run_test_suites(["integration"])
    
    summary = report.get_summary_stats()
    print_test_summary(summary, "Integration Tests")
    
    return 0 if summary["success_rate"] >= 80 else 1

async def cmd_ui(args):
    """Run UI tests"""
    print("🖥️  Running UI tests...")
    config = load_config(args.config, args.environment)
    
    orchestrator = TestOrchestrator(config)
    report = await orchestrator.run_test_suites(["ui"])
    
    summary = report.get_summary_stats()
    print_test_summary(summary, "UI Tests")
    
    return 0 if summary["success_rate"] >= 75 else 1

async def cmd_api(args):
    """Run API tests"""
    print("🌐 Running API tests...")
    config = load_config(args.config, args.environment)
    
    orchestrator = TestOrchestrator(config)
    report = await orchestrator.run_test_suites(["api"])
    
    summary = report.get_summary_stats()
    print_test_summary(summary, "API Tests")
    
    return 0 if summary["success_rate"] >= 85 else 1

async def cmd_workflows(args):
    """Run workflow tests"""
    print("🔄 Running workflow tests...")
    config = load_config(args.config, args.environment)
    
    if args.workflow:
        # Run specific workflow
        orchestrator = WorkflowTestOrchestrator(config)
        results = await orchestrator.run_specific_workflows([args.workflow])
        
        if results:
            result = list(results.values())[0]
            success = result.status == "passed"
            print(f"\n✅ Workflow '{args.workflow}' {'PASSED' if success else 'FAILED'}")
            return 0 if success else 1
        else:
            print(f"❌ Workflow '{args.workflow}' not found")
            return 1
    else:
        # Run all workflows
        orchestrator = TestOrchestrator(config)
        report = await orchestrator.run_test_suites(["workflows"])
        
        summary = report.get_summary_stats()
        print_test_summary(summary, "Workflow Tests")
        
        return 0 if summary["success_rate"] >= 70 else 1

async def cmd_comprehensive(args):
    """Run comprehensive test suite"""
    print("🚀 Running comprehensive test suite...")
    config = load_config(args.config, args.environment)
    
    orchestrator = TestOrchestrator(config)
    report = await orchestrator.run_test_suites(["comprehensive"])
    
    summary = report.get_summary_stats()
    print_test_summary(summary, "Comprehensive Test Suite")
    
    return 0 if summary["success_rate"] >= 75 else 1

async def cmd_continuous(args):
    """Start continuous testing"""
    print(f"⏰ Starting continuous testing (interval: {args.interval}s)...")
    config = load_config(args.config, args.environment)
    
    orchestrator = TestOrchestrator(config)
    
    try:
        await orchestrator.start_continuous_testing(args.interval)
    except KeyboardInterrupt:
        print("\n✋ Continuous testing stopped by user")
        return 0

async def cmd_list_workflows(args):
    """List available workflows"""
    workflows = WorkflowScenarios.get_all_workflows()
    
    print(f"\n{'='*60}")
    print("AVAILABLE WORKFLOW SCENARIOS")
    print(f"{'='*60}")
    
    for workflow in workflows:
        print(f"\n📋 {workflow.name}")
        print(f"   ID: {workflow.workflow_id}")
        print(f"   Description: {workflow.description}")
        print(f"   Steps: {len(workflow.steps)}")
        print(f"   Tags: {', '.join(workflow.tags)}")
        print(f"   Estimated Duration: {workflow.estimated_duration}s")
    
    print(f"{'='*60}")
    return 0

async def cmd_list_suites(args):
    """List available test suites"""
    config = load_config(args.config, args.environment)
    orchestrator = TestOrchestrator(config)
    suites = orchestrator.get_available_suites()
    
    print(f"\n{'='*60}")
    print("AVAILABLE TEST SUITES")
    print(f"{'='*60}")
    
    for suite_id, suite_info in suites.items():
        print(f"\n🧪 {suite_info['name']}")
        print(f"   ID: {suite_id}")
        print(f"   Description: {suite_info['description']}")
        print(f"   Components: {', '.join(suite_info['components'])}")
        print(f"   Tags: {', '.join(suite_info['tags'])}")
        print(f"   Parallel: {'Yes' if suite_info['parallel'] else 'No'}")
    
    print(f"{'='*60}")
    return 0

async def cmd_history(args):
    """Show execution history"""
    config = load_config(args.config, args.environment)
    orchestrator = TestOrchestrator(config)
    history = orchestrator.get_execution_history()
    
    if not history:
        print("No test execution history found.")
        return 0
    
    print(f"\n{'='*60}")
    print("TEST EXECUTION HISTORY")
    print(f"{'='*60}")
    
    for execution in history[-10:]:  # Show last 10 executions
        print(f"\n🕐 {execution['created_at']}")
        print(f"   ID: {execution['execution_id']}")
        print(f"   Suites: {', '.join([s['name'] for s in execution['suites']])}")
        print(f"   Duration: {execution['estimated_duration']}s (estimated)")
        
        if execution['completed']:
            summary = execution.get('summary', {})
            success_rate = summary.get('success_rate', 0)
            total_tests = summary.get('total_tests', 0)
            status_emoji = "✅" if success_rate >= 75 else "❌"
            print(f"   Result: {status_emoji} {success_rate:.1f}% success ({total_tests} tests)")
            
            if 'report_paths' in execution:
                print(f"   Reports: {execution['report_paths']['html']}")
        else:
            print(f"   Status: ⏳ In Progress or Failed")
    
    print(f"{'='*60}")
    return 0

def print_test_summary(summary: Dict[str, Any], suite_name: str):
    """Print test execution summary"""
    print(f"\n{'='*60}")
    print(f"{suite_name.upper()} RESULTS")
    print(f"{'='*60}")
    
    # Overall status
    success_rate = summary.get("success_rate", 0)
    status_emoji = "✅" if success_rate >= 75 else "⚠️" if success_rate >= 50 else "❌"
    
    print(f"Overall Result: {status_emoji} {success_rate:.1f}% Success Rate")
    print(f"Total Tests: {summary.get('total_tests', 0)}")
    print(f"Passed: {summary.get('status_counts', {}).get('passed', 0)}")
    print(f"Failed: {summary.get('status_counts', {}).get('failed', 0)}")
    print(f"Errors: {summary.get('status_counts', {}).get('error', 0)}")
    print(f"Duration: {summary.get('total_duration', 0):.2f}s")
    
    # Issues breakdown
    severity_counts = summary.get('severity_counts', {})
    if severity_counts:
        print(f"\nIssues Found:")
        for severity, count in severity_counts.items():
            if count > 0:
                severity_emoji = {"critical": "🔴", "high": "🟠", "medium": "🟡", "low": "🟢"}.get(severity, "⚪")
                print(f"  {severity_emoji} {severity.title()}: {count}")
    
    print(f"{'='*60}")

def create_parser():
    """Create the argument parser"""
    parser = argparse.ArgumentParser(
        description="PyAirtable Integration Testing Framework",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s health                    # Run system health check
  %(prog)s smoke                     # Run smoke tests
  %(prog)s integration               # Run integration tests
  %(prog)s ui --no-headless          # Run UI tests with visible browser
  %(prog)s workflows --workflow new_user_onboarding
  %(prog)s comprehensive --config custom-config.json
  %(prog)s continuous --interval 600 # Run continuous testing every 10 minutes
        """
    )
    
    # Global options
    parser.add_argument(
        "--config", "-c",
        help="Path to configuration file"
    )
    parser.add_argument(
        "--environment", "-e",
        choices=["local", "minikube", "docker-compose", "kubernetes"],
        help="Test environment"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging"
    )
    parser.add_argument(
        "--log-file",
        help="Log file path"
    )
    parser.add_argument(
        "--output-dir",
        default="test-results",
        help="Output directory for test results"
    )
    
    # Subcommands
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Health check
    parser_health = subparsers.add_parser("health", help="Run system health check")
    parser_health.set_defaults(func=cmd_health)
    
    # Smoke tests
    parser_smoke = subparsers.add_parser("smoke", help="Run smoke tests")
    parser_smoke.set_defaults(func=cmd_smoke)
    
    # Integration tests
    parser_integration = subparsers.add_parser("integration", help="Run integration tests")
    parser_integration.set_defaults(func=cmd_integration)
    
    # UI tests
    parser_ui = subparsers.add_parser("ui", help="Run UI tests")
    parser_ui.add_argument("--headless", action="store_true", default=True, help="Run in headless mode")
    parser_ui.add_argument("--no-headless", action="store_false", dest="headless", help="Run with visible browser")
    parser_ui.set_defaults(func=cmd_ui)
    
    # API tests
    parser_api = subparsers.add_parser("api", help="Run API tests")
    parser_api.set_defaults(func=cmd_api)
    
    # Workflow tests
    parser_workflows = subparsers.add_parser("workflows", help="Run workflow tests")
    parser_workflows.add_argument("--workflow", help="Run specific workflow by ID")
    parser_workflows.set_defaults(func=cmd_workflows)
    
    # Comprehensive tests
    parser_comprehensive = subparsers.add_parser("comprehensive", help="Run comprehensive test suite")
    parser_comprehensive.set_defaults(func=cmd_comprehensive)
    
    # Continuous testing
    parser_continuous = subparsers.add_parser("continuous", help="Start continuous testing")
    parser_continuous.add_argument("--interval", type=int, default=300, help="Check interval in seconds")
    parser_continuous.set_defaults(func=cmd_continuous)
    
    # List commands
    parser_list_workflows = subparsers.add_parser("list-workflows", help="List available workflows")
    parser_list_workflows.set_defaults(func=cmd_list_workflows)
    
    parser_list_suites = subparsers.add_parser("list-suites", help="List available test suites")
    parser_list_suites.set_defaults(func=cmd_list_suites)
    
    # History
    parser_history = subparsers.add_parser("history", help="Show execution history")
    parser_history.set_defaults(func=cmd_history)
    
    return parser

async def main():
    """Main CLI entry point"""
    parser = create_parser()
    args = parser.parse_args()
    
    # Show help if no command specified
    if not args.command:
        parser.print_help()
        return 1
    
    # Setup logging
    setup_logging(args.verbose, args.log_file)
    
    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)
    
    try:
        # Execute the command
        return await args.func(args)
    
    except KeyboardInterrupt:
        print("\n✋ Operation cancelled by user")
        return 130
    
    except Exception as e:
        print(f"❌ Error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1

if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)