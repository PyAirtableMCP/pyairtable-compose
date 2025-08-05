"""
Main Test Orchestrator for PyAirtable Integration Testing Framework
===================================================================

This module provides the main orchestrator that coordinates all testing components,
manages test execution, and provides continuous testing capabilities for local development.
"""

import asyncio
import json
import logging
import os
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any, Set
import uuid
import signal
import sys
from concurrent.futures import ThreadPoolExecutor

from .test_config import TestFrameworkConfig, get_config, TestEnvironment, TestLevel
from .test_reporter import TestReport
from .ui_agents import UITestOrchestrator
from .api_testing import APITestOrchestrator
from .external_api_testing import ExternalAPITestOrchestrator
from .workflow_scenarios import WorkflowTestOrchestrator
from .data_management import TestDataManager

logger = logging.getLogger(__name__)

class TestSuite:
    """Represents a test suite configuration"""
    
    def __init__(self, name: str, description: str, components: List[str], 
                 tags: List[str] = None, parallel: bool = True):
        self.name = name
        self.description = description
        self.components = components  # ui, api, external_api, workflows
        self.tags = tags or []
        self.parallel = parallel
        self.id = str(uuid.uuid4())

class TestExecutionPlan:
    """Defines a test execution plan"""
    
    def __init__(self, suites: List[TestSuite], config: TestFrameworkConfig):
        self.suites = suites
        self.config = config
        self.estimated_duration = self._calculate_duration()
        self.execution_id = str(uuid.uuid4())
        self.created_at = datetime.now()
    
    def _calculate_duration(self) -> int:
        """Estimate total execution duration in seconds"""
        base_durations = {
            "ui": 300,  # 5 minutes
            "api": 180,  # 3 minutes
            "external_api": 240,  # 4 minutes
            "workflows": 900  # 15 minutes
        }
        
        total_duration = 0
        for suite in self.suites:
            suite_duration = sum(base_durations.get(component, 60) for component in suite.components)
            if suite.parallel:
                # If parallel, use the longest component
                suite_duration = max(base_durations.get(component, 60) for component in suite.components)
            total_duration += suite_duration
        
        return total_duration

