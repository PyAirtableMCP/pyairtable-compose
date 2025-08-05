"""
Comprehensive User Workflow Test Scenarios
==========================================

This module defines and executes comprehensive user workflow test scenarios that validate
complete user journeys through the PyAirtable application, from authentication to data analysis.
"""

import asyncio
import json
import logging
import time
from datetime import datetime
from typing import Dict, List, Optional, Any, Tuple
import uuid
from dataclasses import dataclass, field

from .test_config import TestFrameworkConfig, get_config
from .test_reporter import TestResult
from .ui_agents import SyntheticUIAgent, ChatInterfaceAgent, DataAnalysisAgent
from .api_testing import IntegrationAPITester
from .external_api_testing import ExternalAPITestOrchestrator
from .data_management import TestDataManager

logger = logging.getLogger(__name__)

@dataclass
class WorkflowStep:
    """Represents a single step in a user workflow"""
    step_id: str
    name: str
    description: str
    agent_type: str  # ui, api, external_api, data
    action: str
    parameters: Dict[str, Any] = field(default_factory=dict)
    expected_outcome: str = ""
    timeout: int = 60
    critical: bool = True  # If false, failure won't fail entire workflow

@dataclass
class UserWorkflow:
    """Represents a complete user workflow scenario"""
    workflow_id: str
    name: str
    description: str
    steps: List[WorkflowStep]
    setup_steps: List[WorkflowStep] = field(default_factory=list)
    cleanup_steps: List[WorkflowStep] = field(default_factory=list)
    tags: List[str] = field(default_factory=list)
    estimated_duration: int = 300  # seconds

