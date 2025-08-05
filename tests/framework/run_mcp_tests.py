#!/usr/bin/env python3
"""
MCP Tools Test Runner
=====================

Comprehensive test runner for MCP (Model Context Protocol) tools testing through
the pyairtable frontend UI. This script provides a convenient command-line interface
for running all test scenarios with various configuration options.

Usage:
    python run_mcp_tests.py --help
    python run_mcp_tests.py --scenario all --mocking --parallel
    python run_mcp_tests.py --scenario create-table --no-mocking --verbose
    python run_mcp_tests.py --integration --quick
    python run_mcp_tests.py --health-check

Features:
- Run individual test scenarios or complete test suites
- Enable/disable API mocking for different testing approaches
- Parallel or sequential execution options
- Comprehensive reporting with HTML and JSON outputs
- Health checks and system validation
- Debug mode with detailed logging
- Integration with existing test framework
"""

import asyncio
import argparse
import json
import logging
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

# Add the framework to Python path
sys.path.insert(0, str(Path(__file__).parent))

from synthetic_agents import (
    MCPTestOrchestrator, 
    run_create_metadata_table_test,
    run_populate_metadata_test,
    run_update_metadata_test,
    run_add_column_test,
    run_llm_analysis_test,
    run_all_mcp_tests
)
from mcp_integration_tests import (
    MCPIntegrationTestSuite,
    run_quick_integration_test,
    run_comprehensive_integration_test,
    run_real_api_integration_test
)
from test_config import TestFrameworkConfig, TestEnvironment, TestLevel
from test_orchestrator import TestOrchestrator, run_health_check

# Configure logging
def setup_logging(verbose: bool = False, debug: bool = False):
    """Setup logging configuration"""
    level = logging.DEBUG if debug else (logging.INFO if verbose else logging.WARNING)
    
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(f'mcp_test_run_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log')
        ]
    )

logger = logging.getLogger(__name__)