class ContinuousTestingMonitor:
    """Monitors for changes and triggers test execution"""
    
    def __init__(self, orchestrator: 'TestOrchestrator'):
        self.orchestrator = orchestrator
        self.monitoring = False
        self.last_execution = datetime.now()
        self.file_watcher_task = None
        self.schedule_task = None
        self.watched_paths: Set[Path] = set()
        
        # Configure watched paths
        self._setup_watched_paths()
    
    def _setup_watched_paths(self):
        """Setup paths to watch for changes"""
        base_path = Path.cwd()
        
        # Common paths to watch for changes
        watch_patterns = [
            "tests/**/*.py",
            "src/**/*.py",
            "*.py",
            "docker-compose*.yml",
            "requirements*.txt",
            "package*.json",
            "*.env"
        ]
        
        for pattern in watch_patterns:
            for path in base_path.glob(pattern):
                if path.is_file():
                    self.watched_paths.add(path)
        
        logger.info(f"Watching {len(self.watched_paths)} files for changes")
    
    async def start_monitoring(self, interval: int = 300):  # 5 minutes default
        """Start continuous monitoring"""
        self.monitoring = True
        logger.info("Starting continuous testing monitor")
        
        # Start file watcher
        self.file_watcher_task = asyncio.create_task(self._file_watcher())
        
        # Start scheduled execution
        self.schedule_task = asyncio.create_task(self._scheduled_execution(interval))
        
        try:
            await asyncio.gather(self.file_watcher_task, self.schedule_task)
        except asyncio.CancelledError:
            logger.info("Continuous monitoring stopped")
    
    def stop_monitoring(self):
        """Stop continuous monitoring"""
        self.monitoring = False
        
        if self.file_watcher_task:
            self.file_watcher_task.cancel()
        
        if self.schedule_task:
            self.schedule_task.cancel()
    
    async def _file_watcher(self):
        """Watch for file changes"""
        file_mtimes = {}
        
        # Initialize file modification times
        for path in self.watched_paths:
            try:
                file_mtimes[path] = path.stat().st_mtime
            except OSError:
                continue
        
        while self.monitoring:
            try:
                changed_files = []
                
                for path in list(self.watched_paths):
                    try:
                        current_mtime = path.stat().st_mtime
                        if path in file_mtimes and current_mtime > file_mtimes[path]:
                            changed_files.append(path)
                        file_mtimes[path] = current_mtime
                    except OSError:
                        # File might have been deleted
                        if path in file_mtimes:
                            del file_mtimes[path]
                        self.watched_paths.discard(path)
                
                if changed_files:
                    logger.info(f"File changes detected: {[str(f) for f in changed_files[:5]]}")
                    await self._trigger_change_based_tests(changed_files)
                
                await asyncio.sleep(10)  # Check every 10 seconds
                
            except Exception as e:
                logger.error(f"Error in file watcher: {e}")
                await asyncio.sleep(30)
    
    async def _scheduled_execution(self, interval: int):
        """Run tests on schedule"""
        while self.monitoring:
            try:
                await asyncio.sleep(interval)
                
                if not self.monitoring:
                    break
                
                # Check if enough time has passed since last execution
                time_since_last = (datetime.now() - self.last_execution).total_seconds()
                
                if time_since_last >= interval:
                    logger.info("Running scheduled test execution")
                    await self._trigger_scheduled_tests()
                
            except Exception as e:
                logger.error(f"Error in scheduled execution: {e}")
                await asyncio.sleep(60)
    
    async def _trigger_change_based_tests(self, changed_files: List[Path]):
        """Trigger tests based on file changes"""
        # Determine which test suites to run based on changed files
        suites_to_run = []
        
        # Simple heuristics for determining what to test
        has_python_changes = any(str(f).endswith('.py') for f in changed_files)
        has_config_changes = any(str(f).endswith(('.yml', '.yaml', '.json', '.env')) for f in changed_files)
        has_frontend_changes = any('frontend' in str(f) or str(f).endswith(('.js', '.ts', '.tsx')) for f in changed_files)
        
        if has_config_changes:
            # Run all tests if configuration changed
            suites_to_run = ['smoke', 'api']
        elif has_python_changes:
            # Run API and integration tests for Python changes
            suites_to_run = ['api', 'integration']
        elif has_frontend_changes:
            # Run UI tests for frontend changes
            suites_to_run = ['ui']
        
        if suites_to_run:
            try:
                await self.orchestrator.run_test_suites(suites_to_run)
                self.last_execution = datetime.now()
            except Exception as e:
                logger.error(f"Error running change-based tests: {e}")
    
    async def _trigger_scheduled_tests(self):
        """Trigger scheduled test execution"""
        try:
            # Run smoke tests on schedule
            await self.orchestrator.run_test_suites(['smoke'])
            self.last_execution = datetime.now()
        except Exception as e:
            logger.error(f"Error running scheduled tests: {e}")