class WorkflowExecutor:
    """Executes user workflow scenarios"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.ui_agents: Dict[str, SyntheticUIAgent] = {}
        self.api_tester: Optional[IntegrationAPITester] = None
        self.external_api_tester: Optional[ExternalAPITestOrchestrator] = None
        self.data_manager: Optional[TestDataManager] = None
        self.workflow_results: Dict[str, TestResult] = {}
    
    async def __aenter__(self):
        """Initialize all testing resources"""
        try:
            # Initialize UI agents
            self.ui_agents = {
                "chat_agent": ChatInterfaceAgent(self.config),
                "data_agent": DataAnalysisAgent(self.config)
            }
            
            # Initialize other testers
            self.api_tester = IntegrationAPITester(self.config)
            await self.api_tester.__aenter__()
            
            self.external_api_tester = ExternalAPITestOrchestrator(self.config)
            
            self.data_manager = TestDataManager(self.config)
            await self.data_manager.__aenter__()
            
            logger.info("Workflow executor initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize workflow executor: {e}")
            await self.cleanup()
            raise
        
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Cleanup all resources"""
        await self.cleanup()
    
    async def cleanup(self):
        """Cleanup all resources"""
        try:
            # Cleanup UI agents
            for agent in self.ui_agents.values():
                if hasattr(agent, '__aexit__'):
                    await agent.__aexit__(None, None, None)
            
            # Cleanup API tester
            if self.api_tester:
                await self.api_tester.__aexit__(None, None, None)
            
            # Cleanup data manager
            if self.data_manager:
                await self.data_manager.__aexit__(None, None, None)
            
            logger.info("Workflow executor cleanup completed")
        except Exception as e:
            logger.error(f"Error during workflow executor cleanup: {e}")
    
    async def execute_workflow(self, workflow: UserWorkflow) -> TestResult:
        """Execute a complete user workflow"""
        result = TestResult("Workflow Executor", workflow.name)
        result.add_log("info", f"Starting workflow: {workflow.description}")
        
        workflow_data = {}
        
        try:
            # Setup phase
            if workflow.setup_steps:
                result.add_log("info", "Executing setup steps")
                setup_success = await self._execute_steps(workflow.setup_steps, result, workflow_data)
                if not setup_success:
                    result.add_issue("critical", "Setup Failed", "Workflow setup steps failed")
                    result.complete("failed")
                    return result
            
            # Main workflow steps
            result.add_log("info", "Executing main workflow steps")
            main_success = await self._execute_steps(workflow.steps, result, workflow_data)
            
            # Cleanup phase
            if workflow.cleanup_steps:
                result.add_log("info", "Executing cleanup steps")
                await self._execute_steps(workflow.cleanup_steps, result, workflow_data, ignore_failures=True)
            
            # Determine overall result
            if main_success:
                result.complete("passed")
            else:
                result.complete("failed")
        
        except Exception as e:
            result.add_log("error", f"Workflow execution failed: {e}")
            result.complete("failed")
        
        self.workflow_results[workflow.workflow_id] = result
        return result
    
    async def _execute_steps(self, steps: List[WorkflowStep], result: TestResult, 
                           workflow_data: Dict[str, Any], ignore_failures: bool = False) -> bool:
        """Execute a list of workflow steps"""
        all_success = True
        
        for step in steps:
            result.add_log("info", f"Executing step: {step.name}")
            
            try:
                step_start_time = time.time()
                step_success = await self._execute_step(step, result, workflow_data)
                step_duration = time.time() - step_start_time
                
                result.performance_metrics[f"step_{step.step_id}_duration"] = step_duration
                
                if step_success:
                    result.add_log("info", f"✓ Step completed: {step.name} ({step_duration:.2f}s)")
                else:
                    result.add_log("warning", f"✗ Step failed: {step.name} ({step_duration:.2f}s)")
                    
                    if step.critical and not ignore_failures:
                        result.add_issue("high", f"Critical Step Failed: {step.name}", 
                                       step.description)
                        all_success = False
                    elif not ignore_failures:
                        result.add_issue("medium", f"Step Failed: {step.name}", 
                                       step.description)
            
            except Exception as e:
                result.add_log("error", f"Step execution error: {step.name} - {e}")
                if step.critical and not ignore_failures:
                    all_success = False
        
        return all_success
    
    async def _execute_step(self, step: WorkflowStep, result: TestResult, 
                          workflow_data: Dict[str, Any]) -> bool:
        """Execute a single workflow step"""
        try:
            if step.agent_type == "ui":
                return await self._execute_ui_step(step, result, workflow_data)
            elif step.agent_type == "api":
                return await self._execute_api_step(step, result, workflow_data)
            elif step.agent_type == "external_api":
                return await self._execute_external_api_step(step, result, workflow_data)
            elif step.agent_type == "data":
                return await self._execute_data_step(step, result, workflow_data)
            else:
                result.add_log("error", f"Unknown agent type: {step.agent_type}")
                return False
        
        except Exception as e:
            result.add_log("error", f"Step execution failed: {e}")
            return False
    
    async def _execute_ui_step(self, step: WorkflowStep, result: TestResult, 
                             workflow_data: Dict[str, Any]) -> bool:
        """Execute a UI-based step"""
        agent_name = step.parameters.get("agent", "chat_agent")
        agent = self.ui_agents.get(agent_name)
        
        if not agent:
            result.add_log("error", f"UI agent not found: {agent_name}")
            return False
        
        # Initialize agent if needed
        if not hasattr(agent, 'page') or not agent.page:
            await agent.__aenter__()
        
        try:
            if step.action == "navigate":
                url = step.parameters.get("url", self.config.services["frontend"].url)
                success = await agent.navigate_to(url)
                workflow_data["current_url"] = url
                return success
            
            elif step.action == "send_message":
                message = step.parameters.get("message", "")
                # Replace placeholders with workflow data
                for key, value in workflow_data.items():
                    message = message.replace(f"{{{key}}}", str(value))
                
                # Navigate to chat if not already there
                current_url = workflow_data.get("current_url", "")
                if "chat" not in current_url:
                    await agent.navigate_to(f"{self.config.services['frontend'].url}/chat")
                
                # Send message
                message_input_selector = "#messageInput, [data-testid='message-input'], input[placeholder*='message']"
                send_button_selector = "#sendButton, [data-testid='send-button'], button[type='submit']"
                
                await agent.fill_input(message_input_selector, message)
                success = await agent.click_element(send_button_selector)
                
                if success:
                    # Wait for response
                    await asyncio.sleep(5)
                    
                    # Check for AI response
                    response_found = await self._check_for_ai_response(agent, result)
                    workflow_data["last_message"] = message
                    workflow_data["response_received"] = response_found
                    
                    return response_found
                
                return success
            
            elif step.action == "verify_element":
                selector = step.parameters.get("selector", "")
                visible = await agent.is_visible(selector)
                if visible:
                    result.add_log("info", f"Element verified: {selector}")
                else:
                    result.add_log("warning", f"Element not found: {selector}")
                return visible
            
            elif step.action == "take_screenshot":
                description = step.parameters.get("description", step.name)
                screenshot_path = await agent._take_screenshot(f"workflow_{step.step_id}")
                if screenshot_path:
                    result.add_screenshot(screenshot_path, description)
                    return True
                return False
            
            else:
                result.add_log("error", f"Unknown UI action: {step.action}")
                return False
        
        except Exception as e:
            result.add_log("error", f"UI step execution failed: {e}")
            return False
    
    async def _check_for_ai_response(self, agent: SyntheticUIAgent, result: TestResult) -> bool:
        """Check if AI response was received"""
        try:
            max_wait = 30  # seconds
            start_time = time.time()
            
            while time.time() - start_time < max_wait:
                ai_messages = await agent.page.query_selector_all(
                    ".message.assistant, [data-role='assistant'], .ai-message"
                )
                
                if ai_messages:
                    last_message = ai_messages[-1]
                    message_text = await last_message.text_content()
                    
                    if message_text and len(message_text) > 20:
                        result.add_log("info", f"AI response received: {message_text[:100]}...")
                        return True
                
                await asyncio.sleep(1)
            
            result.add_log("warning", "No AI response received within timeout")
            return False
        
        except Exception as e:
            result.add_log("error", f"Failed to check for AI response: {e}")
            return False
    
    async def _execute_api_step(self, step: WorkflowStep, result: TestResult, 
                              workflow_data: Dict[str, Any]) -> bool:
        """Execute an API-based step"""
        try:
            if step.action == "health_check":
                service_name = step.parameters.get("service", "api_gateway")
                tester = self.api_tester.testers.get(service_name)
                
                if not tester:
                    result.add_log("error", f"API tester not found: {service_name}")
                    return False
                
                health_result = await tester.test_health_check()
                workflow_data[f"{service_name}_health"] = health_result.status
                return health_result.status == "passed"
            
            elif step.action == "api_request":
                service_name = step.parameters.get("service", "api_gateway")
                endpoint = step.parameters.get("endpoint", "/api/health")
                method = step.parameters.get("method", "GET")
                
                tester = self.api_tester.testers.get(service_name)
                
                if not tester:
                    result.add_log("error", f"API tester not found: {service_name}")
                    return False
                
                response = await tester.client.request(method, endpoint)
                
                workflow_data["last_api_response"] = {
                    "status_code": response.status_code,
                    "response_time": response.response_time
                }
                
                return response.status_code == 200
            
            else:
                result.add_log("error", f"Unknown API action: {step.action}")
                return False
        
        except Exception as e:
            result.add_log("error", f"API step execution failed: {e}")
            return False
    
    async def _execute_external_api_step(self, step: WorkflowStep, result: TestResult, 
                                       workflow_data: Dict[str, Any]) -> bool:
        """Execute an external API step"""
        try:
            if step.action == "test_external_apis":
                external_results = await self.external_api_tester.run_comprehensive_external_api_tests()
                
                success_count = sum(1 for r in external_results if r.status == "passed")
                total_count = len(external_results)
                success_rate = success_count / total_count * 100 if total_count > 0 else 0
                
                workflow_data["external_api_results"] = {
                    "total_tests": total_count,
                    "passed_tests": success_count,
                    "success_rate": success_rate
                }
                
                result.add_log("info", f"External API tests: {success_count}/{total_count} passed ({success_rate:.1f}%)")
                
                return success_rate >= 75  # At least 75% should pass
            
            else:
                result.add_log("error", f"Unknown external API action: {step.action}")
                return False
        
        except Exception as e:
            result.add_log("error", f"External API step execution failed: {e}")
            return False
    
    async def _execute_data_step(self, step: WorkflowStep, result: TestResult, 
                               workflow_data: Dict[str, Any]) -> bool:
        """Execute a data management step"""
        try:
            if step.action == "create_test_environment":
                test_env_name = step.parameters.get("name", f"workflow_{uuid.uuid4().hex[:8]}")
                test_env = await self.data_manager.create_test_environment(test_env_name)
                
                workflow_data["test_environment"] = test_env
                result.add_log("info", f"Test environment created: {test_env_name}")
                
                return True
            
            elif step.action == "database_snapshot":
                snapshot_name = step.parameters.get("name", f"snapshot_{int(time.time())}")
                
                if self.data_manager.db_validator:
                    snapshot = await self.data_manager.db_validator.create_snapshot(snapshot_name)
                    workflow_data["database_snapshot"] = snapshot
                    result.add_log("info", f"Database snapshot created: {snapshot_name}")
                    return True
                else:
                    result.add_log("warning", "Database validator not available")
                    return False
            
            else:
                result.add_log("error", f"Unknown data action: {step.action}")
                return False
        
        except Exception as e:
            result.add_log("error", f"Data step execution failed: {e}")
            return False

