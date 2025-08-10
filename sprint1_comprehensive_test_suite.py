#!/usr/bin/env python3
"""
PyAirtable MCP Sprint 1 Comprehensive Test Suite
QA Lead Test Runner for all Sprint 1 branches

Tests:
1. feature/SCRUM-15-fix-authentication (Go)
2. feature/SCRUM-16-repair-airtable (Python) 
3. feature/SCRUM-17-deploy-frontend (TypeScript)
4. feature/SCRUM-18-fix-automation (Python)
5. feature/SCRUM-19-stabilize-saga (Python)
"""

import os
import sys
import json
import time
import subprocess
import asyncio
import aiohttp
import logging
from datetime import datetime
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'sprint1_test_report_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class TestResult:
    branch: str
    service_type: str
    test_type: str
    status: str
    duration: float
    details: Dict[str, Any]
    coverage: Optional[float] = None
    performance_metrics: Dict[str, Any] = None
    security_findings: List[str] = None

class Sprint1TestRunner:
    def __init__(self):
        self.base_path = Path("/Users/kg/IdeaProjects/pyairtable-compose")
        self.results = []
        self.current_branch = None
        self.test_start_time = datetime.now()
        
        # Sprint 1 branches mapping
        self.sprint1_branches = {
            'feature/SCRUM-15-fix-authentication': {
                'type': 'go',
                'service': 'auth-service',
                'port': 8081,
                'health_endpoint': '/health'
            },
            'feature/SCRUM-16-repair-airtable': {
                'type': 'python',
                'service': 'airtable-gateway',
                'port': 8082,
                'health_endpoint': '/health'
            },
            'feature/SCRUM-17-deploy-frontend': {
                'type': 'typescript',
                'service': 'tenant-dashboard',
                'port': 3000,
                'health_endpoint': '/api/health'
            },
            'feature/SCRUM-18-fix-automation': {
                'type': 'python',
                'service': 'automation-services',
                'port': 8084,
                'health_endpoint': '/health'
            },
            'feature/SCRUM-19-stabilize-saga': {
                'type': 'python',
                'service': 'saga-orchestrator',
                'port': 8085,
                'health_endpoint': '/health'
            }
        }

    def run_command(self, cmd: str, cwd: Optional[str] = None, timeout: int = 300) -> Dict[str, Any]:
        """Execute shell command with timeout and capture output"""
        start_time = time.time()
        cwd = cwd or str(self.base_path)
        
        try:
            result = subprocess.run(
                cmd,
                shell=True,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            
            duration = time.time() - start_time
            
            return {
                'success': result.returncode == 0,
                'returncode': result.returncode,
                'stdout': result.stdout,
                'stderr': result.stderr,
                'duration': duration,
                'command': cmd
            }
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'returncode': -1,
                'stdout': '',
                'stderr': f'Command timed out after {timeout} seconds',
                'duration': timeout,
                'command': cmd
            }
        except Exception as e:
            return {
                'success': False,
                'returncode': -1,
                'stdout': '',
                'stderr': str(e),
                'duration': time.time() - start_time,
                'command': cmd
            }

    def switch_branch(self, branch: str) -> bool:
        """Switch to specified branch"""
        logger.info(f"Switching to branch: {branch}")
        result = self.run_command(f"git checkout {branch}")
        
        if result['success']:
            self.current_branch = branch
            logger.info(f"Successfully switched to {branch}")
            return True
        else:
            logger.error(f"Failed to switch to {branch}: {result['stderr']}")
            return False

    def test_go_service(self, branch: str, config: Dict) -> List[TestResult]:
        """Test Go service (authentication)"""
        results = []
        service_path = self.base_path / "go-services" / config['service']
        
        # Unit Tests
        logger.info(f"Running Go unit tests for {branch}")
        test_result = self.run_command("go test -v -cover ./...", cwd=str(service_path))
        
        results.append(TestResult(
            branch=branch,
            service_type='go',
            test_type='unit',
            status='pass' if test_result['success'] else 'fail',
            duration=test_result['duration'],
            details={
                'output': test_result['stdout'],
                'errors': test_result['stderr']
            },
            coverage=self.extract_go_coverage(test_result['stdout'])
        ))

        # Build Test
        logger.info(f"Testing Go build for {branch}")
        build_result = self.run_command("go build -o test-binary ./cmd/main.go", cwd=str(service_path))
        
        results.append(TestResult(
            branch=branch,
            service_type='go',
            test_type='build',
            status='pass' if build_result['success'] else 'fail',
            duration=build_result['duration'],
            details={
                'output': build_result['stdout'],
                'errors': build_result['stderr']
            }
        ))

        # Dependency Check
        logger.info(f"Checking Go dependencies for {branch}")
        deps_result = self.run_command("go mod tidy && go mod verify", cwd=str(service_path))
        
        results.append(TestResult(
            branch=branch,
            service_type='go',
            test_type='dependencies',
            status='pass' if deps_result['success'] else 'fail',
            duration=deps_result['duration'],
            details={
                'output': deps_result['stdout'],
                'errors': deps_result['stderr']
            }
        ))

        return results

    def test_python_service(self, branch: str, config: Dict) -> List[TestResult]:
        """Test Python service"""
        results = []
        
        # Determine service path
        if config['service'] == 'airtable-gateway':
            service_path = self.base_path / "python-services" / "airtable-gateway"
        elif config['service'] == 'automation-services':
            service_path = self.base_path / "pyairtable-automation-services"
        elif config['service'] == 'saga-orchestrator':
            service_path = self.base_path / "saga-orchestrator"
        else:
            service_path = self.base_path / "python-services" / config['service']
        
        # Unit Tests with pytest
        logger.info(f"Running Python unit tests for {branch}")
        test_cmd = "python -m pytest -v --cov=. --cov-report=json --tb=short"
        test_result = self.run_command(test_cmd, cwd=str(service_path))
        
        results.append(TestResult(
            branch=branch,
            service_type='python',
            test_type='unit',
            status='pass' if test_result['success'] else 'fail',
            duration=test_result['duration'],
            details={
                'output': test_result['stdout'],
                'errors': test_result['stderr']
            },
            coverage=self.extract_python_coverage(service_path)
        ))

        # Dependency Check
        logger.info(f"Checking Python dependencies for {branch}")
        deps_result = self.run_command("pip check", cwd=str(service_path))
        
        results.append(TestResult(
            branch=branch,
            service_type='python',
            test_type='dependencies',
            status='pass' if deps_result['success'] else 'fail',
            duration=deps_result['duration'],
            details={
                'output': deps_result['stdout'],
                'errors': deps_result['stderr']
            }
        ))

        # Linting
        logger.info(f"Running Python linting for {branch}")
        lint_result = self.run_command("python -m flake8 . --max-line-length=100 --ignore=E501,W503", cwd=str(service_path))
        
        results.append(TestResult(
            branch=branch,
            service_type='python',
            test_type='lint',
            status='pass' if lint_result['success'] else 'fail',
            duration=lint_result['duration'],
            details={
                'output': lint_result['stdout'],
                'errors': lint_result['stderr']
            }
        ))

        return results

    def test_typescript_service(self, branch: str, config: Dict) -> List[TestResult]:
        """Test TypeScript/Frontend service"""
        results = []
        service_path = self.base_path / "frontend-services" / config['service']
        
        # Install dependencies
        logger.info(f"Installing dependencies for {branch}")
        install_result = self.run_command("npm ci", cwd=str(service_path))
        
        results.append(TestResult(
            branch=branch,
            service_type='typescript',
            test_type='install',
            status='pass' if install_result['success'] else 'fail',
            duration=install_result['duration'],
            details={
                'output': install_result['stdout'],
                'errors': install_result['stderr']
            }
        ))

        # Unit Tests
        if install_result['success']:
            logger.info(f"Running TypeScript unit tests for {branch}")
            test_result = self.run_command("npm test -- --coverage --watchAll=false", cwd=str(service_path))
            
            results.append(TestResult(
                branch=branch,
                service_type='typescript',
                test_type='unit',
                status='pass' if test_result['success'] else 'fail',
                duration=test_result['duration'],
                details={
                    'output': test_result['stdout'],
                    'errors': test_result['stderr']
                },
                coverage=self.extract_typescript_coverage(service_path)
            ))

            # Build Test
            logger.info(f"Testing TypeScript build for {branch}")
            build_result = self.run_command("npm run build", cwd=str(service_path))
            
            results.append(TestResult(
                branch=branch,
                service_type='typescript',
                test_type='build',
                status='pass' if build_result['success'] else 'fail',
                duration=build_result['duration'],
                details={
                    'output': build_result['stdout'],
                    'errors': build_result['stderr']
                }
            ))

            # Linting
            logger.info(f"Running TypeScript linting for {branch}")
            lint_result = self.run_command("npm run lint", cwd=str(service_path))
            
            results.append(TestResult(
                branch=branch,
                service_type='typescript',
                test_type='lint',
                status='pass' if lint_result['success'] else 'fail',
                duration=lint_result['duration'],
                details={
                    'output': lint_result['stdout'],
                    'errors': lint_result['stderr']
                }
            ))

        return results

    async def test_service_health(self, branch: str, config: Dict) -> TestResult:
        """Test service health endpoint"""
        logger.info(f"Testing health endpoint for {branch}")
        
        # Start the service (simplified - would need proper orchestration)
        url = f"http://localhost:{config['port']}{config['health_endpoint']}"
        
        start_time = time.time()
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=30)) as response:
                    duration = time.time() - start_time
                    
                    return TestResult(
                        branch=branch,
                        service_type=config['type'],
                        test_type='health_check',
                        status='pass' if response.status == 200 else 'fail',
                        duration=duration,
                        details={
                            'status_code': response.status,
                            'response': await response.text()
                        }
                    )
        except Exception as e:
            duration = time.time() - start_time
            return TestResult(
                branch=branch,
                service_type=config['type'],
                test_type='health_check',
                status='fail',
                duration=duration,
                details={
                    'error': str(e)
                }
            )

    def extract_go_coverage(self, output: str) -> Optional[float]:
        """Extract Go test coverage percentage"""
        try:
            for line in output.split('\n'):
                if 'coverage:' in line and '%' in line:
                    coverage_str = line.split('coverage:')[1].split('%')[0].strip()
                    return float(coverage_str)
        except:
            pass
        return None

    def extract_python_coverage(self, service_path: Path) -> Optional[float]:
        """Extract Python test coverage from coverage.json"""
        try:
            coverage_file = service_path / "coverage.json"
            if coverage_file.exists():
                with open(coverage_file, 'r') as f:
                    coverage_data = json.load(f)
                    return coverage_data.get('totals', {}).get('percent_covered')
        except:
            pass
        return None

    def extract_typescript_coverage(self, service_path: Path) -> Optional[float]:
        """Extract TypeScript test coverage"""
        try:
            coverage_file = service_path / "coverage" / "coverage-summary.json"
            if coverage_file.exists():
                with open(coverage_file, 'r') as f:
                    coverage_data = json.load(f)
                    return coverage_data.get('total', {}).get('lines', {}).get('pct')
        except:
            pass
        return None

    def run_security_tests(self, branch: str, config: Dict) -> List[TestResult]:
        """Run security validation tests"""
        results = []
        
        # Dependency vulnerability scan
        logger.info(f"Running security scan for {branch}")
        
        if config['type'] == 'go':
            security_cmd = "go list -json -deps ./... | nancy sleuth"
            service_path = self.base_path / "go-services" / config['service']
        elif config['type'] == 'python':
            security_cmd = "pip-audit --format=json"
            if config['service'] == 'airtable-gateway':
                service_path = self.base_path / "python-services" / "airtable-gateway"
            elif config['service'] == 'automation-services':
                service_path = self.base_path / "pyairtable-automation-services"
            else:
                service_path = self.base_path / "saga-orchestrator"
        else:  # typescript
            security_cmd = "npm audit --json"
            service_path = self.base_path / "frontend-services" / config['service']
        
        security_result = self.run_command(security_cmd, cwd=str(service_path))
        
        results.append(TestResult(
            branch=branch,
            service_type=config['type'],
            test_type='security',
            status='pass' if security_result['success'] else 'fail',
            duration=security_result['duration'],
            details={
                'output': security_result['stdout'],
                'errors': security_result['stderr']
            },
            security_findings=self.parse_security_findings(security_result['stdout'], config['type'])
        ))
        
        return results

    def parse_security_findings(self, output: str, service_type: str) -> List[str]:
        """Parse security scan findings"""
        findings = []
        try:
            if service_type == 'python' and output:
                # Parse pip-audit JSON output
                audit_data = json.loads(output)
                for vuln in audit_data.get('vulnerabilities', []):
                    findings.append(f"{vuln.get('package', 'unknown')}: {vuln.get('id', 'unknown')}")
            elif service_type == 'typescript' and output:
                # Parse npm audit JSON output
                audit_data = json.loads(output)
                for vuln_id, vuln in audit_data.get('vulnerabilities', {}).items():
                    findings.append(f"{vuln.get('name', vuln_id)}: {vuln.get('severity', 'unknown')}")
        except:
            if 'vulnerability' in output.lower() or 'cve' in output.lower():
                findings.append("Security issues detected - manual review required")
        
        return findings

    async def run_performance_tests(self, branch: str, config: Dict) -> TestResult:
        """Run basic performance tests"""
        logger.info(f"Running performance tests for {branch}")
        
        # Simple load test
        start_time = time.time()
        try:
            url = f"http://localhost:{config['port']}{config['health_endpoint']}"
            
            async with aiohttp.ClientSession() as session:
                tasks = []
                for _ in range(10):  # 10 concurrent requests
                    tasks.append(session.get(url))
                
                responses = await asyncio.gather(*tasks, return_exceptions=True)
                
                successful_requests = sum(1 for r in responses if not isinstance(r, Exception))
                duration = time.time() - start_time
                
                return TestResult(
                    branch=branch,
                    service_type=config['type'],
                    test_type='performance',
                    status='pass' if successful_requests >= 8 else 'fail',  # 80% success rate
                    duration=duration,
                    details={
                        'total_requests': len(tasks),
                        'successful_requests': successful_requests,
                        'success_rate': successful_requests / len(tasks)
                    },
                    performance_metrics={
                        'requests_per_second': len(tasks) / duration,
                        'average_response_time': duration / len(tasks)
                    }
                )
        except Exception as e:
            duration = time.time() - start_time
            return TestResult(
                branch=branch,
                service_type=config['type'],
                test_type='performance',
                status='fail',
                duration=duration,
                details={'error': str(e)}
            )

    def test_branch(self, branch: str) -> List[TestResult]:
        """Test a single branch comprehensively"""
        logger.info(f"\n=== Starting comprehensive test for {branch} ===")
        
        if not self.switch_branch(branch):
            return [TestResult(
                branch=branch,
                service_type='unknown',
                test_type='branch_switch',
                status='fail',
                duration=0,
                details={'error': 'Failed to switch to branch'}
            )]
        
        config = self.sprint1_branches[branch]
        results = []
        
        try:
            # Run appropriate tests based on service type
            if config['type'] == 'go':
                results.extend(self.test_go_service(branch, config))
            elif config['type'] == 'python':
                results.extend(self.test_python_service(branch, config))
            elif config['type'] == 'typescript':
                results.extend(self.test_typescript_service(branch, config))
            
            # Run security tests
            results.extend(self.run_security_tests(branch, config))
            
            # Note: Health and performance tests would require running services
            # These are commented out as they need proper service orchestration
            # results.append(await self.test_service_health(branch, config))
            # results.append(await self.run_performance_tests(branch, config))
            
        except Exception as e:
            logger.error(f"Error testing {branch}: {str(e)}")
            results.append(TestResult(
                branch=branch,
                service_type=config['type'],
                test_type='error',
                status='fail',
                duration=0,
                details={'error': str(e)}
            ))
        
        return results

    def generate_report(self) -> Dict[str, Any]:
        """Generate comprehensive test report"""
        total_duration = (datetime.now() - self.test_start_time).total_seconds()
        
        # Aggregate results by branch
        branch_summaries = {}
        for branch in self.sprint1_branches.keys():
            branch_results = [r for r in self.results if r.branch == branch]
            
            total_tests = len(branch_results)
            passed_tests = len([r for r in branch_results if r.status == 'pass'])
            failed_tests = total_tests - passed_tests
            
            # Calculate average coverage
            coverage_results = [r.coverage for r in branch_results if r.coverage is not None]
            avg_coverage = sum(coverage_results) / len(coverage_results) if coverage_results else None
            
            # Collect security findings
            security_findings = []
            for r in branch_results:
                if r.security_findings:
                    security_findings.extend(r.security_findings)
            
            branch_summaries[branch] = {
                'service_type': self.sprint1_branches[branch]['type'],
                'service_name': self.sprint1_branches[branch]['service'],
                'total_tests': total_tests,
                'passed_tests': passed_tests,
                'failed_tests': failed_tests,
                'success_rate': (passed_tests / total_tests) if total_tests > 0 else 0,
                'average_coverage': avg_coverage,
                'security_findings': security_findings,
                'recommendation': self.get_merge_recommendation(branch_results)
            }
        
        # Overall summary
        total_tests = len(self.results)
        total_passed = len([r for r in self.results if r.status == 'pass'])
        
        report = {
            'sprint': 'Sprint 1',
            'test_execution_date': self.test_start_time.isoformat(),
            'total_duration_seconds': total_duration,
            'overall_summary': {
                'total_branches_tested': len(self.sprint1_branches),
                'total_tests_executed': total_tests,
                'total_tests_passed': total_passed,
                'total_tests_failed': total_tests - total_passed,
                'overall_success_rate': (total_passed / total_tests) if total_tests > 0 else 0
            },
            'branch_summaries': branch_summaries,
            'detailed_results': [
                {
                    'branch': r.branch,
                    'service_type': r.service_type,
                    'test_type': r.test_type,
                    'status': r.status,
                    'duration': r.duration,
                    'coverage': r.coverage,
                    'security_findings': r.security_findings,
                    'details': r.details
                }
                for r in self.results
            ],
            'recommendations': self.get_overall_recommendations()
        }
        
        return report

    def get_merge_recommendation(self, branch_results: List[TestResult]) -> str:
        """Get merge recommendation for a branch"""
        if not branch_results:
            return "BLOCK - No test results available"
        
        failed_results = [r for r in branch_results if r.status == 'fail']
        security_issues = any(r.security_findings for r in branch_results if r.security_findings)
        
        if not failed_results and not security_issues:
            return "APPROVE - All tests passing, no security issues"
        elif len(failed_results) <= 1 and not security_issues:
            return "CONDITIONAL - Minor issues, can merge with fixes"
        elif security_issues:
            return "BLOCK - Security vulnerabilities detected"
        else:
            return "BLOCK - Multiple test failures"

    def get_overall_recommendations(self) -> List[str]:
        """Get overall recommendations for Sprint 1"""
        recommendations = []
        
        # Check overall success rate
        total_tests = len(self.results)
        total_passed = len([r for r in self.results if r.status == 'pass'])
        success_rate = (total_passed / total_tests) if total_tests > 0 else 0
        
        if success_rate >= 0.9:
            recommendations.append("Sprint 1 is in excellent shape for release")
        elif success_rate >= 0.8:
            recommendations.append("Sprint 1 is ready for release with minor fixes")
        elif success_rate >= 0.7:
            recommendations.append("Sprint 1 needs additional work before release")
        else:
            recommendations.append("Sprint 1 requires significant fixes before release")
        
        # Check for security issues
        security_branches = [r.branch for r in self.results if r.security_findings]
        if security_branches:
            recommendations.append(f"Address security vulnerabilities in: {', '.join(set(security_branches))}")
        
        # Check for coverage
        low_coverage_branches = []
        for branch in self.sprint1_branches.keys():
            branch_results = [r for r in self.results if r.branch == branch and r.coverage is not None]
            if branch_results:
                avg_coverage = sum(r.coverage for r in branch_results) / len(branch_results)
                if avg_coverage < 70:
                    low_coverage_branches.append(branch)
        
        if low_coverage_branches:
            recommendations.append(f"Improve test coverage for: {', '.join(low_coverage_branches)}")
        
        return recommendations

    async def run_all_tests(self):
        """Run comprehensive tests for all Sprint 1 branches"""
        logger.info("Starting Sprint 1 comprehensive test suite")
        
        # Store original branch
        original_branch_result = self.run_command("git branch --show-current")
        original_branch = original_branch_result['stdout'].strip() if original_branch_result['success'] else 'main'
        
        try:
            # Test each branch
            for branch in self.sprint1_branches.keys():
                branch_results = self.test_branch(branch)
                self.results.extend(branch_results)
                
                # Log branch summary
                passed = len([r for r in branch_results if r.status == 'pass'])
                failed = len([r for r in branch_results if r.status == 'fail'])
                logger.info(f"{branch}: {passed} passed, {failed} failed")
        
        finally:
            # Switch back to original branch
            self.switch_branch(original_branch)
        
        # Generate and save report
        report = self.generate_report()
        report_file = f"sprint1_comprehensive_test_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        logger.info(f"Test report saved to: {report_file}")
        
        # Print summary
        print("\n" + "="*80)
        print("SPRINT 1 COMPREHENSIVE TEST SUMMARY")
        print("="*80)
        print(f"Total Duration: {report['total_duration_seconds']:.2f} seconds")
        print(f"Branches Tested: {report['overall_summary']['total_branches_tested']}")
        print(f"Tests Executed: {report['overall_summary']['total_tests_executed']}")
        print(f"Tests Passed: {report['overall_summary']['total_tests_passed']}")
        print(f"Tests Failed: {report['overall_summary']['total_tests_failed']}")
        print(f"Success Rate: {report['overall_summary']['overall_success_rate']:.1%}")
        print("\nBRANCH SUMMARIES:")
        print("-"*80)
        
        for branch, summary in report['branch_summaries'].items():
            print(f"{branch}")
            print(f"  Service: {summary['service_name']} ({summary['service_type']})")
            print(f"  Tests: {summary['passed_tests']}/{summary['total_tests']} passed ({summary['success_rate']:.1%})")
            if summary['average_coverage']:
                print(f"  Coverage: {summary['average_coverage']:.1f}%")
            if summary['security_findings']:
                print(f"  Security Issues: {len(summary['security_findings'])}")
            print(f"  Recommendation: {summary['recommendation']}")
            print()
        
        print("OVERALL RECOMMENDATIONS:")
        print("-"*80)
        for rec in report['recommendations']:
            print(f"• {rec}")
        
        print("\n" + "="*80)
        return report

if __name__ == "__main__":
    runner = Sprint1TestRunner()
    report = asyncio.run(runner.run_all_tests())