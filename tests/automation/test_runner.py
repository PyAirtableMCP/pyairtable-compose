"""
Test automation framework with CI/CD integration and comprehensive reporting.
Orchestrates test execution, parallel running, and result aggregation.
"""

import asyncio
import os
import sys
import time
import json
import subprocess
import logging
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field
from pathlib import Path
import pytest
import multiprocessing
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
import aiofiles

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class TestSuite:
    """Test suite configuration"""
    name: str
    path: str
    markers: List[str]
    parallel: bool = True
    timeout: int = 300  # 5 minutes default
    critical: bool = False  # Critical for deployment
    dependencies: List[str] = field(default_factory=list)


@dataclass
class TestResult:
    """Test execution result"""
    suite_name: str
    status: str  # "passed", "failed", "skipped", "error"
    duration: float
    test_count: int
    passed: int
    failed: int
    skipped: int
    error_details: Optional[str] = None
    coverage_percentage: Optional[float] = None
    artifacts: List[str] = field(default_factory=list)


@dataclass
class TestExecutionPlan:
    """Complete test execution plan"""
    suites: List[TestSuite]
    parallel_groups: List[List[str]]
    estimated_duration: float
    environment: str


class TestAutomationFramework:
    """Comprehensive test automation framework"""

    def __init__(self, config_path: Optional[str] = None):
        """Initialize test automation framework"""
        self.config_path = config_path or "tests/automation/config.json"
        self.results_dir = Path("tests/reports")
        self.artifacts_dir = Path("tests/artifacts")
        self.config = self._load_configuration()
        self.test_results: List[TestResult] = []
        
        # Ensure directories exist
        self.results_dir.mkdir(parents=True, exist_ok=True)
        self.artifacts_dir.mkdir(parents=True, exist_ok=True)

    def _load_configuration(self) -> Dict[str, Any]:
        """Load test automation configuration"""
        default_config = {
            "environment": os.getenv("TEST_ENV", "local"),
            "parallel_workers": multiprocessing.cpu_count(),
            "timeout_multiplier": 1.0,
            "retry_failed_tests": True,
            "generate_coverage": True,
            "artifact_retention_days": 7,
            "notification_channels": [],
            "test_suites": self._get_default_test_suites()
        }
        
        try:
            if os.path.exists(self.config_path):
                with open(self.config_path, 'r') as f:
                    config = json.load(f)
                    # Merge with defaults
                    default_config.update(config)
            return default_config
        except Exception as e:
            logger.warning(f"Could not load config from {self.config_path}: {e}")
            return default_config

    def _get_default_test_suites(self) -> List[Dict[str, Any]]:
        """Get default test suite configuration"""
        return [
            {
                "name": "Unit Tests",
                "path": "tests/unit",
                "markers": ["unit"],
                "parallel": True,
                "timeout": 120,
                "critical": True
            },
            {
                "name": "Integration Tests",
                "path": "tests/integration",
                "markers": ["integration"],
                "parallel": True,
                "timeout": 300,
                "critical": True,
                "dependencies": ["unit"]
            },
            {
                "name": "Contract Tests",
                "path": "tests/contract",
                "markers": ["contract"],
                "parallel": True,
                "timeout": 180,
                "critical": True,
                "dependencies": ["integration"]
            },
            {
                "name": "Security Tests",
                "path": "tests/security",
                "markers": ["security"],
                "parallel": True,
                "timeout": 600,
                "critical": True,
                "dependencies": ["integration"]
            },
            {
                "name": "End-to-End Tests",
                "path": "tests/e2e",
                "markers": ["e2e"],
                "parallel": False,  # E2E tests should run sequentially
                "timeout": 900,
                "critical": True,
                "dependencies": ["contract", "security"]
            },
            {
                "name": "Performance Tests",
                "path": "tests/performance",
                "markers": ["performance"],
                "parallel": False,
                "timeout": 1200,
                "critical": False,
                "dependencies": ["e2e"]
            },
            {
                "name": "Chaos Tests",
                "path": "tests/chaos",
                "markers": ["chaos"],
                "parallel": False,
                "timeout": 1800,
                "critical": False,
                "dependencies": ["performance"]
            },
            {
                "name": "Deployment Smoke Tests",
                "path": "tests/deployment",
                "markers": ["deployment", "smoke"],
                "parallel": True,
                "timeout": 300,
                "critical": True,
                "dependencies": []  # Can run independently
            }
        ]

    async def create_execution_plan(self, test_filter: Optional[str] = None) -> TestExecutionPlan:
        """Create optimized test execution plan"""
        # Load test suites
        suites = []
        for suite_config in self.config["test_suites"]:
            # Apply test filter if specified
            if test_filter and test_filter not in suite_config["name"].lower():
                continue
            
            suite = TestSuite(
                name=suite_config["name"],
                path=suite_config["path"],
                markers=suite_config["markers"],
                parallel=suite_config.get("parallel", True),
                timeout=int(suite_config.get("timeout", 300) * self.config["timeout_multiplier"]),
                critical=suite_config.get("critical", False),
                dependencies=suite_config.get("dependencies", [])
            )
            suites.append(suite)
        
        # Create parallel execution groups based on dependencies
        parallel_groups = self._create_parallel_groups(suites)
        
        # Estimate execution duration
        estimated_duration = self._estimate_execution_duration(suites, parallel_groups)
        
        return TestExecutionPlan(
            suites=suites,
            parallel_groups=parallel_groups,
            estimated_duration=estimated_duration,
            environment=self.config["environment"]
        )

    def _create_parallel_groups(self, suites: List[TestSuite]) -> List[List[str]]:
        """Create parallel execution groups based on dependencies"""
        # Simple dependency resolution - in production, use proper topological sort
        groups = []
        remaining_suites = {suite.name: suite for suite in suites}
        
        while remaining_suites:
            # Find suites with no unresolved dependencies
            current_group = []
            
            for suite_name, suite in remaining_suites.items():
                dependencies_met = all(
                    dep not in remaining_suites for dep in suite.dependencies
                )
                
                if dependencies_met:
                    current_group.append(suite_name)
            
            if not current_group:
                # Circular dependency or error - add all remaining
                current_group = list(remaining_suites.keys())
                logger.warning("Potential circular dependency detected in test suites")
            
            groups.append(current_group)
            
            # Remove processed suites
            for suite_name in current_group:
                remaining_suites.pop(suite_name, None)
        
        return groups

    def _estimate_execution_duration(self, suites: List[TestSuite], groups: List[List[str]]) -> float:
        """Estimate total execution duration"""
        suite_durations = {suite.name: suite.timeout for suite in suites}
        
        total_duration = 0
        for group in groups:
            if len(group) > 1 and self.config["parallel_workers"] > 1:
                # Parallel execution - use longest suite in group
                group_duration = max(suite_durations.get(name, 0) for name in group)
            else:
                # Sequential execution
                group_duration = sum(suite_durations.get(name, 0) for name in group)
            
            total_duration += group_duration
        
        return total_duration

    async def execute_test_plan(self, plan: TestExecutionPlan) -> List[TestResult]:
        """Execute the complete test plan"""
        logger.info(f"Executing test plan with {len(plan.suites)} test suites")
        logger.info(f"Estimated duration: {plan.estimated_duration / 60:.1f} minutes")
        
        start_time = time.time()
        all_results = []
        
        for group_index, group in enumerate(plan.parallel_groups):
            logger.info(f"Executing group {group_index + 1}/{len(plan.parallel_groups)}: {group}")
            
            # Get suites for this group
            group_suites = [suite for suite in plan.suites if suite.name in group]
            
            if len(group_suites) > 1 and self.config["parallel_workers"] > 1:
                # Execute group in parallel
                group_results = await self._execute_parallel_group(group_suites)
            else:
                # Execute group sequentially
                group_results = await self._execute_sequential_group(group_suites)
            
            all_results.extend(group_results)
            
            # Check if critical tests failed
            critical_failures = [
                result for result in group_results 
                if result.status == "failed" and any(
                    suite.critical for suite in group_suites if suite.name == result.suite_name
                )
            ]
            
            if critical_failures and self.config["environment"] in ["staging", "production"]:
                logger.error(f"Critical test failures detected: {[r.suite_name for r in critical_failures]}")
                # In production environments, might want to stop execution
                break
        
        total_duration = time.time() - start_time
        logger.info(f"Test execution completed in {total_duration / 60:.1f} minutes")
        
        self.test_results = all_results
        return all_results

    async def _execute_parallel_group(self, suites: List[TestSuite]) -> List[TestResult]:
        """Execute test suites in parallel"""
        max_workers = min(len(suites), self.config["parallel_workers"])
        
        async def execute_suite_async(suite: TestSuite) -> TestResult:
            """Execute single test suite asynchronously"""
            return await asyncio.to_thread(self._execute_single_suite, suite)
        
        # Execute suites in parallel
        tasks = [execute_suite_async(suite) for suite in suites]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Handle exceptions
        final_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                final_results.append(TestResult(
                    suite_name=suites[i].name,
                    status="error",
                    duration=0,
                    test_count=0,
                    passed=0,
                    failed=0,
                    skipped=0,
                    error_details=str(result)
                ))
            else:
                final_results.append(result)
        
        return final_results

    async def _execute_sequential_group(self, suites: List[TestSuite]) -> List[TestResult]:
        """Execute test suites sequentially"""
        results = []
        
        for suite in suites:
            logger.info(f"Executing {suite.name}...")
            result = await asyncio.to_thread(self._execute_single_suite, suite)
            results.append(result)
            
            # If critical suite fails, consider stopping
            if result.status == "failed" and suite.critical:
                logger.warning(f"Critical suite {suite.name} failed")
        
        return results

    def _execute_single_suite(self, suite: TestSuite) -> TestResult:
        """Execute a single test suite"""
        start_time = time.time()
        
        try:
            # Build pytest command
            cmd = self._build_pytest_command(suite)
            
            logger.info(f"Running: {' '.join(cmd)}")
            
            # Execute pytest
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=suite.timeout,
                cwd=os.getcwd()
            )
            
            duration = time.time() - start_time
            
            # Parse pytest output
            test_stats = self._parse_pytest_output(result.stdout, result.stderr)
            
            # Determine status
            if result.returncode == 0:
                status = "passed"
            elif result.returncode == 5:  # No tests collected
                status = "skipped"
            else:
                status = "failed"
            
            # Collect artifacts
            artifacts = self._collect_test_artifacts(suite)
            
            return TestResult(
                suite_name=suite.name,
                status=status,
                duration=duration,
                test_count=test_stats["total"],
                passed=test_stats["passed"],
                failed=test_stats["failed"],
                skipped=test_stats["skipped"],
                error_details=result.stderr if result.returncode != 0 else None,
                coverage_percentage=test_stats.get("coverage"),
                artifacts=artifacts
            )
        
        except subprocess.TimeoutExpired:
            return TestResult(
                suite_name=suite.name,
                status="failed",
                duration=suite.timeout,
                test_count=0,
                passed=0,
                failed=0,
                skipped=0,
                error_details=f"Test suite timed out after {suite.timeout} seconds"
            )
        
        except Exception as e:
            return TestResult(
                suite_name=suite.name,
                status="error",
                duration=time.time() - start_time,
                test_count=0,
                passed=0,
                failed=0,
                skipped=0,
                error_details=str(e)
            )

    def _build_pytest_command(self, suite: TestSuite) -> List[str]:
        """Build pytest command for test suite"""
        cmd = ["python", "-m", "pytest"]
        
        # Add test path
        if os.path.exists(suite.path):
            cmd.append(suite.path)
        else:
            logger.warning(f"Test path {suite.path} does not exist")
            return cmd
        
        # Add markers
        if suite.markers:
            marker_expr = " or ".join(suite.markers)
            cmd.extend(["-m", marker_expr])
        
        # Add output options
        cmd.extend([
            "-v",  # Verbose output
            "--tb=short",  # Short traceback format
            "--strict-markers",  # Strict marker handling
            f"--junitxml={self.results_dir}/{suite.name.lower().replace(' ', '_')}_results.xml"
        ])
        
        # Add coverage if enabled
        if self.config.get("generate_coverage", True):
            cmd.extend([
                "--cov=src",
                "--cov-report=xml",
                f"--cov-report=html:{self.results_dir}/coverage_{suite.name.lower().replace(' ', '_')}"
            ])
        
        # Add parallel execution for supported suites
        if suite.parallel and self.config["parallel_workers"] > 1:
            cmd.extend(["-n", str(min(4, self.config["parallel_workers"]))])  # Limit to 4 for stability
        
        # Add environment-specific options
        if self.config["environment"] == "ci":
            cmd.extend([
                "--maxfail=5",  # Stop after 5 failures in CI
                "--disable-warnings"  # Reduce noise in CI
            ])
        
        return cmd

    def _parse_pytest_output(self, stdout: str, stderr: str) -> Dict[str, Any]:
        """Parse pytest output to extract test statistics"""
        stats = {
            "total": 0,
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "coverage": None
        }
        
        # Parse test results from output
        lines = stdout.split('\n')
        
        for line in lines:
            # Look for test summary line
            if "passed" in line or "failed" in line or "skipped" in line:
                # Extract numbers from summary line
                import re
                numbers = re.findall(r'(\d+)', line)
                
                if "passed" in line:
                    stats["passed"] = int(numbers[0]) if numbers else 0
                elif "failed" in line:
                    stats["failed"] = int(numbers[0]) if numbers else 0
                elif "skipped" in line:
                    stats["skipped"] = int(numbers[0]) if numbers else 0
            
            # Look for coverage information
            if "coverage" in line.lower() and "%" in line:
                import re
                coverage_match = re.search(r'(\d+)%', line)
                if coverage_match:
                    stats["coverage"] = float(coverage_match.group(1))
        
        stats["total"] = stats["passed"] + stats["failed"] + stats["skipped"]
        
        return stats

    def _collect_test_artifacts(self, suite: TestSuite) -> List[str]:
        """Collect test artifacts and logs"""
        artifacts = []
        
        # Collect test result files
        result_file = self.results_dir / f"{suite.name.lower().replace(' ', '_')}_results.xml"
        if result_file.exists():
            artifacts.append(str(result_file))
        
        # Collect coverage reports
        coverage_dir = self.results_dir / f"coverage_{suite.name.lower().replace(' ', '_')}"
        if coverage_dir.exists():
            artifacts.append(str(coverage_dir))
        
        # Collect screenshots for E2E tests
        if "e2e" in suite.markers:
            screenshots_dir = self.results_dir / "screenshots"
            if screenshots_dir.exists():
                artifacts.extend([
                    str(f) for f in screenshots_dir.glob("*.png")
                    if f.stat().st_mtime >= time.time() - 3600  # Last hour
                ])
        
        # Collect performance reports
        if "performance" in suite.markers:
            perf_dir = self.results_dir / "performance"
            if perf_dir.exists():
                artifacts.extend([
                    str(f) for f in perf_dir.glob("*.json")
                    if f.stat().st_mtime >= time.time() - 3600
                ])
        
        return artifacts

    async def generate_comprehensive_report(self) -> Dict[str, Any]:
        """Generate comprehensive test execution report"""
        if not self.test_results:
            return {}
        
        total_tests = sum(result.test_count for result in self.test_results)
        total_passed = sum(result.passed for result in self.test_results)
        total_failed = sum(result.failed for result in self.test_results)
        total_skipped = sum(result.skipped for result in self.test_results)
        total_duration = sum(result.duration for result in self.test_results)
        
        # Calculate success rate
        success_rate = (total_passed / total_tests * 100) if total_tests > 0 else 0
        
        # Identify critical failures
        critical_failures = [
            result for result in self.test_results
            if result.status == "failed" and any(
                suite.critical for suite in self._get_all_suites()
                if suite.name == result.suite_name
            )
        ]
        
        # Generate report
        report = {
            "summary": {
                "execution_time": time.time(),
                "environment": self.config["environment"],
                "total_suites": len(self.test_results),
                "total_tests": total_tests,
                "passed": total_passed,
                "failed": total_failed,
                "skipped": total_skipped,
                "success_rate": f"{success_rate:.1f}%",
                "total_duration": f"{total_duration / 60:.1f} minutes",
                "critical_failures": len(critical_failures)
            },
            "suite_results": [],
            "coverage": self._aggregate_coverage_data(),
            "artifacts": self._collect_all_artifacts(),
            "recommendations": self._generate_recommendations()
        }
        
        # Add individual suite results
        for result in self.test_results:
            suite_data = {
                "name": result.suite_name,
                "status": result.status,
                "duration": f"{result.duration:.2f}s",
                "tests": {
                    "total": result.test_count,
                    "passed": result.passed,
                    "failed": result.failed,
                    "skipped": result.skipped
                },
                "success_rate": f"{(result.passed / result.test_count * 100):.1f}%" if result.test_count > 0 else "0%",
                "coverage": f"{result.coverage_percentage:.1f}%" if result.coverage_percentage else "N/A",
                "artifacts": result.artifacts,
                "error_details": result.error_details
            }
            report["suite_results"].append(suite_data)
        
        # Save report
        report_path = self.results_dir / "comprehensive_test_report.json"
        async with aiofiles.open(report_path, 'w') as f:
            await f.write(json.dumps(report, indent=2))
        
        # Generate HTML report
        await self._generate_html_report(report)
        
        return report

    def _get_all_suites(self) -> List[TestSuite]:
        """Get all configured test suites"""
        return [
            TestSuite(
                name=suite_config["name"],
                path=suite_config["path"],
                markers=suite_config["markers"],
                critical=suite_config.get("critical", False)
            )
            for suite_config in self.config["test_suites"]
        ]

    def _aggregate_coverage_data(self) -> Dict[str, Any]:
        """Aggregate coverage data from all test suites"""
        coverage_data = {
            "overall_percentage": 0,
            "by_suite": {},
            "uncovered_lines": []
        }
        
        # This would aggregate coverage data from individual suite reports
        # Implementation depends on coverage tool and format
        
        coverage_percentages = [
            result.coverage_percentage for result in self.test_results
            if result.coverage_percentage is not None
        ]
        
        if coverage_percentages:
            coverage_data["overall_percentage"] = sum(coverage_percentages) / len(coverage_percentages)
        
        return coverage_data

    def _collect_all_artifacts(self) -> List[str]:
        """Collect all test artifacts"""
        all_artifacts = []
        
        for result in self.test_results:
            all_artifacts.extend(result.artifacts)
        
        return list(set(all_artifacts))  # Remove duplicates

    def _generate_recommendations(self) -> List[str]:
        """Generate recommendations based on test results"""
        recommendations = []
        
        # Check for failed tests
        failed_suites = [result for result in self.test_results if result.status == "failed"]
        if failed_suites:
            recommendations.append(f"Address {len(failed_suites)} failed test suites before deployment")
        
        # Check for low coverage
        low_coverage_suites = [
            result for result in self.test_results
            if result.coverage_percentage and result.coverage_percentage < 80
        ]
        if low_coverage_suites:
            recommendations.append("Improve test coverage for suites with less than 80% coverage")
        
        # Check for slow tests
        slow_suites = [
            result for result in self.test_results
            if result.duration > 300  # 5 minutes
        ]
        if slow_suites:
            recommendations.append("Consider optimizing slow-running test suites")
        
        # Check for skipped tests
        skipped_tests = sum(result.skipped for result in self.test_results)
        if skipped_tests > 0:
            recommendations.append(f"Review {skipped_tests} skipped tests - ensure they're intentional")
        
        return recommendations

    async def _generate_html_report(self, report_data: Dict[str, Any]):
        """Generate HTML test report"""
        html_content = self._create_html_report_template(report_data)
        
        html_path = self.results_dir / "test_report.html"
        async with aiofiles.open(html_path, 'w') as f:
            await f.write(html_content)

    def _create_html_report_template(self, report_data: Dict[str, Any]) -> str:
        """Create HTML report template"""
        # Simple HTML template - in production, use proper templating
        return f"""
<!DOCTYPE html>
<html>
<head>
    <title>PyAirtable Test Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        .summary {{ background: #f5f5f5; padding: 20px; border-radius: 5px; }}
        .suite {{ margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }}
        .passed {{ border-left: 5px solid #28a745; }}
        .failed {{ border-left: 5px solid #dc3545; }}
        .skipped {{ border-left: 5px solid #ffc107; }}
        .error {{ border-left: 5px solid #6c757d; }}
        table {{ width: 100%; border-collapse: collapse; }}
        th, td {{ padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }}
        th {{ background-color: #f8f9fa; }}
    </style>
</head>
<body>
    <h1>PyAirtable Test Execution Report</h1>
    
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Environment:</strong> {report_data['summary']['environment']}</p>
        <p><strong>Total Tests:</strong> {report_data['summary']['total_tests']}</p>
        <p><strong>Success Rate:</strong> {report_data['summary']['success_rate']}</p>
        <p><strong>Duration:</strong> {report_data['summary']['total_duration']}</p>
        <p><strong>Critical Failures:</strong> {report_data['summary']['critical_failures']}</p>
    </div>
    
    <h2>Test Suite Results</h2>
    {self._generate_suite_html(report_data['suite_results'])}
    
    <h2>Recommendations</h2>
    <ul>
        {''.join(f'<li>{rec}</li>' for rec in report_data.get('recommendations', []))}
    </ul>
</body>
</html>
        """

    def _generate_suite_html(self, suite_results: List[Dict[str, Any]]) -> str:
        """Generate HTML for suite results"""
        html_parts = []
        
        for suite in suite_results:
            status_class = suite['status']
            html_parts.append(f"""
            <div class="suite {status_class}">
                <h3>{suite['name']} - {suite['status'].upper()}</h3>
                <p><strong>Duration:</strong> {suite['duration']}</p>
                <p><strong>Tests:</strong> {suite['tests']['passed']}/{suite['tests']['total']} passed</p>
                <p><strong>Coverage:</strong> {suite['coverage']}</p>
                {f"<p><strong>Error:</strong> {suite['error_details']}</p>" if suite['error_details'] else ""}
            </div>
            """)
        
        return ''.join(html_parts)

    async def notify_results(self, report: Dict[str, Any]):
        """Send test result notifications"""
        # Implementation for various notification channels
        channels = self.config.get("notification_channels", [])
        
        for channel in channels:
            if channel["type"] == "slack":
                await self._send_slack_notification(channel, report)
            elif channel["type"] == "email":
                await self._send_email_notification(channel, report)
            elif channel["type"] == "teams":
                await self._send_teams_notification(channel, report)

    async def _send_slack_notification(self, channel_config: Dict[str, Any], report: Dict[str, Any]):
        """Send Slack notification"""
        # Implementation for Slack notifications
        pass

    async def _send_email_notification(self, channel_config: Dict[str, Any], report: Dict[str, Any]):
        """Send email notification"""
        # Implementation for email notifications
        pass

    async def _send_teams_notification(self, channel_config: Dict[str, Any], report: Dict[str, Any]):
        """Send Microsoft Teams notification"""
        # Implementation for Teams notifications
        pass


