#!/usr/bin/env python3
"""
Comprehensive E2E Test Runner for PyAirtable Application

This script runs end-to-end tests for the PyAirtable application,
testing real user scenarios through the API Gateway with Gemini LLM
integration and Airtable data access.

Usage:
    python run_comprehensive_e2e_tests.py [--config-file config.json] [--verbose]
"""

import asyncio
import argparse
import json
import sys
import os
from pathlib import Path
from datetime import datetime

# Add the tests directory to the Python path
sys.path.insert(0, str(Path(__file__).parent / "tests"))

from tests.e2e.test_pyairtable_comprehensive_e2e import PyAirtableE2ETestSuite, TestConfig


class E2ETestRunner:
    """Test runner for PyAirtable E2E tests"""
    
    def __init__(self, config_file: str = None, verbose: bool = False):
        self.verbose = verbose
        self.config = self.load_config(config_file)
        
    def load_config(self, config_file: str = None) -> TestConfig:
        """Load test configuration from file or use defaults"""
        if config_file and os.path.exists(config_file):
            with open(config_file, 'r') as f:
                config_data = json.load(f)
            return TestConfig(**config_data)
        else:
            # Use default configuration
            return TestConfig()
    
    def print_banner(self):
        """Print test banner"""
        print("\n" + "="*80)
        print("PYAIRTABLE COMPREHENSIVE END-TO-END TEST SUITE")
        print("="*80)
        print(f"Timestamp: {datetime.now().isoformat()}")
        print(f"API Gateway: {self.config.api_gateway_url}")
        print(f"LLM Orchestrator: {self.config.llm_orchestrator_url}")
        print(f"MCP Server: {self.config.mcp_server_url}")
        print(f"Airtable Gateway: {self.config.airtable_gateway_url}")
        print(f"Airtable Base: {self.config.airtable_base}")
        print("="*80)
    
    def print_test_scenario(self, scenario_num: int, description: str):
        """Print test scenario header"""
        print(f"\n📋 TEST SCENARIO {scenario_num}: {description}")
        print("-" * 60)
    
    async def run_tests(self) -> dict:
        """Run all E2E tests and return results"""
        self.print_banner()
        
        async with PyAirtableE2ETestSuite(self.config) as suite:
            if self.verbose:
                print("\n🔍 Starting comprehensive test suite...")
            
            result = await suite.run_comprehensive_test_suite()
            
            return result
    
    def print_results(self, result: dict):
        """Print test results in a formatted way"""
        print("\n" + "="*80)
        print("TEST RESULTS SUMMARY")
        print("="*80)
        
        # Overall status
        status = result.get('status', 'unknown')
        status_emoji = "✅" if status == "passed" else "❌" if status == "failed" else "⚠️"
        print(f"Overall Status: {status_emoji} {status.upper()}")
        
        # Test statistics
        total_tests = result.get('total_tests', 0)
        passed_tests = result.get('passed_tests', 0)
        failed_tests = result.get('failed_tests', 0)
        duration = result.get('duration', 0)
        
        print(f"Total Tests: {total_tests}")
        print(f"Passed: {passed_tests}")
        print(f"Failed: {failed_tests}")
        print(f"Duration: {duration:.2f} seconds")
        
        # Service health status
        health_status = result.get('health_status', {})
        if health_status:
            print(f"\n🏥 SERVICE HEALTH STATUS:")
            for service, is_healthy in health_status.items():
                health_emoji = "✅" if is_healthy else "❌"
                print(f"  {health_emoji} {service}")
        
        # Detailed test results
        test_results = result.get('test_results', {})
        if test_results:
            print(f"\n📊 DETAILED TEST RESULTS:")
            
            scenario_mapping = {
                "connectivity": "Service Connectivity Check",
                "gemini_integration": "Gemini LLM Integration Test",
                "scenario_1": "Facebook Posts Analysis & Recommendations",
                "scenario_2": "Metadata Table Creation",
                "scenario_3": "Working Hours Calculation",
                "scenario_4": "Projects Status & Expenses Listing"
            }
            
            for test_key, test_result in test_results.items():
                if isinstance(test_result, dict) and 'status' in test_result:
                    status = test_result['status']
                    test_name = scenario_mapping.get(test_key, test_key.replace('_', ' ').title())
                    status_emoji = "✅" if status == "passed" else "❌" if status == "failed" else "⚠️"
                    
                    print(f"  {status_emoji} {test_name}")
                    
                    if self.verbose and 'response_length' in test_result:
                        print(f"      Response Length: {test_result['response_length']} chars")
                    
                    # Show additional details for failed tests
                    if status == "failed" and self.verbose:
                        for key, value in test_result.items():
                            if key not in ['status', 'scenario', 'test']:
                                print(f"      {key}: {value}")
        
        # Session information
        session_id = result.get('session_id')
        if session_id:
            print(f"\n🔗 Session ID: {session_id}")
        
        print("="*80)
    
    def save_results(self, result: dict, output_file: str = None):
        """Save test results to file"""
        if not output_file:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_file = f"tests/reports/e2e_comprehensive_results_{timestamp}.json"
        
        # Ensure reports directory exists
        os.makedirs(os.path.dirname(output_file), exist_ok=True)
        
        # Add metadata to results
        result['metadata'] = {
            'timestamp': datetime.now().isoformat(),
            'config': {
                'api_gateway_url': self.config.api_gateway_url,
                'llm_orchestrator_url': self.config.llm_orchestrator_url,
                'mcp_server_url': self.config.mcp_server_url,
                'airtable_gateway_url': self.config.airtable_gateway_url,
                'airtable_base': self.config.airtable_base,
                'timeout': self.config.timeout,
                'retry_attempts': self.config.retry_attempts
            }
        }
        
        with open(output_file, 'w') as f:
            json.dump(result, f, indent=2)
        
        print(f"\n💾 Results saved to: {output_file}")
        return output_file


async def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Run PyAirtable Comprehensive E2E Tests")
    parser.add_argument("--config-file", type=str, help="Path to configuration file")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose output")
    parser.add_argument("--output", "-o", type=str, help="Output file for results")
    
    args = parser.parse_args()
    
    # Create test runner
    runner = E2ETestRunner(config_file=args.config_file, verbose=args.verbose)
    
    try:
        # Run tests
        result = await runner.run_tests()
        
        # Print results
        runner.print_results(result)
        
        # Save results
        output_file = runner.save_results(result, args.output)
        
        # Exit with appropriate code
        if result.get('status') == 'passed':
            print("\n🎉 All tests passed successfully!")
            sys.exit(0)
        else:
            print("\n💥 Some tests failed. Check the results above.")
            sys.exit(1)
            
    except KeyboardInterrupt:
        print("\n\n⚠️ Tests interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n❌ Test runner failed with error: {str(e)}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())