class WorkflowScenarios:
    """Predefined workflow scenarios for common user journeys"""
    
    @staticmethod
    def get_new_user_onboarding_workflow() -> UserWorkflow:
        """Complete new user onboarding workflow"""
        return UserWorkflow(
            workflow_id="new_user_onboarding",
            name="New User Onboarding",
            description="Complete journey of a new user from first visit to data analysis",
            setup_steps=[
                WorkflowStep(
                    step_id="setup_environment",
                    name="Setup Test Environment",
                    description="Create test data and environment",
                    agent_type="data",
                    action="create_test_environment",
                    parameters={"name": "onboarding_test"}
                )
            ],
            steps=[
                WorkflowStep(
                    step_id="visit_homepage",
                    name="Visit Homepage",
                    description="Navigate to the PyAirtable homepage",
                    agent_type="ui",
                    action="navigate",
                    parameters={"url": ""},
                    expected_outcome="Homepage loads successfully"
                ),
                WorkflowStep(
                    step_id="screenshot_homepage",
                    name="Capture Homepage",
                    description="Take screenshot of homepage",
                    agent_type="ui",
                    action="take_screenshot",
                    parameters={"description": "Homepage initial load"},
                    critical=False
                ),
                WorkflowStep(
                    step_id="navigate_to_chat",
                    name="Navigate to Chat",
                    description="Navigate to the chat interface",
                    agent_type="ui",
                    action="navigate",
                    parameters={"url": "/chat"},
                    expected_outcome="Chat interface loads"
                ),
                WorkflowStep(
                    step_id="first_message",
                    name="Send First Message",
                    description="Send a welcome message to test basic functionality",
                    agent_type="ui",
                    action="send_message",
                    parameters={"message": "Hello! I'm a new user. Can you help me understand what PyAirtable can do?"},
                    expected_outcome="AI responds with helpful information"
                ),
                WorkflowStep(
                    step_id="explore_airtable_data",
                    name="Explore Airtable Data",
                    description="Ask to explore Airtable data",
                    agent_type="ui",
                    action="send_message",
                    parameters={"message": "Can you show me what tables are available in my Airtable base?"},
                    expected_outcome="AI provides information about available tables"
                ),
                WorkflowStep(
                    step_id="request_data_analysis",
                    name="Request Data Analysis",
                    description="Request analysis of specific data",
                    agent_type="ui",
                    action="send_message",
                    parameters={"message": "Please analyze my project data and provide insights about project status and budgets"},
                    expected_outcome="AI provides detailed data analysis"
                ),
                WorkflowStep(
                    step_id="final_screenshot",
                    name="Capture Final State",
                    description="Take final screenshot of the chat session",
                    agent_type="ui",
                    action="take_screenshot",
                    parameters={"description": "Completed onboarding session"},
                    critical=False
                )
            ],
            tags=["onboarding", "ui", "chat", "data_analysis"],
            estimated_duration=300
        )
    
    @staticmethod
    def get_data_analysis_workflow() -> UserWorkflow:
        """Advanced data analysis workflow"""
        return UserWorkflow(
            workflow_id="advanced_data_analysis",
            name="Advanced Data Analysis",
            description="Power user workflow for complex data analysis tasks",
            setup_steps=[
                WorkflowStep(
                    step_id="api_health_check",
                    name="API Health Check",
                    description="Verify all APIs are healthy",
                    agent_type="api",
                    action="health_check",
                    parameters={"service": "api_gateway"}
                ),
                WorkflowStep(
                    step_id="external_api_check",
                    name="External API Check",
                    description="Verify external APIs are working",
                    agent_type="external_api",
                    action="test_external_apis"
                )
            ],
            steps=[
                WorkflowStep(
                    step_id="navigate_to_chat",
                    name="Open Chat Interface",
                    description="Navigate to chat for data analysis",
                    agent_type="ui",
                    action="navigate",
                    parameters={"url": "/chat"},
                    expected_outcome="Chat interface ready"
                ),
                WorkflowStep(
                    step_id="table_overview",
                    name="Get Table Overview",
                    description="Request comprehensive table overview",
                    agent_type="ui",
                    action="send_message",
                    parameters={"message": "Please provide a comprehensive overview of all tables in my Airtable base, including record counts and key fields"},
                    expected_outcome="Detailed table overview provided"
                ),
                WorkflowStep(
                    step_id="project_analysis",
                    name="Analyze Projects",
                    description="Deep analysis of project data",
                    agent_type="ui",
                    action="send_message",
                    parameters={"message": "Analyze all projects: calculate total budgets, group by status, identify overdue projects, and provide recommendations"},
                    expected_outcome="Comprehensive project analysis"
                ),
                WorkflowStep(
                    step_id="financial_summary",
                    name="Financial Summary",
                    description="Generate financial summary",
                    agent_type="ui",
                    action="send_message",
                    parameters={"message": "Create a financial summary showing total project costs, budget utilization, and cost trends over time"},
                    expected_outcome="Financial summary generated"
                ),
                WorkflowStep(
                    step_id="data_export_request",
                    name="Request Data Export",
                    description="Request data in exportable format",
                    agent_type="ui",
                    action="send_message",
                    parameters={"message": "Can you format the project analysis results as a JSON report that I can export?"},
                    expected_outcome="Structured data provided"
                ),
                WorkflowStep(
                    step_id="workflow_screenshot",
                    name="Document Analysis Results",
                    description="Capture the analysis results",
                    agent_type="ui",
                    action="take_screenshot",
                    parameters={"description": "Advanced data analysis results"},
                    critical=False
                )
            ],
            tags=["data_analysis", "advanced", "projects", "financial"],
            estimated_duration=420
        )
    
    @staticmethod
    def get_system_integration_workflow() -> UserWorkflow:
        """System integration and reliability workflow"""
        return UserWorkflow(
            workflow_id="system_integration",
            name="System Integration Test",
            description="Comprehensive test of system integration and reliability",
            setup_steps=[
                WorkflowStep(
                    step_id="database_snapshot",
                    name="Create Database Snapshot",
                    description="Create initial database snapshot",
                    agent_type="data",
                    action="database_snapshot",
                    parameters={"name": "integration_test_before"}
                )
            ],
            steps=[
                WorkflowStep(
                    step_id="api_gateway_health",
                    name="Test API Gateway",
                    description="Verify API Gateway health and routing",
                    agent_type="api",
                    action="health_check",
                    parameters={"service": "api_gateway"},
                    expected_outcome="API Gateway healthy"
                ),
                WorkflowStep(
                    step_id="llm_orchestrator_health",
                    name="Test LLM Orchestrator",
                    description="Verify LLM Orchestrator health",
                    agent_type="api",
                    action="health_check",
                    parameters={"service": "llm_orchestrator"},
                    expected_outcome="LLM Orchestrator healthy"
                ),
                WorkflowStep(
                    step_id="airtable_gateway_health",
                    name="Test Airtable Gateway",
                    description="Verify Airtable Gateway health",
                    agent_type="api",
                    action="health_check",
                    parameters={"service": "airtable_gateway"},
                    expected_outcome="Airtable Gateway healthy"
                ),
                WorkflowStep(
                    step_id="mcp_server_health",
                    name="Test MCP Server",
                    description="Verify MCP Server health",
                    agent_type="api",
                    action="health_check",
                    parameters={"service": "mcp_server"},
                    expected_outcome="MCP Server healthy"
                ),
                WorkflowStep(
                    step_id="frontend_integration",
                    name="Test Frontend Integration",
                    description="Test frontend to backend integration",
                    agent_type="ui",
                    action="navigate",
                    parameters={"url": "/chat"},
                    expected_outcome="Frontend loads and connects to backend"
                ),
                WorkflowStep(
                    step_id="end_to_end_flow",
                    name="End-to-End Data Flow",
                    description="Test complete data flow from UI to Airtable",
                    agent_type="ui",
                    action="send_message",
                    parameters={"message": "Test message: Please fetch and analyze data from my Airtable base to verify the complete data flow"},
                    expected_outcome="Data successfully flows through all systems"
                ),
                WorkflowStep(
                    step_id="external_api_integration",
                    name="External API Integration",
                    description="Test external API integrations",
                    agent_type="external_api",
                    action="test_external_apis",
                    expected_outcome="External APIs accessible and functional"
                ),
                WorkflowStep(
                    step_id="integration_screenshot",
                    name="Document Integration Test",
                    description="Capture integration test results",
                    agent_type="ui",
                    action="take_screenshot",
                    parameters={"description": "System integration test results"},
                    critical=False
                )
            ],
            cleanup_steps=[
                WorkflowStep(
                    step_id="final_database_snapshot",
                    name="Final Database Snapshot",
                    description="Create final database snapshot",
                    agent_type="data",
                    action="database_snapshot",
                    parameters={"name": "integration_test_after"}
                )
            ],
            tags=["integration", "system", "reliability", "api"],
            estimated_duration=360
        )
    
    @staticmethod
    def get_performance_stress_workflow() -> UserWorkflow:
        """Performance and stress testing workflow"""
        return UserWorkflow(
            workflow_id="performance_stress",
            name="Performance and Stress Test",
            description="Test system performance under load and stress conditions",
            steps=[
                WorkflowStep(
                    step_id="baseline_performance",
                    name="Baseline Performance",
                    description="Establish baseline performance metrics",
                    agent_type="ui",
                    action="navigate",
                    parameters={"url": "/chat"},
                    expected_outcome="Normal page load time recorded"
                ),
                WorkflowStep(
                    step_id="simple_query_performance",
                    name="Simple Query Performance",
                    description="Test performance of simple queries",
                    agent_type="ui",
                    action="send_message",
                    parameters={"message": "What is 2+2?"},
                    expected_outcome="Quick response to simple query"
                ),
                WorkflowStep(
                    step_id="complex_query_performance",
                    name="Complex Query Performance",
                    description="Test performance of complex data queries",
                    agent_type="ui",
                    action="send_message",
                    parameters={"message": "Analyze all my Airtable data across all tables, calculate totals, averages, and trends, then provide a comprehensive report with recommendations"},
                    expected_outcome="Complex query handled within reasonable time"
                ),
                WorkflowStep(
                    step_id="concurrent_api_stress",
                    name="Concurrent API Stress",
                    description="Test API under concurrent load",
                    agent_type="api",
                    action="api_request",
                    parameters={"service": "api_gateway", "endpoint": "/api/health", "method": "GET"},
                    expected_outcome="API handles concurrent requests"
                ),
                WorkflowStep(
                    step_id="memory_usage_check",
                    name="Memory Usage Check",
                    description="Monitor system memory usage",
                    agent_type="ui",
                    action="take_screenshot",
                    parameters={"description": "System state during stress test"},
                    critical=False
                )
            ],
            tags=["performance", "stress", "load", "monitoring"],
            estimated_duration=480
        )
    
    @staticmethod
    def get_all_workflows() -> List[UserWorkflow]:
        """Get all predefined workflows"""
        return [
            WorkflowScenarios.get_new_user_onboarding_workflow(),
            WorkflowScenarios.get_data_analysis_workflow(),
            WorkflowScenarios.get_system_integration_workflow(),
            WorkflowScenarios.get_performance_stress_workflow()
        ]