class TestOrchestrator:
    """Main test orchestrator for the PyAirtable integration testing framework"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.execution_history: List[TestExecutionPlan] = []
        self.continuous_monitor: Optional[ContinuousTestingMonitor] = None
        self.current_execution: Optional[str] = None
        self.test_results: Dict[str, Any] = {}
        
        # Define predefined test suites
        self.predefined_suites = self._define_predefined_suites()
        
        # Setup signal handlers for graceful shutdown
        self._setup_signal_handlers()
    
    def _define_predefined_suites(self) -> Dict[str, TestSuite]:
        """Define predefined test suites"""
        return {
            "smoke": TestSuite(
                name="Smoke Tests",
                description="Quick smoke tests to verify basic functionality",
                components=["api"],
                tags=["smoke", "quick"],
                parallel=True
            ),
            "integration": TestSuite(
                name="Integration Tests",
                description="Integration tests for API and service communication",
                components=["api", "external_api"],
                tags=["integration", "api"],
                parallel=True
            ),
            "ui": TestSuite(
                name="UI Tests",
                description="User interface and interaction tests",
                components=["ui"],
                tags=["ui", "frontend"],
                parallel=False  # UI tests often need to be sequential
            ),
            "comprehensive": TestSuite(
                name="Comprehensive Tests",
                description="Complete test suite including all components",
                components=["ui", "api", "external_api", "workflows"],
                tags=["comprehensive", "full"],
                parallel=True
            ),
            "workflows": TestSuite(
                name="User Workflow Tests",
                description="End-to-end user workflow scenarios",
                components=["workflows"],
                tags=["workflows", "e2e", "scenarios"],
                parallel=False
            ),
            "performance": TestSuite(
                name="Performance Tests",
                description="Performance and stress testing",
                components=["api", "ui"],
                tags=["performance", "stress"],
                parallel=True
            )
        }
    
    def _setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown"""
        def signal_handler(signum, frame):
            logger.info(f"Received signal {signum}, initiating graceful shutdown...")
            if self.continuous_monitor:
                self.continuous_monitor.stop_monitoring()
            sys.exit(0)
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
    
    async def run_test_suites(self, suite_names: List[str] = None, 
                             tags: List[str] = None) -> TestReport:
        """Run specified test suites"""
        if suite_names is None:
            suite_names = ["comprehensive"]
        
        # Get test suites
        suites_to_run = []
        for suite_name in suite_names:
            if suite_name in self.predefined_suites:
                suite = self.predefined_suites[suite_name]
                
                # Filter by tags if specified
                if tags and not any(tag in suite.tags for tag in tags):
                    continue
                
                suites_to_run.append(suite)
            else:
                logger.warning(f"Unknown test suite: {suite_name}")
        
        if not suites_to_run:
            logger.error("No valid test suites to run")
            return TestReport("No Tests")
        
        # Create execution plan
        execution_plan = TestExecutionPlan(suites_to_run, self.config)
        self.execution_history.append(execution_plan)
        self.current_execution = execution_plan.execution_id
        
        logger.info(f"Starting test execution: {execution_plan.execution_id}")
        logger.info(f"Estimated duration: {execution_plan.estimated_duration} seconds")
        logger.info(f"Suites to run: {[s.name for s in suites_to_run]}")
        
        # Create main test report
        main_report = TestReport("PyAirtable Integration Test Suite")
        
        try:
            async with TestDataManager(self.config) as data_manager:
                # Execute each test suite
                for suite in suites_to_run:
                    suite_start_time = time.time()
                    logger.info(f"Executing test suite: {suite.name}")
                    
                    try:
                        suite_results = await self._execute_test_suite(suite, data_manager)
                        
                        # Add results to main report
                        for result in suite_results:
                            main_report.add_test_result(result)
                        
                        suite_duration = time.time() - suite_start_time
                        logger.info(f"Suite '{suite.name}' completed in {suite_duration:.2f}s")
                        
                    except Exception as e:
                        logger.error(f"Suite '{suite.name}' failed: {e}")
                        # Create error result for the suite
                        from .test_reporter import TestResult
                        error_result = TestResult("Test Orchestrator", f"Suite: {suite.name}")
                        error_result.add_log("error", f"Suite execution failed: {e}")
                        error_result.complete("failed")
                        main_report.add_test_result(error_result)
                
                # Generate final report
                json_report, html_report = await main_report.generate_report()
                
                # Store results
                self.test_results[execution_plan.execution_id] = {
                    "execution_plan": execution_plan,
                    "report": main_report,
                    "json_report_path": json_report,
                    "html_report_path": html_report
                }
                
                logger.info(f"Test execution completed: {execution_plan.execution_id}")
                logger.info(f"Reports generated:")
                logger.info(f"  JSON: {json_report}")
                logger.info(f"  HTML: {html_report}")
        
        except Exception as e:
            logger.error(f"Test execution failed: {e}")
            raise
        
        finally:
            self.current_execution = None
        
        return main_report
    
    async def _execute_test_suite(self, suite: TestSuite, 
                                 data_manager: TestDataManager) -> List[Any]:
        """Execute a single test suite"""
        all_results = []
        
        if suite.parallel and len(suite.components) > 1:
            # Execute components in parallel
            tasks = []
            for component in suite.components:
                task = self._execute_component(component, data_manager)
                tasks.append(task)
            
            component_results = await asyncio.gather(*tasks, return_exceptions=True)
            
            for result in component_results:
                if isinstance(result, Exception):
                    logger.error(f"Component execution failed: {result}")
                else:
                    all_results.extend(result)
        else:
            # Execute components sequentially
            for component in suite.components:
                try:
                    component_results = await self._execute_component(component, data_manager)
                    all_results.extend(component_results)
                except Exception as e:
                    logger.error(f"Component '{component}' execution failed: {e}")
        
        return all_results
    
    async def _execute_component(self, component: str, 
                                data_manager: TestDataManager) -> List[Any]:
        """Execute a specific test component"""
        logger.info(f"Executing component: {component}")
        
        try:
            if component == "ui":
                orchestrator = UITestOrchestrator(self.config)
                report = await orchestrator.run_all_tests()
                return report.test_results
            
            elif component == "api":
                orchestrator = APITestOrchestrator(self.config)
                report = await orchestrator.run_comprehensive_api_tests()
                return report.test_results
            
            elif component == "external_api":
                orchestrator = ExternalAPITestOrchestrator(self.config)
                results = await orchestrator.run_comprehensive_external_api_tests()
                return results
            
            elif component == "workflows":
                orchestrator = WorkflowTestOrchestrator(self.config)
                workflow_results = await orchestrator.run_all_workflows()
                return list(workflow_results.values())
            
            else:
                logger.error(f"Unknown test component: {component}")
                return []
        
        except Exception as e:
            logger.error(f"Component execution failed: {component} - {e}")
            raise
    
    async def start_continuous_testing(self, interval: int = 300):
        """Start continuous testing mode"""
        logger.info("Starting continuous testing mode")
        
        if not self.continuous_monitor:
            self.continuous_monitor = ContinuousTestingMonitor(self)
        
        try:
            await self.continuous_monitor.start_monitoring(interval)
        except KeyboardInterrupt:
            logger.info("Continuous testing interrupted by user")
        finally:
            if self.continuous_monitor:
                self.continuous_monitor.stop_monitoring()
    
    def stop_continuous_testing(self):
        """Stop continuous testing mode"""
        if self.continuous_monitor:
            self.continuous_monitor.stop_monitoring()
            logger.info("Continuous testing stopped")
    
    def get_execution_history(self) -> List[Dict[str, Any]]:
        """Get execution history"""
        history = []
        
        for plan in self.execution_history:
            execution_data = {
                "execution_id": plan.execution_id,
                "created_at": plan.created_at.isoformat(),
                "estimated_duration": plan.estimated_duration,
                "suites": [
                    {
                        "name": suite.name,
                        "description": suite.description,
                        "components": suite.components,
                        "tags": suite.tags
                    }
                    for suite in plan.suites
                ]
            }
            
            # Add results if available
            if plan.execution_id in self.test_results:
                result_data = self.test_results[plan.execution_id]
                execution_data["completed"] = True
                execution_data["report_paths"] = {
                    "json": result_data["json_report_path"],
                    "html": result_data["html_report_path"]
                }
                
                # Add summary statistics
                report = result_data["report"]
                summary = report.get_summary_stats()
                execution_data["summary"] = summary
            else:
                execution_data["completed"] = False
            
            history.append(execution_data)
        
        return history
    
    def get_available_suites(self) -> Dict[str, Dict[str, Any]]:
        """Get available test suites"""
        return {
            name: {
                "name": suite.name,
                "description": suite.description,
                "components": suite.components,
                "tags": suite.tags,
                "parallel": suite.parallel
            }
            for name, suite in self.predefined_suites.items()
        }
    
    async def run_health_check(self) -> Dict[str, Any]:
        """Run a quick health check of the system"""
        logger.info("Running system health check")
        
        health_status = {
            "timestamp": datetime.now().isoformat(),
            "overall_status": "healthy",
            "services": {},
            "config_valid": True,
            "issues": []
        }
        
        try:
            # Validate configuration
            config_issues = self.config.validate()
            if config_issues:
                health_status["config_valid"] = False
                health_status["issues"].extend(config_issues)
                health_status["overall_status"] = "warning"
            
            # Quick API health checks
            async with APITestOrchestrator(self.config) as api_orchestrator:
                async with api_orchestrator.api_tester as api_tester:
                    for service_name, tester in api_tester.testers.items():
                        try:
                            health_result = await tester.test_health_check()
                            health_status["services"][service_name] = {
                                "status": health_result.status,
                                "response_time": health_result.performance_metrics.get("response_time", 0)
                            }
                            
                            if health_result.status != "passed":
                                health_status["overall_status"] = "unhealthy"
                        
                        except Exception as e:
                            health_status["services"][service_name] = {
                                "status": "error",
                                "error": str(e)
                            }
                            health_status["overall_status"] = "unhealthy"
            
            # Check external APIs briefly
            if self.config.airtable.api_key and self.config.gemini.api_key:
                try:
                    external_orchestrator = ExternalAPITestOrchestrator(self.config)
                    # Run minimal external API tests
                    health_status["external_apis"] = "available"
                except Exception as e:
                    health_status["external_apis"] = f"error: {e}"
                    health_status["issues"].append(f"External API check failed: {e}")
        
        except Exception as e:
            health_status["overall_status"] = "error"
            health_status["error"] = str(e)
            logger.error(f"Health check failed: {e}")
        
        logger.info(f"Health check completed: {health_status['overall_status']}")
        return health_status
    
    async def create_custom_suite(self, name: str, description: str, 
                                 components: List[str], tags: List[str] = None) -> str:
        """Create a custom test suite"""
        custom_suite = TestSuite(name, description, components, tags or [])
        suite_id = f"custom_{int(time.time())}"
        self.predefined_suites[suite_id] = custom_suite
        
        logger.info(f"Created custom test suite: {name} (ID: {suite_id})")
        return suite_id