async def main():
    """Main test automation runner"""
    import argparse
    
    parser = argparse.ArgumentParser(description="PyAirtable Test Automation Framework")
    parser.add_argument("--config", help="Configuration file path")
    parser.add_argument("--filter", help="Test filter (suite name substring)")
    parser.add_argument("--environment", help="Test environment", default="local")
    parser.add_argument("--parallel", type=int, help="Number of parallel workers")
    parser.add_argument("--notify", action="store_true", help="Send notifications")
    
    args = parser.parse_args()
    
    # Initialize framework
    framework = TestAutomationFramework(config_path=args.config)
    
    # Override environment if specified
    if args.environment:
        framework.config["environment"] = args.environment
    
    # Override parallel workers if specified
    if args.parallel:
        framework.config["parallel_workers"] = args.parallel
    
    try:
        # Create execution plan
        plan = await framework.create_execution_plan(test_filter=args.filter)
        
        # Execute tests
        results = await framework.execute_test_plan(plan)
        
        # Generate comprehensive report
        report = await framework.generate_comprehensive_report()
        
        # Send notifications if requested
        if args.notify:
            await framework.notify_results(report)
        
        # Print summary
        print(f"\n{'='*60}")
        print("TEST EXECUTION SUMMARY")
        print(f"{'='*60}")
        print(f"Environment: {report['summary']['environment']}")
        print(f"Total Tests: {report['summary']['total_tests']}")
        print(f"Success Rate: {report['summary']['success_rate']}")
        print(f"Duration: {report['summary']['total_duration']}")
        print(f"Critical Failures: {report['summary']['critical_failures']}")
        
        # Exit with appropriate code
        if report['summary']['critical_failures'] > 0:
            sys.exit(1)
        elif report['summary']['failed'] > 0:
            sys.exit(2)  # Non-critical failures
        else:
            sys.exit(0)  # Success
    
    except Exception as e:
        logger.error(f"Test automation framework failed: {e}")
        sys.exit(3)


if __name__ == "__main__":
    asyncio.run(main())