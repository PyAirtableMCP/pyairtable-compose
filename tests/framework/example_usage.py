#!/usr/bin/env python3
"""
MCP Tools Testing Framework - Usage Examples
============================================

This script demonstrates various ways to use the MCP testing framework
with different configurations and scenarios.
"""

import asyncio
import logging
from pathlib import Path

# Import the MCP testing framework components
from synthetic_agents import (
    MCPTestOrchestrator,
    MCPMetadataTableAgent,
    MCPMetadataPopulationAgent,
    run_all_mcp_tests
)
from mcp_integration_tests import MCPIntegrationTestSuite
from test_config import TestFrameworkConfig, TestEnvironment
from mcp_mocking import MCPMockContextManager

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def example_1_single_scenario():
    """Example 1: Run a single test scenario with custom configuration"""
    print("\n" + "="*60)
    print("EXAMPLE 1: Single Scenario - Create Metadata Table")
    print("="*60)
    
    # Create custom configuration
    config = TestFrameworkConfig()
    config.browser.headless = True  # Run in headless mode
    config.save_screenshots = True
    config.timeout = 120  # 2 minute timeout
    
    # Create and run the metadata table agent
    agent = MCPMetadataTableAgent(config)
    
    async with agent:
        result = await agent.test_create_metadata_table()
        
        print(f"Test Result: {result.status}")
        print(f"Duration: {result.performance_metrics.get('duration', 'N/A')} seconds")
        print(f"Issues Found: {len(result.issues_found)}")
        print(f"Screenshots: {len(result.screenshots)}")
        
        if result.issues_found:
            print("\nIssues:")
            for issue in result.issues_found:
                print(f"  - {issue['severity']}: {issue['title']}")

async def example_2_orchestrated_tests():
    """Example 2: Run orchestrated tests with all scenarios"""
    print("\n" + "="*60)
    print("EXAMPLE 2: Orchestrated Tests - All Scenarios")
    print("="*60)
    
    # Create orchestrator
    orchestrator = MCPTestOrchestrator()
    
    # Run all tests in parallel
    report = await orchestrator.run_comprehensive_mcp_tests(
        parallel=True,
        agents_subset=None  # Run all agents
    )
    
    # Print summary
    summary = report.get_summary_stats()
    print(f"Total Tests: {summary.get('total_tests', 0)}")
    print(f"Passed: {summary.get('passed_tests', 0)}")
    print(f"Failed: {summary.get('failed_tests', 0)}")
    print(f"Execution Time: {summary.get('total_duration', 0):.2f} seconds")
    
    if hasattr(report, 'html_report_path'):
        print(f"HTML Report: {report.html_report_path}")

async def example_3_with_mocking():
    """Example 3: Run tests with API mocking for faster execution"""
    print("\n" + "="*60)
    print("EXAMPLE 3: Tests with API Mocking")
    print("="*60)
    
    config = TestFrameworkConfig()
    config.browser.headless = True
    
    # Create agent
    agent = MCPMetadataPopulationAgent(config)
    
    async with agent:
        # Set up mocking context
        async with MCPMockContextManager(
            agent.page,
            enable_airtable=True,
            enable_llm=True,
            enable_frontend=False
        ) as mock_framework:
            
            print("Mocking enabled - this should run much faster!")
            
            # Run the test with mocked APIs
            result = await agent.test_populate_metadata_for_tables()
            
            # Get mock metrics
            from mcp_mocking import MockValidator
            mock_metrics = MockValidator.extract_mock_metrics(mock_framework)
            
            print(f"Test Result: {result.status}")
            print(f"Requests Intercepted: {mock_metrics['total_requests']}")
            print(f"Mock Effectiveness: {mock_metrics['mock_effectiveness']:.2%}")

async def example_4_integration_suite():
    """Example 4: Run comprehensive integration test suite"""
    print("\n" + "="*60)
    print("EXAMPLE 4: Integration Test Suite")
    print("="*60)
    
    # Create integration test suite
    suite = MCPIntegrationTestSuite()
    
    # Run comprehensive integration tests
    report = await suite.run_full_integration_suite(
        use_mocking=True,
        parallel=False  # Sequential for clearer output
    )
    
    # Print detailed results
    print(f"Integration Tests Completed!")
    print(f"Total Tests: {len(report.test_results)}")
    
    # Group results by status
    results_by_status = {}
    for result in report.test_results:
        status = result.status
        if status not in results_by_status:
            results_by_status[status] = 0
        results_by_status[status] += 1
    
    for status, count in results_by_status.items():
        print(f"{status.title()}: {count}")
    
    # Show execution metrics if available
    if hasattr(report, 'execution_metrics'):
        metrics = report.execution_metrics
        suite_summary = metrics.get('suite_summary', {})
        print(f"Total Duration: {suite_summary.get('total_duration', 0):.2f}s")
        print(f"Scenarios Executed: {suite_summary.get('scenarios_executed', 0)}")

