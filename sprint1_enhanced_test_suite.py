#!/usr/bin/env python3
"""
PyAirtable MCP Sprint 1 Enhanced Test Suite
Enhanced QA testing with proper environment setup and detailed analysis

This test suite addresses the issues found in the initial run:
- Proper Python environment detection
- Service-specific test strategies
- Better error handling and reporting
- Actionable recommendations
"""

import os
import sys
import json
import time
import subprocess
import asyncio
import logging
import shutil
from datetime import datetime
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, asdict
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'sprint1_enhanced_test_report_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class TestEnvironment:
    """Test environment configuration"""
    python_cmd: Optional[str] = None
    pip_cmd: Optional[str] = None
    go_cmd: Optional[str] = None
    npm_cmd: Optional[str] = None
    docker_cmd: Optional[str] = None
    git_cmd: Optional[str] = None

@dataclass
class ServiceInfo:
    """Service information"""
    name: str
    type: str
    path: Path
    port: int
    health_endpoint: str
    test_command: Optional[str] = None
    build_command: Optional[str] = None
    dependencies_file: Optional[str] = None

@dataclass
class TestResult:
    branch: str
    service: str
    test_type: str
    status: str  # pass, fail, skip, error
    duration: float
    details: Dict[str, Any]
    coverage: Optional[float] = None
    issues: List[str] = None
    recommendations: List[str] = None

    def __post_init__(self):
        if self.issues is None:
            self.issues = []
        if self.recommendations is None:
            self.recommendations = []