class MCPTestRunner:
    """Main test runner for MCP tools testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or TestFrameworkConfig()
        self.start_time = None
        self.results = {}
        
    async def run_scenario(self, scenario: str, use_mocking: bool = True, 
                          verbose: bool = False) -> Dict[str, Any]:
        """Run a specific test scenario"""
        self.start_time = time.time()
        logger.info(f"Running MCP test scenario: {scenario}")
        logger.info(f"Mocking enabled: {use_mocking}")
        
        try:
            if scenario == "create-table":
                result = await run_create_metadata_table_test(self.config)
                return self._format_single_result(result, scenario)
            
            elif scenario == "populate":
                result = await run_populate_metadata_test(self.config)
                return self._format_single_result(result, scenario)
            
            elif scenario == "update":
                result = await run_update_metadata_test(self.config)
                return self._format_single_result(result, scenario)
            
            elif scenario == "add-column":
                result = await run_add_column_test(self.config)
                return self._format_single_result(result, scenario)
            
            elif scenario == "llm-analysis":
                result = await run_llm_analysis_test(self.config)
                return self._format_single_result(result, scenario)
            
            elif scenario == "all":
                report = await run_all_mcp_tests(self.config, parallel=True)
                return self._format_report_result(report, "all_scenarios")
            
            else:
                raise ValueError(f"Unknown scenario: {scenario}")
        
        except Exception as e:
            logger.error(f"Scenario {scenario} failed: {e}")
            return {
                "scenario": scenario,
                "status": "failed",
                "error": str(e),
                "duration": time.time() - self.start_time if self.start_time else 0
            }
    
    async def run_integration_tests(self, test_type: str = "quick", 
                                   parallel: bool = True, use_mocking: bool = True) -> Dict[str, Any]:
        """Run integration tests"""
        self.start_time = time.time()
        logger.info(f"Running MCP integration tests: {test_type}")
        
        try:
            if test_type == "quick":
                report = await run_quick_integration_test(use_mocking=use_mocking)
            elif test_type == "comprehensive":
                report = await run_comprehensive_integration_test(parallel=parallel)
            elif test_type == "real-api":
                report = await run_real_api_integration_test()
            else:
                # Custom integration test
                suite = MCPIntegrationTestSuite(self.config)
                report = await suite.run_full_integration_suite(
                    use_mocking=use_mocking, parallel=parallel
                )
            
            return self._format_report_result(report, f"integration_{test_type}")
        
        except Exception as e:
            logger.error(f"Integration test {test_type} failed: {e}")
            return {
                "test_type": f"integration_{test_type}",
                "status": "failed", 
                "error": str(e),
                "duration": time.time() - self.start_time if self.start_time else 0
            }
    
    async def run_health_check(self) -> Dict[str, Any]:
        """Run system health check"""
        logger.info("Running system health check")
        
        try:
            health_status = await run_health_check(self.config)
            
            return {
                "test_type": "health_check",
                "status": "completed",
                "health_status": health_status,
                "timestamp": datetime.now().isoformat()
            }
        
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return {
                "test_type": "health_check",
                "status": "failed",
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }
    
    def _format_single_result(self, result, scenario: str) -> Dict[str, Any]:
        """Format single test result"""
        duration = time.time() - self.start_time if self.start_time else 0
        
        return {
            "scenario": scenario,
            "status": result.status,
            "duration": duration,
            "test_name": result.test_name,
            "agent_name": result.agent_name,
            "issues_count": len(result.issues_found),
            "logs_count": len(result.logs),
            "screenshots": [s["path"] for s in result.screenshots],
            "performance_metrics": result.performance_metrics,
            "summary": {
                "passed": result.status == "passed",
                "issues": result.issues_found,
                "key_metrics": result.performance_metrics
            }
        }
    
    def _format_report_result(self, report, test_type: str) -> Dict[str, Any]:
        """Format test report result"""
        duration = time.time() - self.start_time if self.start_time else 0
        summary = report.get_summary_stats()
        
        return {
            "test_type": test_type,
            "status": "completed",
            "duration": duration,
            "summary": summary,
            "total_tests": len(report.test_results),
            "results_by_status": {
                "passed": len([r for r in report.test_results if r.status == "passed"]),
                "failed": len([r for r in report.test_results if r.status == "failed"]),
                "partial": len([r for r in report.test_results if r.status == "partial"])
            },
            "report_files": {
                "html": getattr(report, "html_report_path", None),
                "json": getattr(report, "json_report_path", None)
            },
            "execution_metrics": getattr(report, "execution_metrics", {})
        }
    
    def print_results_summary(self, results: Dict[str, Any], verbose: bool = False):
        """Print formatted results summary"""
        print("\n" + "="*80)
        print("MCP TOOLS TEST RESULTS SUMMARY")
        print("="*80)
        
        test_type = results.get("scenario") or results.get("test_type", "unknown")
        status = results.get("status", "unknown")
        duration = results.get("duration", 0)
        
        print(f"Test Type: {test_type}")
        print(f"Status: {status.upper()}")
        print(f"Duration: {duration:.2f} seconds")
        
        if "summary" in results:
            summary = results["summary"]
            print(f"\nTest Summary:")
            
            if isinstance(summary, dict):
                for key, value in summary.items():
                    if key == "issues" and isinstance(value, list):
                        print(f"  Issues Found: {len(value)}")
                        if verbose and value:
                            for issue in value[:3]:  # Show first 3 issues
                                print(f"    - {issue.get('severity', 'unknown')}: {issue.get('title', 'Unknown issue')}")
                    elif key == "key_metrics" and isinstance(value, dict):
                        print(f"  Key Metrics:")
                        for metric, metric_value in value.items():
                            print(f"    {metric}: {metric_value}")
                    else:
                        print(f"  {key}: {value}")
        
        if "results_by_status" in results:
            status_counts = results["results_by_status"]
            print(f"\nResults Breakdown:")
            for status_name, count in status_counts.items():
                print(f"  {status_name.capitalize()}: {count}")
        
        if "report_files" in results:
            report_files = results["report_files"]
            print(f"\nGenerated Reports:")
            for report_type, file_path in report_files.items():
                if file_path:
                    print(f"  {report_type.upper()}: {file_path}")
        
        if verbose and "execution_metrics" in results:
            metrics = results["execution_metrics"]
            print(f"\nExecution Metrics:")
            print(json.dumps(metrics, indent=2))
        
        print("="*80)

def create_config_from_args(args) -> TestFrameworkConfig:
    """Create test configuration from command line arguments"""
    config = TestFrameworkConfig()
    
    # Environment settings
    if args.environment:
        config.environment = TestEnvironment(args.environment)
    
    if args.test_level:
        config.test_level = TestLevel(args.test_level)
    
    # Browser settings
    if args.headless is not None:
        config.browser.headless = args.headless
    
    if args.browser:
        config.browser.browser_type = args.browser
    
    # Execution settings
    if args.timeout:
        config.timeout = args.timeout
    
    if args.parallel is not None:
        config.parallel_execution = args.parallel
    
    # Screenshots and reporting
    config.save_screenshots = args.screenshots
    config.save_traces = args.traces
    config.generate_html_report = True
    config.generate_json_report = True
    
    return config

async def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="MCP Tools Test Runner - Comprehensive testing for MCP tools through pyairtable frontend",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python run_mcp_tests.py --scenario all --mocking --parallel
  python run_mcp_tests.py --scenario create-table --no-mocking --verbose
  python run_mcp_tests.py --integration quick --parallel
  python run_mcp_tests.py --health-check
  python run_mcp_tests.py --scenario populate --headless --timeout 300
        """
    )
    
    # Test execution options
    parser.add_argument("--scenario", 
                       choices=["create-table", "populate", "update", "add-column", "llm-analysis", "all"],
                       help="Specific test scenario to run")
    
    parser.add_argument("--integration", 
                       choices=["quick", "comprehensive", "real-api"],
                       help="Run integration tests")
    
    parser.add_argument("--health-check", action="store_true",
                       help="Run system health check")
    
    # Configuration options
    parser.add_argument("--mocking", action="store_true", default=True,
                       help="Enable API mocking (default: enabled)")
    parser.add_argument("--no-mocking", action="store_true",
                       help="Disable API mocking")
    
    parser.add_argument("--parallel", action="store_true",
                       help="Enable parallel execution")
    parser.add_argument("--no-parallel", action="store_true",
                       help="Disable parallel execution")
    
    # Environment and browser options
    parser.add_argument("--environment", 
                       choices=["local", "minikube", "docker-compose"],
                       default="local",
                       help="Test environment (default: local)")
    
    parser.add_argument("--test-level",
                       choices=["unit", "integration", "e2e", "performance"],
                       default="integration",
                       help="Test level (default: integration)")
    
    parser.add_argument("--browser",
                       choices=["chromium", "firefox", "webkit"],
                       default="chromium",
                       help="Browser type (default: chromium)")
    
    parser.add_argument("--headless", action="store_true", default=True,
                       help="Run browser in headless mode (default: enabled)")
    parser.add_argument("--no-headless", action="store_true",
                       help="Run browser with UI visible")
    
    # Output and debugging options
    parser.add_argument("--verbose", "-v", action="store_true",
                       help="Enable verbose output")
    parser.add_argument("--debug", action="store_true",
                       help="Enable debug logging")
    
    parser.add_argument("--screenshots", action="store_true", default=True,
                       help="Save screenshots (default: enabled)")
    parser.add_argument("--traces", action="store_true",
                       help="Save browser traces")
    
    # Timing options
    parser.add_argument("--timeout", type=int, default=300,
                       help="Test timeout in seconds (default: 300)")
    
    # Output options
    parser.add_argument("--output", "-o", 
                       help="Output file for results (JSON format)")
    
    args = parser.parse_args()
    
    # Setup logging
    setup_logging(verbose=args.verbose, debug=args.debug)
    
    # Validate arguments
    if not any([args.scenario, args.integration, args.health_check]):
        parser.error("Must specify --scenario, --integration, or --health-check")
    
    # Process boolean arguments
    if args.no_mocking:
        use_mocking = False
    else:
        use_mocking = args.mocking
    
    if args.no_headless:
        headless = False
    else:
        headless = args.headless
    
    if args.no_parallel:
        parallel = False
    else:
        parallel = args.parallel
    
    # Create configuration
    config = create_config_from_args(args)
    config.browser.headless = headless
    
    # Create test runner
    runner = MCPTestRunner(config)
    
    try:
        results = None
        
        if args.health_check:
            logger.info("Running health check...")
            results = await runner.run_health_check()
        
        elif args.scenario:
            logger.info(f"Running scenario: {args.scenario}")
            results = await runner.run_scenario(
                args.scenario, 
                use_mocking=use_mocking,
                verbose=args.verbose
            )
        
        elif args.integration:
            logger.info(f"Running integration tests: {args.integration}")
            results = await runner.run_integration_tests(
                test_type=args.integration,
                parallel=parallel,
                use_mocking=use_mocking
            )
        
        # Print results
        if results:
            runner.print_results_summary(results, verbose=args.verbose)
            
            # Save to output file if specified
            if args.output:
                output_path = Path(args.output)
                output_path.parent.mkdir(parents=True, exist_ok=True)
                
                with open(output_path, 'w') as f:
                    json.dump(results, f, indent=2, default=str)
                
                logger.info(f"Results saved to: {output_path}")
            
            # Exit with appropriate code
            status = results.get("status", "unknown")
            if status == "failed":
                sys.exit(1)
            elif status in ["completed", "passed"]:
                sys.exit(0)
            else:
                sys.exit(2)  # Partial success or unknown
        
        else:
            logger.error("No results generated")
            sys.exit(1)
    
    except KeyboardInterrupt:
        logger.info("Test execution interrupted by user")
        sys.exit(130)
    
    except Exception as e:
        logger.error(f"Test execution failed: {e}")
        if args.debug:
            import traceback
            traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())