# Convenience functions for common operations

async def run_smoke_tests(config: TestFrameworkConfig = None) -> TestReport:
    """Run smoke tests quickly"""
    orchestrator = TestOrchestrator(config)
    return await orchestrator.run_test_suites(["smoke"])

async def run_integration_tests(config: TestFrameworkConfig = None) -> TestReport:
    """Run integration tests"""
    orchestrator = TestOrchestrator(config)
    return await orchestrator.run_test_suites(["integration"])

async def run_comprehensive_tests(config: TestFrameworkConfig = None) -> TestReport:
    """Run comprehensive test suite"""
    orchestrator = TestOrchestrator(config)
    return await orchestrator.run_test_suites(["comprehensive"])

async def run_health_check(config: TestFrameworkConfig = None) -> Dict[str, Any]:
    """Run system health check"""
    orchestrator = TestOrchestrator(config)
    return await orchestrator.run_health_check()

async def start_continuous_testing(config: TestFrameworkConfig = None, interval: int = 300):
    """Start continuous testing with monitoring"""
    orchestrator = TestOrchestrator(config)
    await orchestrator.start_continuous_testing(interval)

# CLI interface helper
def get_orchestrator_cli_commands() -> Dict[str, Any]:
    """Get CLI commands for the test orchestrator"""
    return {
        "smoke": {
            "function": run_smoke_tests,
            "description": "Run smoke tests",
            "args": []
        },
        "integration": {
            "function": run_integration_tests,
            "description": "Run integration tests",
            "args": []
        },
        "comprehensive": {
            "function": run_comprehensive_tests,
            "description": "Run comprehensive test suite",
            "args": []
        },
        "health": {
            "function": run_health_check,
            "description": "Run system health check",
            "args": []
        },
        "continuous": {
            "function": start_continuous_testing,
            "description": "Start continuous testing mode",
            "args": [
                {"name": "interval", "type": int, "default": 300, "help": "Check interval in seconds"}
            ]
        }
    }