#!/usr/bin/env python3
"""
Integration test runner for PyAirtable Sprint 1 functionality.

This script runs the complete integration test suite and generates reports.
"""

import subprocess
import sys
import os
import time
import argparse
import json
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any


class IntegrationTestRunner:
    """Manages and executes integration tests"""
    
    def __init__(self):
        self.base_dir = Path(__file__).parent
        self.test_dir = self.base_dir / "tests"
        self.results_dir = self.base_dir / "test_results"
        self.timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Ensure results directory exists
        self.results_dir.mkdir(exist_ok=True)
    
    def check_dependencies(self) -> bool:
        """Check if required Python packages are installed"""
        try:
            import pytest
            import httpx
            import asyncio
            return True
        except ImportError as e:
            print(f"❌ Missing required dependency: {e}")
            print("Please install requirements: pip install -r tests/requirements.txt")
            return False
    
    def check_services(self) -> Dict[str, bool]:
        """Check if required services are running"""
        services = {
            "API Gateway": "http://localhost:8000/api/health",
            "Platform Services": "http://localhost:8007/health", 
            "Airtable Gateway": "http://localhost:8002/health",
            "AI Processing": "http://localhost:8001/health",
        }
        
        results = {}
        
        print("🔍 Checking service availability...")
        
        for service_name, health_url in services.items():
            try:
                import httpx
                with httpx.Client(timeout=5.0) as client:
                    response = client.get(health_url)
                    if response.status_code == 200:
                        results[service_name] = True
                        print(f"  ✅ {service_name}: Running")
                    else:
                        results[service_name] = False
                        print(f"  ⚠️  {service_name}: Unhealthy (HTTP {response.status_code})")
            except Exception as e:
                results[service_name] = False
                print(f"  ❌ {service_name}: Not accessible ({str(e)[:50]}...)")
        
        return results
    
    def run_tests(self, test_pattern: str = None, markers: str = None, verbose: bool = True) -> bool:
        """Run integration tests with specified parameters"""
        
        cmd = [
            sys.executable, "-m", "pytest",
            str(self.test_dir),
            "--tb=short",
            "--durations=10",
            f"--html={self.results_dir}/integration_test_report_{self.timestamp}.html",
            "--self-contained-html",
            f"--json-report={self.results_dir}/test_results_{self.timestamp}.json",
            "--json-report-omit=collectors",
        ]
        
        if verbose:
            cmd.extend(["-v", "-s"])
        
        if test_pattern:
            cmd.extend(["-k", test_pattern])
        
        if markers:
            cmd.extend(["-m", markers])
        
        # Add coverage if available
        try:
            import coverage
            cmd.extend([
                "--cov=.",
                f"--cov-report=html:{self.results_dir}/coverage_{self.timestamp}",
                "--cov-report=term-missing"
            ])
        except ImportError:
            pass
        
        print(f"\n🧪 Running integration tests...")
        print(f"Command: {' '.join(cmd)}")
        print("-" * 60)
        
        start_time = time.time()
        result = subprocess.run(cmd, cwd=self.base_dir)
        end_time = time.time()
        
        print("-" * 60)
        print(f"⏱️  Test execution time: {end_time - start_time:.2f} seconds")
        
        return result.returncode == 0
    
    def generate_summary_report(self, test_success: bool, service_status: Dict[str, bool]):
        """Generate a summary report of the test run"""
        
        summary = {
            "timestamp": self.timestamp,
            "test_success": test_success,
            "service_status": service_status,
            "environment": {
                "python_version": sys.version,
                "working_directory": str(self.base_dir),
                "test_directory": str(self.test_dir)
            }
        }
        
        # Save summary as JSON
        summary_file = self.results_dir / f"test_summary_{self.timestamp}.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        # Create human-readable summary
        summary_text = f"""
PyAirtable Integration Test Summary
==================================
Timestamp: {self.timestamp}
Test Result: {'✅ PASSED' if test_success else '❌ FAILED'}

Service Status:
{chr(10).join(f"  {'✅' if status else '❌'} {name}" for name, status in service_status.items())}

Test Reports Generated:
  📊 HTML Report: test_results/integration_test_report_{self.timestamp}.html
  📋 JSON Results: test_results/test_results_{self.timestamp}.json
  📝 Summary: test_results/test_summary_{self.timestamp}.json

Total Services Healthy: {sum(service_status.values())}/{len(service_status)}
Overall Status: {'✅ SUCCESS' if test_success and all(service_status.values()) else '⚠️ PARTIAL SUCCESS' if test_success else '❌ FAILURE'}
"""
        
        summary_text_file = self.results_dir / f"test_summary_{self.timestamp}.txt"
        with open(summary_text_file, 'w') as f:
            f.write(summary_text)
        
        print(summary_text)
        
        return summary_file


def main():
    """Main execution function"""
    parser = argparse.ArgumentParser(description="Run PyAirtable Integration Tests")
    parser.add_argument("--pattern", "-k", help="Test pattern to match")
    parser.add_argument("--markers", "-m", help="Test markers to run (e.g., 'auth', 'not slow')")
    parser.add_argument("--quiet", "-q", action="store_true", help="Run in quiet mode")
    parser.add_argument("--skip-service-check", action="store_true", help="Skip service availability check")
    
    args = parser.parse_args()
    
    runner = IntegrationTestRunner()
    
    print("🚀 PyAirtable Integration Test Suite - Sprint 1")
    print("=" * 60)
    
    # Check dependencies
    if not runner.check_dependencies():
        print("Please install required dependencies and try again.")
        sys.exit(1)
    
    # Check services unless skipped
    service_status = {}
    if not args.skip_service_check:
        service_status = runner.check_services()
        
        # Warn if critical services are down
        critical_services = ["API Gateway"]
        missing_critical = [name for name in critical_services if not service_status.get(name, False)]
        
        if missing_critical:
            print(f"\n⚠️  WARNING: Critical services not available: {', '.join(missing_critical)}")
            print("Some tests may fail or be skipped.")
            
            response = input("Continue anyway? (y/N): ")
            if response.lower() not in ['y', 'yes']:
                print("Test execution cancelled.")
                sys.exit(1)
    else:
        print("⏭️  Skipping service availability check")
    
    # Run tests
    success = runner.run_tests(
        test_pattern=args.pattern,
        markers=args.markers,
        verbose=not args.quiet
    )
    
    # Generate summary
    summary_file = runner.generate_summary_report(success, service_status)
    
    if success:
        print("\n🎉 Integration tests completed successfully!")
        sys.exit(0)
    else:
        print(f"\n💥 Integration tests failed. Check reports in: {runner.results_dir}")
        sys.exit(1)


if __name__ == "__main__":
    main()