class WorkflowTestOrchestrator:
    """Orchestrates execution of multiple user workflow scenarios"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.workflow_executor: Optional[WorkflowExecutor] = None
        self.workflow_results: Dict[str, TestResult] = {}
    
    async def run_all_workflows(self, workflows: List[UserWorkflow] = None) -> Dict[str, TestResult]:
        """Run all workflow scenarios"""
        if workflows is None:
            workflows = WorkflowScenarios.get_all_workflows()
        
        logger.info(f"Starting execution of {len(workflows)} user workflow scenarios")
        
        async with WorkflowExecutor(self.config) as executor:
            self.workflow_executor = executor
            
            for workflow in workflows:
                logger.info(f"Executing workflow: {workflow.name}")
                
                try:
                    workflow_result = await executor.execute_workflow(workflow)
                    self.workflow_results[workflow.workflow_id] = workflow_result
                    
                    status_emoji = "✅" if workflow_result.status == "passed" else "❌"
                    logger.info(f"{status_emoji} Workflow completed: {workflow.name} - {workflow_result.status}")
                    
                except Exception as e:
                    logger.error(f"Workflow execution failed: {workflow.name} - {e}")
                    
                    # Create error result
                    error_result = TestResult("Workflow Executor", workflow.name)
                    error_result.add_log("error", f"Workflow execution failed: {e}")
                    error_result.complete("failed")
                    self.workflow_results[workflow.workflow_id] = error_result
        
        # Log summary
        total_workflows = len(workflows)
        passed_workflows = sum(1 for result in self.workflow_results.values() if result.status == "passed")
        success_rate = passed_workflows / total_workflows * 100 if total_workflows > 0 else 0
        
        logger.info(f"Workflow execution summary: {passed_workflows}/{total_workflows} passed ({success_rate:.1f}%)")
        
        return self.workflow_results
    
    async def run_specific_workflows(self, workflow_ids: List[str]) -> Dict[str, TestResult]:
        """Run specific workflow scenarios by ID"""
        all_workflows = WorkflowScenarios.get_all_workflows()
        selected_workflows = [wf for wf in all_workflows if wf.workflow_id in workflow_ids]
        
        if not selected_workflows:
            logger.warning(f"No workflows found matching IDs: {workflow_ids}")
            return {}
        
        return await self.run_all_workflows(selected_workflows)
    
    def get_workflow_summary(self) -> Dict[str, Any]:
        """Get summary of workflow execution results"""
        if not self.workflow_results:
            return {"error": "No workflow results available"}
        
        total = len(self.workflow_results)
        passed = sum(1 for result in self.workflow_results.values() if result.status == "passed")
        failed = sum(1 for result in self.workflow_results.values() if result.status == "failed")
        
        # Calculate total duration
        total_duration = sum(result.duration for result in self.workflow_results.values())
        
        # Count issues by severity
        severity_counts = {"critical": 0, "high": 0, "medium": 0, "low": 0}
        for result in self.workflow_results.values():
            for issue in result.issues_found:
                severity = issue.get("severity", "medium")
                if severity in severity_counts:
                    severity_counts[severity] += 1
        
        return {
            "total_workflows": total,
            "passed_workflows": passed,
            "failed_workflows": failed,
            "success_rate": passed / total * 100 if total > 0 else 0,
            "total_duration": total_duration,
            "avg_duration": total_duration / total if total > 0 else 0,
            "issues_by_severity": severity_counts,
            "workflow_details": {
                workflow_id: {
                    "name": result.test_name,
                    "status": result.status,
                    "duration": result.duration,
                    "issues_count": len(result.issues_found)
                }
                for workflow_id, result in self.workflow_results.items()
            }
        }