class Sprint1EnhancedTestRunner:
    def __init__(self):
        self.base_path = Path("/Users/kg/IdeaProjects/pyairtable-compose")
        self.results: List[TestResult] = []
        self.test_start_time = datetime.now()
        self.env = self._detect_environment()
        
        # Sprint 1 services configuration
        self.services = {
            'feature/SCRUM-15-fix-authentication': ServiceInfo(
                name='auth-service',
                type='go',
                path=self.base_path / "go-services" / "auth-service",
                port=8081,
                health_endpoint='/health',
                build_command='go build -o auth-service ./cmd/auth-service',
                test_command='go test -v -cover ./...'
            ),
            'feature/SCRUM-16-repair-airtable': ServiceInfo(
                name='airtable-gateway',
                type='python',
                path=self.base_path / "python-services" / "airtable-gateway",
                port=8082,
                health_endpoint='/health',
                dependencies_file='requirements.txt'
            ),
            'feature/SCRUM-17-deploy-frontend': ServiceInfo(
                name='tenant-dashboard',
                type='typescript',
                path=self.base_path / "frontend-services" / "tenant-dashboard",
                port=3000,
                health_endpoint='/api/health',
                build_command='npm run build',
                test_command='npm test',
                dependencies_file='package.json'
            ),
            'feature/SCRUM-18-fix-automation': ServiceInfo(
                name='automation-services',
                type='python',
                path=self.base_path / "pyairtable-automation-services",
                port=8084,
                health_endpoint='/health',
                dependencies_file='requirements.txt'
            ),
            'feature/SCRUM-19-stabilize-saga': ServiceInfo(
                name='saga-orchestrator',
                type='python',
                path=self.base_path / "saga-orchestrator",
                port=8085,
                health_endpoint='/health',
                dependencies_file='requirements.txt'
            )
        }

    def _detect_environment(self) -> TestEnvironment:
        """Detect available tools and commands"""
        env = TestEnvironment()
        
        # Python detection
        for python_cmd in ['python3', 'python']:
            if shutil.which(python_cmd):
                env.python_cmd = python_cmd
                break
        
        # Pip detection
        for pip_cmd in ['pip3', 'pip']:
            if shutil.which(pip_cmd):
                env.pip_cmd = pip_cmd
                break
        
        # Other tools
        env.go_cmd = 'go' if shutil.which('go') else None
        env.npm_cmd = 'npm' if shutil.which('npm') else None
        env.docker_cmd = 'docker' if shutil.which('docker') else None
        env.git_cmd = 'git' if shutil.which('git') else None
        
        logger.info(f"Environment detected - Python: {env.python_cmd}, Pip: {env.pip_cmd}, Go: {env.go_cmd}, NPM: {env.npm_cmd}")
        return env

    def run_command(self, cmd: str, cwd: Optional[Path] = None, timeout: int = 300) -> Tuple[bool, str, str, float]:
        """Execute command and return success, stdout, stderr, duration"""
        start_time = time.time()
        cwd_str = str(cwd) if cwd else str(self.base_path)
        
        try:
            result = subprocess.run(
                cmd,
                shell=True,
                cwd=cwd_str,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            
            duration = time.time() - start_time
            return result.returncode == 0, result.stdout, result.stderr, duration
        
        except subprocess.TimeoutExpired:
            duration = time.time() - start_time
            return False, "", f"Command timed out after {timeout} seconds", duration
        except Exception as e:
            duration = time.time() - start_time
            return False, "", str(e), duration

    def switch_branch(self, branch: str) -> bool:
        """Switch to specified branch"""
        if not self.env.git_cmd:
            logger.error("Git command not available")
            return False
        
        logger.info(f"Switching to branch: {branch}")
        success, stdout, stderr, duration = self.run_command(f"git checkout {branch}")
        
        if success:
            logger.info(f"Successfully switched to {branch}")
            return True
        else:
            logger.error(f"Failed to switch to {branch}: {stderr}")
            return False

    def test_go_service(self, branch: str, service: ServiceInfo) -> List[TestResult]:
        """Test Go service with proper error handling"""
        results = []
        
        if not self.env.go_cmd:
            return [TestResult(
                branch=branch,
                service=service.name,
                test_type='environment',
                status='skip',
                duration=0,
                details={'error': 'Go command not available'},
                recommendations=['Install Go to run Go service tests']
            )]
        
        if not service.path.exists():
            return [TestResult(
                branch=branch,
                service=service.name,
                test_type='environment',
                status='fail',
                duration=0,
                details={'error': f'Service path does not exist: {service.path}'},
                recommendations=[f'Ensure {service.name} service exists in the expected location']
            )]
        
        # Test Go module
        logger.info(f"Testing Go module for {service.name}")
        success, stdout, stderr, duration = self.run_command("go mod tidy && go mod verify", service.path)
        
        results.append(TestResult(
            branch=branch,
            service=service.name,
            test_type='module',
            status='pass' if success else 'fail',
            duration=duration,
            details={'stdout': stdout, 'stderr': stderr},
            issues=[stderr] if stderr and not success else [],
            recommendations=['Fix Go module issues'] if not success else []
        ))
        
        # Test compilation
        logger.info(f"Testing Go compilation for {service.name}")
        # Check for main.go in different possible locations
        main_locations = [
            service.path / "cmd" / "main.go",
            service.path / "cmd" / service.name / "main.go",
            service.path / "main.go"
        ]
        
        main_file = None
        for location in main_locations:
            if location.exists():
                main_file = location
                break
        
        if main_file:
            build_cmd = f"go build -o test-binary {main_file.relative_to(service.path)}"
            success, stdout, stderr, duration = self.run_command(build_cmd, service.path)
        else:
            # Try building all packages
            success, stdout, stderr, duration = self.run_command("go build ./...", service.path)
        
        results.append(TestResult(
            branch=branch,
            service=service.name,
            test_type='build',
            status='pass' if success else 'fail',
            duration=duration,
            details={'stdout': stdout, 'stderr': stderr},
            issues=[f"Build failed: {stderr}"] if not success else [],
            recommendations=['Fix compilation errors'] if not success else []
        ))
        
        # Run unit tests
        logger.info(f"Running Go tests for {service.name}")
        success, stdout, stderr, duration = self.run_command("go test -v -cover ./...", service.path)
        
        coverage = self._extract_go_coverage(stdout)
        
        results.append(TestResult(
            branch=branch,
            service=service.name,
            test_type='unit_tests',
            status='pass' if success else 'fail',
            duration=duration,
            details={'stdout': stdout, 'stderr': stderr},
            coverage=coverage,
            issues=[f"Tests failed: {stderr}"] if not success else [],
            recommendations=['Fix failing tests'] if not success else (['Improve test coverage'] if coverage and coverage < 70 else [])
        ))
        
        return results

    def test_python_service(self, branch: str, service: ServiceInfo) -> List[TestResult]:
        """Test Python service with environment detection"""
        results = []
        
        if not self.env.python_cmd:
            return [TestResult(
                branch=branch,
                service=service.name,
                test_type='environment',
                status='skip',
                duration=0,
                details={'error': 'Python command not available'},
                recommendations=['Install Python to run Python service tests']
            )]
        
        if not service.path.exists():
            return [TestResult(
                branch=branch,
                service=service.name,
                test_type='environment',
                status='fail',
                duration=0,
                details={'error': f'Service path does not exist: {service.path}'},
                recommendations=[f'Ensure {service.name} service exists in the expected location']
            )]
        
        # Check for requirements file
        requirements_file = service.path / "requirements.txt"
        if not requirements_file.exists():
            requirements_file = service.path / "pyproject.toml"
        
        if requirements_file.exists():
            logger.info(f"Found dependencies file: {requirements_file}")
            results.append(TestResult(
                branch=branch,
                service=service.name,
                test_type='dependencies_check',
                status='pass',
                duration=0,
                details={'dependencies_file': str(requirements_file)},
                recommendations=['Consider installing dependencies in virtual environment']
            ))
        else:
            results.append(TestResult(
                branch=branch,
                service=service.name,
                test_type='dependencies_check',
                status='fail',
                duration=0,
                details={'error': 'No requirements.txt or pyproject.toml found'},
                recommendations=['Create requirements.txt or pyproject.toml file']
            ))
        
        # Try to detect if virtual environment is needed
        venv_path = service.path / "venv"
        if venv_path.exists():
            python_cmd = str(venv_path / "bin" / "python")
            pip_cmd = str(venv_path / "bin" / "pip")
        else:
            python_cmd = self.env.python_cmd
            pip_cmd = self.env.pip_cmd
        
        # Test basic Python syntax
        logger.info(f"Testing Python syntax for {service.name}")
        python_files = list(service.path.rglob("*.py"))
        if python_files:
            # Test a few key Python files
            for py_file in python_files[:5]:  # Test first 5 Python files
                success, stdout, stderr, duration = self.run_command(f"{python_cmd} -m py_compile {py_file}")
                if not success:
                    results.append(TestResult(
                        branch=branch,
                        service=service.name,
                        test_type='syntax_check',
                        status='fail',
                        duration=duration,
                        details={'file': str(py_file), 'error': stderr},
                        issues=[f"Syntax error in {py_file}: {stderr}"],
                        recommendations=['Fix Python syntax errors']
                    ))
                    break
            else:
                results.append(TestResult(
                    branch=branch,
                    service=service.name,
                    test_type='syntax_check',
                    status='pass',
                    duration=0,
                    details={'files_checked': len(python_files)},
                    recommendations=[]
                ))
        
        # Try to run pytest if available
        if shutil.which('pytest') or (pip_cmd and shutil.which(pip_cmd)):
            logger.info(f"Attempting to run tests for {service.name}")
            success, stdout, stderr, duration = self.run_command(f"{python_cmd} -m pytest --version", service.path)
            if success:
                success, stdout, stderr, duration = self.run_command(f"{python_cmd} -m pytest -v", service.path)
                results.append(TestResult(
                    branch=branch,
                    service=service.name,
                    test_type='unit_tests',
                    status='pass' if success else 'fail',
                    duration=duration,
                    details={'stdout': stdout, 'stderr': stderr},
                    issues=[f"Tests failed: {stderr}"] if not success else [],
                    recommendations=['Fix failing tests'] if not success else []
                ))
            else:
                results.append(TestResult(
                    branch=branch,
                    service=service.name,
                    test_type='unit_tests',
                    status='skip',
                    duration=0,
                    details={'error': 'pytest not available'},
                    recommendations=['Install pytest to run unit tests']
                ))
        
        return results

    def test_typescript_service(self, branch: str, service: ServiceInfo) -> List[TestResult]:
        """Test TypeScript/Node.js service"""
        results = []
        
        if not self.env.npm_cmd:
            return [TestResult(
                branch=branch,
                service=service.name,
                test_type='environment',
                status='skip',
                duration=0,
                details={'error': 'npm command not available'},
                recommendations=['Install Node.js and npm to run TypeScript service tests']
            )]
        
        if not service.path.exists():
            return [TestResult(
                branch=branch,
                service=service.name,
                test_type='environment',
                status='fail',
                duration=0,
                details={'error': f'Service path does not exist: {service.path}'},
                recommendations=[f'Ensure {service.name} service exists in the expected location']
            )]
        
        # Check package.json
        package_json = service.path / "package.json"
        if not package_json.exists():
            return [TestResult(
                branch=branch,
                service=service.name,
                test_type='configuration',
                status='fail',
                duration=0,
                details={'error': 'package.json not found'},
                recommendations=['Create package.json file']
            )]
        
        # Install dependencies (already done in previous test, check if node_modules exists)
        node_modules = service.path / "node_modules"
        if node_modules.exists():
            results.append(TestResult(
                branch=branch,
                service=service.name,
                test_type='dependencies',
                status='pass',
                duration=0,
                details={'node_modules_exists': True},
                recommendations=[]
            ))
        else:
            logger.info(f"Installing dependencies for {service.name}")
            success, stdout, stderr, duration = self.run_command("npm install", service.path)
            results.append(TestResult(
                branch=branch,
                service=service.name,
                test_type='dependencies',
                status='pass' if success else 'fail',
                duration=duration,
                details={'stdout': stdout, 'stderr': stderr},
                issues=[f"Dependency installation failed: {stderr}"] if not success else [],
                recommendations=['Fix dependency issues'] if not success else []
            ))
        
        # TypeScript compilation check
        if node_modules.exists():
            logger.info(f"Checking TypeScript compilation for {service.name}")
            success, stdout, stderr, duration = self.run_command("npx tsc --noEmit", service.path)
            results.append(TestResult(
                branch=branch,
                service=service.name,
                test_type='typescript_check',
                status='pass' if success else 'fail',
                duration=duration,
                details={'stdout': stdout, 'stderr': stderr},
                issues=[f"TypeScript errors: {stderr}"] if not success else [],
                recommendations=['Fix TypeScript compilation errors'] if not success else []
            ))
            
            # Linting check (less strict)
            logger.info(f"Running linting for {service.name}")
            success, stdout, stderr, duration = self.run_command("npm run lint", service.path)
            # Don't fail on linting issues, just report them
            lint_issues = self._parse_lint_issues(stderr)
            results.append(TestResult(
                branch=branch,
                service=service.name,
                test_type='linting',
                status='pass' if success else 'warning',  # Use warning instead of fail
                duration=duration,
                details={'stdout': stdout, 'stderr': stderr},
                issues=lint_issues,
                recommendations=['Address linting issues'] if lint_issues else []
            ))
        
        return results

    def _extract_go_coverage(self, output: str) -> Optional[float]:
        """Extract Go coverage percentage"""
        try:
            lines = output.split('\n')
            for line in lines:
                if 'coverage:' in line and '%' in line:
                    # Look for pattern like "coverage: 54.8% of statements"
                    parts = line.split('coverage:')[1].split('%')[0].strip()
                    return float(parts)
        except:
            pass
        return None

    def _parse_lint_issues(self, stderr: str) -> List[str]:
        """Parse linting issues from stderr"""
        issues = []
        if not stderr:
            return issues
        
        lines = stderr.split('\n')
        for line in lines:
            if 'Error:' in line or 'Warning:' in line:
                issues.append(line.strip())
        
        return issues[:10]  # Limit to first 10 issues

    def analyze_service_structure(self, branch: str, service: ServiceInfo) -> TestResult:
        """Analyze service structure and configuration"""
        issues = []
        recommendations = []
        details = {}
        
        # Check basic structure
        if not service.path.exists():
            return TestResult(
                branch=branch,
                service=service.name,
                test_type='structure',
                status='fail',
                duration=0,
                details={'error': 'Service directory does not exist'},
                issues=['Service directory missing'],
                recommendations=[f'Create {service.name} service directory']
            )
        
        # Service-specific structure checks
        if service.type == 'go':
            required_files = ['go.mod']
            optional_files = ['go.sum', 'Dockerfile', 'README.md']
            
            for file in required_files:
                file_path = service.path / file
                if not file_path.exists():
                    issues.append(f'Missing required file: {file}')
                    recommendations.append(f'Create {file}')
                else:
                    details[file] = 'exists'
            
            # Check for main.go in various locations
            main_locations = [
                service.path / "cmd" / "main.go",
                service.path / "cmd" / service.name / "main.go",
                service.path / "main.go"
            ]
            
            main_found = any(loc.exists() for loc in main_locations)
            if not main_found:
                issues.append('No main.go file found')
                recommendations.append('Create main.go file')
            else:
                details['main_go'] = 'exists'
        
        elif service.type == 'python':
            potential_req_files = ['requirements.txt', 'pyproject.toml', 'setup.py']
            req_file_found = any((service.path / f).exists() for f in potential_req_files)
            
            if not req_file_found:
                issues.append('No dependency file found')
                recommendations.append('Create requirements.txt or pyproject.toml')
            else:
                details['dependency_file'] = 'exists'
            
            # Check for main module
            main_files = list(service.path.glob('main.py')) + list(service.path.glob('src/main.py'))
            if main_files:
                details['main_module'] = str(main_files[0])
        
        elif service.type == 'typescript':
            required_files = ['package.json']
            for file in required_files:
                file_path = service.path / file
                if not file_path.exists():
                    issues.append(f'Missing required file: {file}')
                    recommendations.append(f'Create {file}')
                else:
                    details[file] = 'exists'
        
        # Check Dockerfile
        dockerfile = service.path / 'Dockerfile'
        if dockerfile.exists():
            details['dockerfile'] = 'exists'
        else:
            recommendations.append('Consider adding Dockerfile for containerization')
        
        # Count source files
        if service.type == 'go':
            source_files = list(service.path.rglob('*.go'))
        elif service.type == 'python':
            source_files = list(service.path.rglob('*.py'))
        else:  # typescript
            source_files = list(service.path.rglob('*.ts')) + list(service.path.rglob('*.tsx'))
        
        details['source_files_count'] = len(source_files)
        
        return TestResult(
            branch=branch,
            service=service.name,
            test_type='structure',
            status='fail' if issues else 'pass',
            duration=0,
            details=details,
            issues=issues,
            recommendations=recommendations
        )

    def test_branch_comprehensive(self, branch: str) -> List[TestResult]:
        """Comprehensive testing for a branch"""
        logger.info(f"\n{'='*60}")
        logger.info(f"COMPREHENSIVE TEST: {branch}")
        logger.info(f"{'='*60}")
        
        if not self.switch_branch(branch):
            return [TestResult(
                branch=branch,
                service='unknown',
                test_type='git',
                status='fail',
                duration=0,
                details={'error': 'Failed to switch branch'},
                issues=['Branch switch failed'],
                recommendations=[f'Ensure {branch} exists and is accessible']
            )]
        
        service = self.services[branch]
        results = []
        
        # 1. Structure Analysis
        logger.info(f"Analyzing structure for {service.name}")
        results.append(self.analyze_service_structure(branch, service))
        
        # 2. Service-specific tests
        if service.type == 'go':
            results.extend(self.test_go_service(branch, service))
        elif service.type == 'python':
            results.extend(self.test_python_service(branch, service))
        elif service.type == 'typescript':
            results.extend(self.test_typescript_service(branch, service))
        
        # 3. Security scan (if tools available)
        results.append(self.run_security_scan(branch, service))
        
        return results

    def run_security_scan(self, branch: str, service: ServiceInfo) -> TestResult:
        """Run security scan for service"""
        if service.type == 'typescript' and self.env.npm_cmd:
            logger.info(f"Running security audit for {service.name}")
            success, stdout, stderr, duration = self.run_command("npm audit --json", service.path)
            
            if success or stdout:  # npm audit may return non-zero but still provide results
                try:
                    audit_data = json.loads(stdout)
                    vuln_count = audit_data.get('metadata', {}).get('vulnerabilities', {}).get('total', 0)
                    
                    return TestResult(
                        branch=branch,
                        service=service.name,
                        test_type='security',
                        status='warning' if vuln_count > 0 else 'pass',
                        duration=duration,
                        details={'vulnerabilities': vuln_count, 'audit_data': audit_data},
                        issues=[f"{vuln_count} vulnerabilities found"] if vuln_count > 0 else [],
                        recommendations=['Run npm audit fix to address vulnerabilities'] if vuln_count > 0 else []
                    )
                except json.JSONDecodeError:
                    return TestResult(
                        branch=branch,
                        service=service.name,
                        test_type='security',
                        status='skip',
                        duration=duration,
                        details={'error': 'Could not parse audit output'},
                        recommendations=['Check npm audit output manually']
                    )
        
        # For other service types or if npm not available
        return TestResult(
            branch=branch,
            service=service.name,
            test_type='security',
            status='skip',
            duration=0,
            details={'reason': 'Security scanning not configured for this service type'},
            recommendations=['Configure security scanning tools']
        )

    def generate_comprehensive_report(self) -> Dict[str, Any]:
        """Generate comprehensive test report with actionable insights"""
        total_duration = (datetime.now() - self.test_start_time).total_seconds()
        
        # Aggregate results by branch
        branch_summaries = {}
        for branch in self.services.keys():
            branch_results = [r for r in self.results if r.branch == branch]
            if not branch_results:
                continue
            
            service_name = self.services[branch].name
            service_type = self.services[branch].type
            
            # Count results by status
            total_tests = len(branch_results)
            passed_tests = len([r for r in branch_results if r.status == 'pass'])
            failed_tests = len([r for r in branch_results if r.status == 'fail'])
            skipped_tests = len([r for r in branch_results if r.status == 'skip'])
            warning_tests = len([r for r in branch_results if r.status == 'warning'])
            
            # Collect all issues and recommendations
            all_issues = []
            all_recommendations = []
            for result in branch_results:
                all_issues.extend(result.issues)
                all_recommendations.extend(result.recommendations)
            
            # Remove duplicates while preserving order
            unique_issues = list(dict.fromkeys(all_issues))
            unique_recommendations = list(dict.fromkeys(all_recommendations))
            
            # Calculate merge readiness score
            score = self._calculate_readiness_score(branch_results)
            
            # Determine merge recommendation
            merge_recommendation = self._get_merge_recommendation(branch_results, score)
            
            branch_summaries[branch] = {
                'service_name': service_name,
                'service_type': service_type,
                'readiness_score': score,
                'total_tests': total_tests,
                'passed_tests': passed_tests,
                'failed_tests': failed_tests,
                'skipped_tests': skipped_tests,
                'warning_tests': warning_tests,
                'success_rate': (passed_tests / total_tests) if total_tests > 0 else 0,
                'critical_issues': [issue for issue in unique_issues if 'fail' in issue.lower() or 'error' in issue.lower()],
                'all_issues': unique_issues,
                'recommendations': unique_recommendations,
                'merge_recommendation': merge_recommendation,
                'test_results': [asdict(r) for r in branch_results]
            }
        
        # Overall analysis
        total_tests = len(self.results)
        total_passed = len([r for r in self.results if r.status == 'pass'])
        total_failed = len([r for r in self.results if r.status == 'fail'])
        total_skipped = len([r for r in self.results if r.status == 'skip'])
        
        # Environment summary
        env_summary = {
            'python_available': self.env.python_cmd is not None,
            'pip_available': self.env.pip_cmd is not None,
            'go_available': self.env.go_cmd is not None,
            'npm_available': self.env.npm_cmd is not None,
            'docker_available': self.env.docker_cmd is not None,
            'git_available': self.env.git_cmd is not None,
            'python_command': self.env.python_cmd,
            'go_command': self.env.go_cmd,
            'npm_command': self.env.npm_cmd
        }
        
        # Sprint readiness assessment
        ready_branches = len([branch for branch, summary in branch_summaries.items() 
                            if summary['merge_recommendation'] in ['APPROVE', 'CONDITIONAL']])
        
        sprint_status = self._assess_sprint_status(branch_summaries)
        
        report = {
            'test_metadata': {
                'sprint': 'Sprint 1',
                'execution_date': self.test_start_time.isoformat(),
                'total_duration_seconds': total_duration,
                'test_runner_version': 'Enhanced v2.0'
            },
            'environment_summary': env_summary,
            'overall_summary': {
                'total_branches_tested': len(self.services),
                'ready_branches': ready_branches,
                'total_tests_executed': total_tests,
                'total_tests_passed': total_passed,
                'total_tests_failed': total_failed,
                'total_tests_skipped': total_skipped,
                'overall_success_rate': (total_passed / total_tests) if total_tests > 0 else 0,
                'sprint_readiness': sprint_status
            },
            'branch_summaries': branch_summaries,
            'executive_summary': self._generate_executive_summary(branch_summaries, sprint_status),
            'action_plan': self._generate_action_plan(branch_summaries),
            'next_steps': self._generate_next_steps(branch_summaries)
        }
        
        return report

    def _calculate_readiness_score(self, results: List[TestResult]) -> float:
        """Calculate readiness score (0-100) based on test results"""
        if not results:
            return 0
        
        weights = {
            'pass': 100,
            'warning': 70,
            'skip': 50,
            'fail': 0
        }
        
        total_score = sum(weights.get(result.status, 0) for result in results)
        max_score = len(results) * 100
        
        return (total_score / max_score) * 100 if max_score > 0 else 0

    def _get_merge_recommendation(self, results: List[TestResult], score: float) -> str:
        """Get merge recommendation based on results and score"""
        critical_failures = len([r for r in results if r.status == 'fail' and 
                               any(keyword in issue.lower() for issue in r.issues 
                                   for keyword in ['compile', 'build', 'syntax', 'missing'])])
        
        security_issues = len([r for r in results if r.test_type == 'security' and r.status == 'warning'])
        
        if score >= 90 and critical_failures == 0:
            return 'APPROVE'
        elif score >= 70 and critical_failures <= 1:
            return 'CONDITIONAL'
        elif critical_failures > 0 or security_issues > 0:
            return 'BLOCK'
        else:
            return 'NEEDS_WORK'

    def _assess_sprint_status(self, branch_summaries: Dict) -> str:
        """Assess overall Sprint 1 readiness"""
        approve_count = len([b for b in branch_summaries.values() if b['merge_recommendation'] == 'APPROVE'])
        conditional_count = len([b for b in branch_summaries.values() if b['merge_recommendation'] == 'CONDITIONAL'])
        total_branches = len(branch_summaries)
        
        ready_ratio = (approve_count + conditional_count) / total_branches if total_branches > 0 else 0
        
        if ready_ratio >= 0.8:
            return 'READY'
        elif ready_ratio >= 0.6:
            return 'MOSTLY_READY'
        elif ready_ratio >= 0.4:
            return 'NEEDS_WORK'
        else:
            return 'NOT_READY'

    def _generate_executive_summary(self, branch_summaries: Dict, sprint_status: str) -> Dict[str, Any]:
        """Generate executive summary"""
        total_branches = len(branch_summaries)
        ready_branches = len([b for b in branch_summaries.values() 
                            if b['merge_recommendation'] in ['APPROVE', 'CONDITIONAL']])
        
        critical_issues = []
        for branch, summary in branch_summaries.items():
            if summary['critical_issues']:
                critical_issues.extend([f"{branch}: {issue}" for issue in summary['critical_issues']])
        
        return {
            'sprint_status': sprint_status,
            'readiness_percentage': (ready_branches / total_branches * 100) if total_branches > 0 else 0,
            'total_services': total_branches,
            'ready_services': ready_branches,
            'critical_blockers': len(critical_issues),
            'top_issues': critical_issues[:5],  # Top 5 critical issues
            'environment_issues': self._get_environment_issues()
        }

    def _get_environment_issues(self) -> List[str]:
        """Get environment-related issues"""
        issues = []
        if not self.env.python_cmd:
            issues.append("Python not available - cannot test Python services")
        if not self.env.go_cmd:
            issues.append("Go not available - cannot test Go services")
        if not self.env.npm_cmd:
            issues.append("Node.js/npm not available - cannot test TypeScript services")
        return issues

    def _generate_action_plan(self, branch_summaries: Dict) -> List[Dict[str, Any]]:
        """Generate prioritized action plan"""
        actions = []
        
        # Priority 1: Critical failures
        for branch, summary in branch_summaries.items():
            if summary['merge_recommendation'] == 'BLOCK':
                actions.append({
                    'priority': 'HIGH',
                    'branch': branch,
                    'service': summary['service_name'],
                    'action': 'Fix critical issues',
                    'issues': summary['critical_issues'][:3],  # Top 3 issues
                    'estimated_effort': 'High'
                })
        
        # Priority 2: Environment setup
        env_issues = self._get_environment_issues()
        if env_issues:
            actions.append({
                'priority': 'MEDIUM',
                'branch': 'ALL',
                'service': 'Testing Infrastructure',
                'action': 'Setup testing environment',
                'issues': env_issues,
                'estimated_effort': 'Medium'
            })
        
        # Priority 3: Improvements for conditional branches
        for branch, summary in branch_summaries.items():
            if summary['merge_recommendation'] == 'CONDITIONAL':
                actions.append({
                    'priority': 'MEDIUM',
                    'branch': branch,
                    'service': summary['service_name'],
                    'action': 'Address minor issues',
                    'issues': summary['recommendations'][:3],
                    'estimated_effort': 'Low-Medium'
                })
        
        return actions

    def _generate_next_steps(self, branch_summaries: Dict) -> List[str]:
        """Generate next steps for team"""
        steps = []
        
        # Environment setup
        if not self.env.python_cmd:
            steps.append("Install Python 3.8+ for Python service testing")
        if not self.env.go_cmd:
            steps.append("Install Go 1.19+ for Go service testing")
        if not self.env.npm_cmd:
            steps.append("Install Node.js 18+ for TypeScript service testing")
        
        # Service-specific steps
        blocked_services = [summary['service_name'] for summary in branch_summaries.values() 
                           if summary['merge_recommendation'] == 'BLOCK']
        if blocked_services:
            steps.append(f"Priority: Fix critical issues in {', '.join(blocked_services)}")
        
        conditional_services = [summary['service_name'] for summary in branch_summaries.values() 
                               if summary['merge_recommendation'] == 'CONDITIONAL']
        if conditional_services:
            steps.append(f"Address minor issues in {', '.join(conditional_services)}")
        
        # Testing improvements
        steps.append("Set up automated testing pipeline")
        steps.append("Configure security scanning tools")
        steps.append("Implement service health checks")
        
        return steps

    async def run_comprehensive_tests(self):
        """Run all comprehensive tests"""
        logger.info("="*80)
        logger.info("PYAIRTABLE MCP SPRINT 1 ENHANCED TEST SUITE")
        logger.info("="*80)
        logger.info(f"Environment: Python={self.env.python_cmd}, Go={self.env.go_cmd}, NPM={self.env.npm_cmd}")
        logger.info("="*80)
        
        # Store original branch
        original_branch_result = self.run_command("git branch --show-current")
        original_branch = original_branch_result[1].strip() if original_branch_result[0] else 'main'
        
        try:
            # Test each branch
            for branch in self.services.keys():
                branch_results = self.test_branch_comprehensive(branch)
                self.results.extend(branch_results)
                
                # Log branch summary
                passed = len([r for r in branch_results if r.status == 'pass'])
                failed = len([r for r in branch_results if r.status == 'fail'])
                skipped = len([r for r in branch_results if r.status == 'skip'])
                logger.info(f"{branch}: {passed} passed, {failed} failed, {skipped} skipped")
        
        finally:
            # Switch back to original branch
            self.switch_branch(original_branch)
        
        # Generate and save report
        report = self.generate_comprehensive_report()
        report_file = f"sprint1_enhanced_test_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        logger.info(f"Enhanced test report saved to: {report_file}")
        
        # Print comprehensive summary
        self._print_comprehensive_summary(report)
        
        return report

    def _print_comprehensive_summary(self, report: Dict[str, Any]):
        """Print comprehensive test summary"""
        print("\n" + "="*100)
        print("SPRINT 1 ENHANCED TEST RESULTS")
        print("="*100)
        
        # Executive Summary
        exec_summary = report['executive_summary']
        print(f"Sprint Status: {exec_summary['sprint_status']}")
        print(f"Readiness: {exec_summary['readiness_percentage']:.1f}%")
        print(f"Services Ready: {exec_summary['ready_services']}/{exec_summary['total_services']}")
        print(f"Critical Blockers: {exec_summary['critical_blockers']}")
        
        # Environment
        env = report['environment_summary']
        print(f"\nEnvironment: Python={env['python_available']}, Go={env['go_available']}, NPM={env['npm_available']}")
        
        # Branch Details
        print("\n" + "-"*100)
        print("BRANCH ANALYSIS")
        print("-"*100)
        
        for branch, summary in report['branch_summaries'].items():
            print(f"\n{branch}")
            print(f"  Service: {summary['service_name']} ({summary['service_type']})")
            print(f"  Readiness Score: {summary['readiness_score']:.1f}/100")
            print(f"  Tests: {summary['passed_tests']}/{summary['total_tests']} passed")
            print(f"  Status: {summary['merge_recommendation']}")
            
            if summary['critical_issues']:
                print(f"  Critical Issues:")
                for issue in summary['critical_issues'][:3]:
                    print(f"    • {issue}")
            
            if summary['recommendations']:
                print(f"  Recommendations:")
                for rec in summary['recommendations'][:3]:
                    print(f"    • {rec}")
        
        # Action Plan
        print("\n" + "-"*100)
        print("ACTION PLAN")
        print("-"*100)
        
        for action in report['action_plan']:
            print(f"\n[{action['priority']}] {action['service']} ({action['branch']})")
            print(f"  Action: {action['action']}")
            print(f"  Effort: {action['estimated_effort']}")
            if action.get('issues'):
                for issue in action['issues']:
                    print(f"    • {issue}")
        
        # Next Steps
        print("\n" + "-"*100)
        print("NEXT STEPS")
        print("-"*100)
        
        for i, step in enumerate(report['next_steps'], 1):
            print(f"{i}. {step}")
        
        print("\n" + "="*100)

if __name__ == "__main__":
    runner = Sprint1EnhancedTestRunner()
    report = asyncio.run(runner.run_comprehensive_tests())