async def example_5_custom_workflow():
    """Example 5: Create a custom testing workflow"""
    print("\n" + "="*60)
    print("EXAMPLE 5: Custom Testing Workflow")
    print("="*60)
    
    config = TestFrameworkConfig()
    config.browser.headless = False  # Show browser for demo
    config.browser.slow_mo = 1000   # Slow down for visibility
    config.save_screenshots = True
    
    results = []
    
    # Step 1: Create metadata table
    print("Step 1: Creating metadata table...")
    table_agent = MCPMetadataTableAgent(config)
    async with table_agent:
        table_result = await table_agent.test_create_metadata_table()
        results.append(("Create Table", table_result.status))
        print(f"  Result: {table_result.status}")
    
    # Step 2: Add improvements column (only if table creation succeeded)
    if table_result.status == "passed":
        print("Step 2: Adding improvements column...")
        column_agent = MCPColumnAdditionAgent(config)
        async with column_agent:
            column_result = await column_agent.test_add_improvements_column()
            results.append(("Add Column", column_result.status))
            print(f"  Result: {column_result.status}")
    
        # Step 3: Populate with sample data (only if column addition succeeded)
        if column_result.status == "passed":
            print("Step 3: Populating metadata...")
            populate_agent = MCPMetadataPopulationAgent(config)
            async with populate_agent:
                populate_result = await populate_agent.test_populate_metadata_for_tables()
                results.append(("Populate Data", populate_result.status))
                print(f"  Result: {populate_result.status}")
    
    # Summary
    print("\nCustom Workflow Summary:")
    for step_name, status in results:
        print(f"  {step_name}: {status}")

async def example_6_error_handling():
    """Example 6: Demonstrate error handling and debugging"""
    print("\n" + "="*60)
    print("EXAMPLE 6: Error Handling and Debugging")
    print("="*60)
    
    config = TestFrameworkConfig()
    config.browser.headless = True
    config.save_screenshots = True
    config.timeout = 30  # Short timeout to force some failures
    
    # Run a scenario that might fail due to timeout
    try:
        agent = MCPLLMAnalysisAgent(config)
        async with agent:
            result = await agent.test_llm_analysis_integration()
            
            print(f"Test Status: {result.status}")
            
            # Show any issues that were detected
            if result.issues_found:
                print(f"Issues Detected: {len(result.issues_found)}")
                for issue in result.issues_found[:3]:  # Show first 3
                    print(f"  - {issue['severity']}: {issue['title']}")
            
            # Show debugging information
            print(f"Logs Generated: {len(result.logs)}")
            print(f"Screenshots Captured: {len(result.screenshots)}")
            
            # Show performance metrics
            if result.performance_metrics:
                print("Performance Metrics:")
                for metric, value in result.performance_metrics.items():
                    print(f"  {metric}: {value}")
    
    except Exception as e:
        print(f"Exception caught: {e}")
        print("This demonstrates the framework's error handling capabilities")

async def main():
    """Run all examples"""
    print("MCP Tools Testing Framework - Usage Examples")
    print("=" * 80)
    print("This script demonstrates various ways to use the testing framework.")
    print("Each example shows different features and configuration options.")
    print("=" * 80)
    
    # List of examples to run
    examples = [
        ("Single Scenario Test", example_1_single_scenario),
        ("Orchestrated Tests", example_2_orchestrated_tests),
        ("Tests with Mocking", example_3_with_mocking),
        ("Integration Suite", example_4_integration_suite),
        ("Custom Workflow", example_5_custom_workflow),
        ("Error Handling", example_6_error_handling)
    ]
    
    print(f"\nAvailable examples:")
    for i, (name, _) in enumerate(examples, 1):
        print(f"  {i}. {name}")
    
    # Ask user which example to run
    try:
        choice = input(f"\nEnter example number (1-{len(examples)}) or 'all' for all examples: ").strip()
        
        if choice.lower() == 'all':
            # Run all examples
            for name, example_func in examples:
                print(f"\nRunning: {name}")
                try:
                    await example_func()
                except Exception as e:
                    print(f"Example failed: {e}")
                    logger.exception("Example execution failed")
        else:
            # Run specific example
            try:
                example_num = int(choice)
                if 1 <= example_num <= len(examples):
                    name, example_func = examples[example_num - 1]
                    print(f"\nRunning: {name}")
                    await example_func()
                else:
                    print("Invalid example number!")
            except ValueError:
                print("Please enter a valid number or 'all'")
    
    except KeyboardInterrupt:
        print("\nExecution interrupted by user")
    except Exception as e:
        print(f"Error: {e}")
        logger.exception("Main execution failed")
    
    print(f"\nExamples completed! Check the test-results directory for generated artifacts.")

if __name__ == "__main__":
    asyncio.run(main())