#!/usr/bin/env python3
"""
Sprint 2 Comprehensive Test Runner
==================================

Master test runner that orchestrates both automated and manual testing
for the complete Sprint 2 integration validation.

Author: QA Automation Engineer
Version: 1.0.0
"""

import asyncio
import json
import logging
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any
import aiohttp
import shutil

# Import our test suites
try:
    from sprint2_e2e_test_suite import Sprint2TestSuite
    from sprint2_manual_test_scenarios import Sprint2ManualTestRunner
except ImportError as e:
    print(f"Error importing test modules: {e}")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'sprint2_comprehensive_test_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class Sprint2ComprehensiveTestRunner:
    """Comprehensive test runner for Sprint 2 validation"""
    
    def __init__(self):
        self.start_time = time.time()
        self.timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Test components
        self.e2e_test_suite = Sprint2TestSuite()
        self.manual_test_runner = Sprint2ManualTestRunner()
        
        # Results storage
        self.results = {
            "execution_info": {
                "timestamp": datetime.now().isoformat(),
                "test_environment": "Sprint 2 Integration",
                "runner_version": "1.0.0"
            },
            "automated_tests": {},
            "manual_test_guidance": {},
            "service_validation": {},
            "performance_analysis": {},
            "integration_assessment": {},
            "recommendations": [],
            "deliverables": []
        }
        
        # Service configurations
        self.services = {
            "chat_ui": {"url": "http://localhost:3001", "port": 3001, "name": "Chat UI"},
            "api_gateway": {"url": "http://localhost:8000", "port": 8000, "name": "API Gateway"},
            "airtable_gateway": {"url": "http://localhost:8002", "port": 8002, "name": "Airtable Gateway"},
            "mcp_server": {"url": "http://localhost:8001", "port": 8001, "name": "MCP Server"},
            "llm_orchestrator": {"url": "http://localhost:8003", "port": 8003, "name": "LLM Orchestrator"}
        }
        
    async def run_comprehensive_test_suite(self) -> Dict[str, Any]:
        """Run the complete comprehensive test suite"""
        logger.info("="*80)
        logger.info("SPRINT 2 COMPREHENSIVE TEST SUITE")
        logger.info("="*80)
        logger.info("Starting comprehensive validation of Sprint 2 integration stack...")
        
        try:
            # Phase 1: Pre-test Service Validation
            logger.info("\n📋 PHASE 1: Pre-test Service Validation")
            await self.validate_test_environment()
            
            # Phase 2: Automated E2E Testing
            logger.info("\n🤖 PHASE 2: Automated E2E Testing")
            await self.run_automated_tests()
            
            # Phase 3: Manual Test Guidance Generation
            logger.info("\n👤 PHASE 3: Manual Test Guidance Generation")
            await self.generate_manual_test_guidance()
            
            # Phase 4: Performance Analysis
            logger.info("\n⚡ PHASE 4: Performance Analysis")
            await self.analyze_performance_metrics()
            
            # Phase 5: Integration Assessment
            logger.info("\n🔗 PHASE 5: Integration Assessment")
            await self.assess_integration_health()
            
            # Phase 6: Generate Recommendations
            logger.info("\n💡 PHASE 6: Generate Recommendations")
            await self.generate_recommendations()
            
            # Phase 7: Create Deliverables
            logger.info("\n📄 PHASE 7: Create Deliverables")
            await self.create_test_deliverables()
            
        except Exception as e:
            logger.error(f"Comprehensive test suite failed: {e}")
            self.results["execution_info"]["error"] = str(e)
        
        # Calculate total execution time
        total_duration = time.time() - self.start_time
        self.results["execution_info"]["total_duration"] = total_duration
        
        # Generate final report
        final_report = await self.generate_final_report()
        
        return final_report
    
    async def validate_test_environment(self):
        """Validate that the test environment is ready"""
        logger.info("Validating test environment...")
        
        validation_results = {
            "service_health": {},
            "dependencies_check": {},
            "test_data_availability": {},
            "environment_readiness": True
        }
        
        # Check service health
        async with aiohttp.ClientSession() as session:
            for service_name, config in self.services.items():
                try:
                    async with session.get(f"{config['url']}/health", timeout=5) as response:
                        if response.status == 200:
                            validation_results["service_health"][service_name] = "HEALTHY"
                            logger.info(f"✓ {config['name']} is healthy")
                        else:
                            validation_results["service_health"][service_name] = f"UNHEALTHY_HTTP_{response.status}"
                            logger.warning(f"⚠️ {config['name']} returned HTTP {response.status}")
                            validation_results["environment_readiness"] = False
                except Exception as e:
                    validation_results["service_health"][service_name] = f"UNAVAILABLE: {str(e)}"
                    logger.error(f"✗ {config['name']} is unavailable: {e}")
                    validation_results["environment_readiness"] = False
        
        # Check required dependencies
        dependencies = ["playwright", "aiohttp", "websockets"]
        for dep in dependencies:
            try:
                __import__(dep)
                validation_results["dependencies_check"][dep] = "AVAILABLE"
                logger.info(f"✓ {dep} is available")
            except ImportError:
                validation_results["dependencies_check"][dep] = "MISSING"
                logger.error(f"✗ {dep} is missing")
                validation_results["environment_readiness"] = False
        
        # Check test data availability (ports, connectivity)
        for service_name, config in self.services.items():
            try:
                # Use a simple TCP connection test
                import socket
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(2)
                result = sock.connect_ex(('localhost', config['port']))
                sock.close()
                
                if result == 0:
                    validation_results["test_data_availability"][service_name] = "PORT_ACCESSIBLE"
                else:
                    validation_results["test_data_availability"][service_name] = "PORT_INACCESSIBLE"
                    validation_results["environment_readiness"] = False
            except Exception as e:
                validation_results["test_data_availability"][service_name] = f"CONNECTION_ERROR: {e}"
                validation_results["environment_readiness"] = False
        
        self.results["service_validation"] = validation_results
        
        if not validation_results["environment_readiness"]:
            logger.error("❌ Test environment is not ready. Please fix the issues above before proceeding.")
            return False
        
        logger.info("✅ Test environment validation completed successfully")
        return True
    
    async def run_automated_tests(self):
        """Run the automated E2E test suite"""
        logger.info("Executing automated E2E test suite...")
        
        try:
            # Run the automated test suite
            automated_results = await self.e2e_test_suite.run_full_test_suite()
            self.results["automated_tests"] = automated_results
            
            # Log summary
            total_tests = automated_results.get("test_execution", {}).get("total_tests", 0)
            passed_tests = automated_results.get("test_execution", {}).get("passed", 0)
            failed_tests = automated_results.get("test_execution", {}).get("failed", 0)
            pass_rate = automated_results.get("test_execution", {}).get("pass_rate", 0)
            
            logger.info(f"Automated tests completed:")
            logger.info(f"  Total: {total_tests}, Passed: {passed_tests}, Failed: {failed_tests}")
            logger.info(f"  Pass Rate: {pass_rate:.1f}%")
            
            if failed_tests > 0:
                logger.warning(f"⚠️ {failed_tests} automated tests failed")
                for failed_test in automated_results.get("failed_tests", []):
                    logger.warning(f"   - {failed_test['test_name']}: {failed_test['error_message']}")
            
        except Exception as e:
            logger.error(f"Automated tests failed to execute: {e}")
            self.results["automated_tests"] = {"error": str(e)}
    
    async def generate_manual_test_guidance(self):
        """Generate comprehensive manual test guidance"""
        logger.info("Generating manual test guidance...")
        
        try:
            manual_guidance = await self.manual_test_runner.run_manual_test_guidance()
            self.results["manual_test_guidance"] = manual_guidance
            
            total_scenarios = manual_guidance.get("execution_info", {}).get("total_scenarios", 0)
            estimated_duration = manual_guidance.get("execution_info", {}).get("estimated_duration", "Unknown")
            
            logger.info(f"Manual test guidance generated:")
            logger.info(f"  Scenarios: {total_scenarios}")
            logger.info(f"  Estimated Duration: {estimated_duration}")
            
            # Check service availability for manual tests
            unavailable_services = []
            for service, status in manual_guidance.get("service_status", {}).items():
                if status != "AVAILABLE":
                    unavailable_services.append(service)
            
            if unavailable_services:
                logger.warning(f"⚠️ Some services unavailable for manual testing: {', '.join(unavailable_services)}")
            
        except Exception as e:
            logger.error(f"Manual test guidance generation failed: {e}")
            self.results["manual_test_guidance"] = {"error": str(e)}
    
    async def analyze_performance_metrics(self):
        """Analyze performance metrics from automated tests"""
        logger.info("Analyzing performance metrics...")
        
        automated_results = self.results.get("automated_tests", {})
        performance_metrics = automated_results.get("performance_metrics", {})
        
        analysis = {
            "response_time_analysis": {},
            "performance_targets": {
                "chat_response_time": 2.0,
                "airtable_api_response": 0.5,
                "websocket_connection": 1.0
            },
            "performance_status": "UNKNOWN",
            "bottlenecks_identified": [],
            "recommendations": []
        }
        
        # Analyze chat response time
        chat_response_time = performance_metrics.get("chat_response_time")
        if chat_response_time:
            target = analysis["performance_targets"]["chat_response_time"]
            analysis["response_time_analysis"]["chat"] = {
                "actual": chat_response_time,
                "target": target,
                "status": "PASS" if chat_response_time <= target else "FAIL",
                "variance": ((chat_response_time - target) / target * 100) if target > 0 else 0
            }
            
            if chat_response_time > target:
                analysis["bottlenecks_identified"].append(f"Chat response time ({chat_response_time:.2f}s) exceeds target ({target}s)")
        
        # Analyze Airtable API response time
        airtable_response_time = performance_metrics.get("airtable_api_response")
        if airtable_response_time:
            target = analysis["performance_targets"]["airtable_api_response"]
            analysis["response_time_analysis"]["airtable"] = {
                "actual": airtable_response_time,
                "target": target,
                "status": "PASS" if airtable_response_time <= target else "FAIL",
                "variance": ((airtable_response_time - target) / target * 100) if target > 0 else 0
            }
            
            if airtable_response_time > target:
                analysis["bottlenecks_identified"].append(f"Airtable API response time ({airtable_response_time:.2f}s) exceeds target ({target}s)")
        
        # Analyze concurrent users
        concurrent_success_rate = performance_metrics.get("concurrent_users_success_rate")
        if concurrent_success_rate:
            analysis["concurrent_users"] = {
                "success_rate": concurrent_success_rate,
                "target": 0.95,
                "status": "PASS" if concurrent_success_rate >= 0.95 else "FAIL"
            }
            
            if concurrent_success_rate < 0.95:
                analysis["bottlenecks_identified"].append(f"Concurrent users success rate ({concurrent_success_rate:.2%}) below 95% target")
        
        # Determine overall performance status
        response_statuses = [metrics.get("status", "UNKNOWN") for metrics in analysis["response_time_analysis"].values()]
        if all(status == "PASS" for status in response_statuses) and len(response_statuses) > 0:
            analysis["performance_status"] = "PASS"
        elif any(status == "FAIL" for status in response_statuses):
            analysis["performance_status"] = "FAIL"
        else:
            analysis["performance_status"] = "INSUFFICIENT_DATA"
        
        # Generate performance recommendations
        if analysis["bottlenecks_identified"]:
            analysis["recommendations"].extend([
                "Investigate and optimize slow response components",
                "Consider implementing caching strategies",
                "Review database query optimization",
                "Analyze network latency and connection pooling"
            ])
        else:
            analysis["recommendations"].append("Performance targets are being met")
        
        self.results["performance_analysis"] = analysis
        
        logger.info(f"Performance analysis completed:")
        logger.info(f"  Overall Status: {analysis['performance_status']}")
        if analysis["bottlenecks_identified"]:
            logger.info(f"  Bottlenecks: {len(analysis['bottlenecks_identified'])} identified")
    
    async def assess_integration_health(self):
        """Assess the overall health of Sprint 2 integrations"""
        logger.info("Assessing integration health...")
        
        automated_results = self.results.get("automated_tests", {})
        integration_status = automated_results.get("integration_status", {})
        service_health = self.results.get("service_validation", {}).get("service_health", {})
        
        assessment = {
            "overall_health": "UNKNOWN",
            "component_health": {},
            "integration_points": {},
            "critical_issues": [],
            "recommendations": []
        }
        
        # Assess component health
        for service_name, health_status in service_health.items():
            if health_status == "HEALTHY":
                assessment["component_health"][service_name] = "HEALTHY"
            else:
                assessment["component_health"][service_name] = "UNHEALTHY"
                assessment["critical_issues"].append(f"{service_name} service is unhealthy: {health_status}")
        
        # Assess integration points
        integration_points = {
            "chat_ui_to_backend": integration_status.get("chat_ui", False),
            "auth_integration": integration_status.get("authentication", False),
            "mcp_tools_integration": integration_status.get("mcp_tools", False),
            "airtable_crud": integration_status.get("airtable_crud", False),
            "websocket_communication": integration_status.get("websocket", False),
            "file_processing": integration_status.get("file_upload", False)
        }
        
        for integration_point, status in integration_points.items():
            assessment["integration_points"][integration_point] = "WORKING" if status else "BROKEN"
            if not status:
                assessment["critical_issues"].append(f"{integration_point.replace('_', ' ').title()} integration is not working")
        
        # Determine overall health
        healthy_services = sum(1 for status in assessment["component_health"].values() if status == "HEALTHY")
        total_services = len(assessment["component_health"])
        working_integrations = sum(1 for status in assessment["integration_points"].values() if status == "WORKING")
        total_integrations = len(assessment["integration_points"])
        
        service_health_rate = healthy_services / total_services if total_services > 0 else 0
        integration_health_rate = working_integrations / total_integrations if total_integrations > 0 else 0
        
        if service_health_rate >= 0.8 and integration_health_rate >= 0.8:
            assessment["overall_health"] = "HEALTHY"
        elif service_health_rate >= 0.6 and integration_health_rate >= 0.6:
            assessment["overall_health"] = "DEGRADED"
        else:
            assessment["overall_health"] = "UNHEALTHY"
        
        # Generate integration recommendations
        if assessment["critical_issues"]:
            assessment["recommendations"].extend([
                "Address critical service health issues before production",
                "Fix broken integration points",
                "Implement comprehensive monitoring for all integration points"
            ])
        
        if assessment["overall_health"] in ["HEALTHY", "DEGRADED"]:
            assessment["recommendations"].append("Consider implementing automated health checks")
        
        self.results["integration_assessment"] = assessment
        
        logger.info(f"Integration health assessment completed:")
        logger.info(f"  Overall Health: {assessment['overall_health']}")
        logger.info(f"  Service Health Rate: {service_health_rate:.1%}")
        logger.info(f"  Integration Health Rate: {integration_health_rate:.1%}")
        
        if assessment["critical_issues"]:
            logger.warning(f"  Critical Issues: {len(assessment['critical_issues'])} identified")
    
    async def generate_recommendations(self):
        """Generate comprehensive recommendations based on all test results"""
        logger.info("Generating comprehensive recommendations...")
        
        recommendations = []
        
        # Service health recommendations
        service_health = self.results.get("service_validation", {}).get("service_health", {})
        unhealthy_services = [name for name, status in service_health.items() if status != "HEALTHY"]
        if unhealthy_services:
            recommendations.append({
                "category": "Service Health",
                "priority": "CRITICAL",
                "issue": f"Unhealthy services: {', '.join(unhealthy_services)}",
                "recommendation": "Fix service health issues before proceeding to production deployment",
                "action_items": [
                    "Investigate service startup issues",
                    "Check service dependencies and configuration", 
                    "Verify network connectivity between services",
                    "Review service logs for error details"
                ]
            })
        
        # Automated test recommendations
        automated_results = self.results.get("automated_tests", {})
        failed_tests = automated_results.get("test_execution", {}).get("failed", 0)
        if failed_tests > 0:
            recommendations.append({
                "category": "Automated Testing", 
                "priority": "HIGH",
                "issue": f"{failed_tests} automated tests are failing",
                "recommendation": "Address failing automated tests to ensure system stability",
                "action_items": [
                    "Review failed test error messages",
                    "Fix underlying service or integration issues",
                    "Update test expectations if business logic has changed",
                    "Ensure test environment matches production configuration"
                ]
            })
        
        # Performance recommendations
        performance_analysis = self.results.get("performance_analysis", {})
        if performance_analysis.get("performance_status") == "FAIL":
            recommendations.append({
                "category": "Performance",
                "priority": "HIGH", 
                "issue": "Performance targets not being met",
                "recommendation": "Optimize system performance before production deployment",
                "action_items": [
                    "Profile application performance bottlenecks",
                    "Implement caching strategies where appropriate",
                    "Optimize database queries and connection pooling",
                    "Consider implementing async processing for long-running operations"
                ]
            })
        
        # Integration recommendations
        integration_assessment = self.results.get("integration_assessment", {})
        if integration_assessment.get("overall_health") in ["UNHEALTHY", "DEGRADED"]:
            recommendations.append({
                "category": "Integration Health",
                "priority": "CRITICAL" if integration_assessment.get("overall_health") == "UNHEALTHY" else "HIGH",
                "issue": f"Integration health is {integration_assessment.get('overall_health', 'UNKNOWN').lower()}",
                "recommendation": "Fix integration issues to ensure reliable system operation",
                "action_items": [
                    "Investigate broken integration points",
                    "Verify service-to-service communication",
                    "Check authentication and authorization flows",
                    "Implement robust error handling and retry mechanisms"
                ]
            })
        
        # Manual testing recommendations
        manual_guidance = self.results.get("manual_test_guidance", {})
        if manual_guidance.get("service_status"):
            unavailable_services = [s for s, status in manual_guidance.get("service_status", {}).items() if status != "AVAILABLE"]
            if unavailable_services:
                recommendations.append({
                    "category": "Manual Testing",
                    "priority": "MEDIUM",
                    "issue": f"Some services unavailable for manual testing: {', '.join(unavailable_services)}",
                    "recommendation": "Ensure all services are available for comprehensive manual testing",
                    "action_items": [
                        "Start all required services",
                        "Verify service configuration",
                        "Execute complete manual test suite", 
                        "Document any additional issues found during manual testing"
                    ]
                })
        
        # General recommendations for Sprint 2 readiness
        if not recommendations:
            recommendations.append({
                "category": "Production Readiness",
                "priority": "LOW",
                "issue": "No critical issues detected",
                "recommendation": "System appears ready for production deployment",
                "action_items": [
                    "Complete manual testing scenarios",
                    "Set up production monitoring and alerting",
                    "Prepare rollback procedures",
                    "Document operational runbooks"
                ]
            })
        else:
            recommendations.append({
                "category": "Production Readiness",
                "priority": "HIGH",
                "issue": "Multiple issues detected",
                "recommendation": "Address identified issues before production deployment",
                "action_items": [
                    "Prioritize critical and high priority issues",
                    "Create action plan with assigned owners and deadlines",
                    "Re-run comprehensive tests after fixes",
                    "Consider staged deployment approach"
                ]
            })
        
        self.results["recommendations"] = recommendations
        
        logger.info(f"Generated {len(recommendations)} recommendation categories")
        for rec in recommendations:
            logger.info(f"  {rec['priority']}: {rec['category']} - {rec['issue']}")
    
    async def create_test_deliverables(self):
        """Create comprehensive test deliverables"""
        logger.info("Creating test deliverables...")
        
        deliverables = []
        
        # Create deliverables directory
        deliverables_dir = Path(f"sprint2_test_deliverables_{self.timestamp}")
        deliverables_dir.mkdir(exist_ok=True)
        
        # 1. Comprehensive Test Report (JSON)
        comprehensive_report_path = deliverables_dir / "comprehensive_test_report.json"
        with open(comprehensive_report_path, 'w') as f:
            json.dump(self.results, f, indent=2, default=str)
        deliverables.append(str(comprehensive_report_path))
        
        # 2. Executive Summary (Markdown)
        executive_summary_path = deliverables_dir / "executive_summary.md"
        with open(executive_summary_path, 'w') as f:
            f.write(self.generate_executive_summary_markdown())
        deliverables.append(str(executive_summary_path))
        
        # 3. Manual Test Scenarios (JSON)
        if self.results.get("manual_test_guidance"):
            manual_test_path = deliverables_dir / "manual_test_scenarios.json"
            with open(manual_test_path, 'w') as f:
                json.dump(self.results["manual_test_guidance"], f, indent=2, default=str)
            deliverables.append(str(manual_test_path))
        
        # 4. Failed Tests Report (if any failures)
        automated_results = self.results.get("automated_tests", {})
        if automated_results.get("failed_tests"):
            failed_tests_path = deliverables_dir / "failed_tests_report.json"
            with open(failed_tests_path, 'w') as f:
                json.dump({
                    "summary": {
                        "total_failed": len(automated_results["failed_tests"]),
                        "timestamp": datetime.now().isoformat()
                    },
                    "failed_tests": automated_results["failed_tests"]
                }, f, indent=2)
            deliverables.append(str(failed_tests_path))
        
        # 5. Performance Analysis Report
        if self.results.get("performance_analysis"):
            performance_report_path = deliverables_dir / "performance_analysis.json"
            with open(performance_report_path, 'w') as f:
                json.dump(self.results["performance_analysis"], f, indent=2)
            deliverables.append(str(performance_report_path))
        
        # 6. Action Plan (based on recommendations)
        action_plan_path = deliverables_dir / "action_plan.md"
        with open(action_plan_path, 'w') as f:
            f.write(self.generate_action_plan_markdown())
        deliverables.append(str(action_plan_path))
        
        self.results["deliverables"] = deliverables
        
        logger.info(f"Created {len(deliverables)} test deliverables in {deliverables_dir}")
        for deliverable in deliverables:
            logger.info(f"  📄 {deliverable}")
    
    def generate_executive_summary_markdown(self) -> str:
        """Generate executive summary in markdown format"""
        automated_results = self.results.get("automated_tests", {})
        integration_assessment = self.results.get("integration_assessment", {})
        performance_analysis = self.results.get("performance_analysis", {})
        
        total_tests = automated_results.get("test_execution", {}).get("total_tests", 0)
        passed_tests = automated_results.get("test_execution", {}).get("passed", 0)
        failed_tests = automated_results.get("test_execution", {}).get("failed", 0)
        pass_rate = automated_results.get("test_execution", {}).get("pass_rate", 0)
        
        overall_health = integration_assessment.get("overall_health", "UNKNOWN")
        performance_status = performance_analysis.get("performance_status", "UNKNOWN")
        
        recommendations_count = len(self.results.get("recommendations", []))
        critical_recommendations = len([r for r in self.results.get("recommendations", []) if r.get("priority") == "CRITICAL"])
        
        summary = f"""# Sprint 2 Integration Test - Executive Summary
        
## Test Execution Overview
- **Test Date:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
- **Test Environment:** Sprint 2 Local Development
- **Total Test Duration:** {self.results.get('execution_info', {}).get('total_duration', 0):.2f} seconds
        
## Automated Test Results
- **Total Tests Executed:** {total_tests}
- **Tests Passed:** {passed_tests}
- **Tests Failed:** {failed_tests}
- **Pass Rate:** {pass_rate:.1f}%
        
## Integration Health Assessment
- **Overall Health Status:** {overall_health}
- **Performance Status:** {performance_status}
        
## Key Findings
        
### ✅ Successes
"""
        
        if pass_rate >= 80:
            summary += "- Automated test suite shows good overall stability\n"
        if overall_health == "HEALTHY":
            summary += "- All integration points are functioning correctly\n"
        if performance_status == "PASS":
            summary += "- Performance targets are being met\n"
        
        summary += "\n### ❌ Issues Identified\n"
        
        if failed_tests > 0:
            summary += f"- {failed_tests} automated tests are failing\n"
        if overall_health in ["UNHEALTHY", "DEGRADED"]:
            summary += f"- Integration health is {overall_health.lower()}\n"
        if performance_status == "FAIL":
            summary += "- Performance targets are not being met\n"
        
        summary += f"""
## Recommendations Summary
- **Total Recommendations:** {recommendations_count}
- **Critical Priority:** {critical_recommendations}
        
## Next Steps
1. Address critical and high priority recommendations
2. Execute manual test scenarios
3. Re-run automated tests after fixes
4. Plan production deployment based on results
        
---
*This summary was generated automatically by the Sprint 2 Comprehensive Test Runner*
"""
        
        return summary
    
    def generate_action_plan_markdown(self) -> str:
        """Generate action plan based on recommendations"""
        recommendations = self.results.get("recommendations", [])
        
        action_plan = f"""# Sprint 2 Action Plan
        
Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
        
## Priority Matrix
        
### 🔴 Critical Priority
"""
        
        critical_recs = [r for r in recommendations if r.get("priority") == "CRITICAL"]
        for i, rec in enumerate(critical_recs, 1):
            action_plan += f"""
#### {i}. {rec.get('category', 'Unknown')}
**Issue:** {rec.get('issue', 'No description')}
**Recommendation:** {rec.get('recommendation', 'No recommendation')}

**Action Items:**
"""
            for action in rec.get('action_items', []):
                action_plan += f"- [ ] {action}\n"
        
        action_plan += "\n### 🟡 High Priority\n"
        
        high_recs = [r for r in recommendations if r.get("priority") == "HIGH"]
        for i, rec in enumerate(high_recs, 1):
            action_plan += f"""
#### {i}. {rec.get('category', 'Unknown')}
**Issue:** {rec.get('issue', 'No description')}
**Recommendation:** {rec.get('recommendation', 'No recommendation')}

**Action Items:**
"""
            for action in rec.get('action_items', []):
                action_plan += f"- [ ] {action}\n"
        
        action_plan += "\n### 🟢 Medium/Low Priority\n"
        
        other_recs = [r for r in recommendations if r.get("priority") not in ["CRITICAL", "HIGH"]]
        for i, rec in enumerate(other_recs, 1):
            action_plan += f"""
#### {i}. {rec.get('category', 'Unknown')}
**Issue:** {rec.get('issue', 'No description')}
**Recommendation:** {rec.get('recommendation', 'No recommendation')}

**Action Items:**
"""
            for action in rec.get('action_items', []):
                action_plan += f"- [ ] {action}\n"
        
        action_plan += """
## Timeline
- **Phase 1 (Immediate):** Address all Critical priority items
- **Phase 2 (This Week):** Address High priority items
- **Phase 3 (Next Sprint):** Address Medium/Low priority items

## Success Criteria
- All automated tests pass (90%+ pass rate)
- All services are healthy
- Integration health is HEALTHY
- Performance targets are met
- Manual test scenarios complete successfully

---
*Track progress by checking off completed action items*
"""
        
        return action_plan
    
    async def generate_final_report(self) -> Dict[str, Any]:
        """Generate the final comprehensive report"""
        total_duration = time.time() - self.start_time
        
        # Calculate overall success metrics
        automated_results = self.results.get("automated_tests", {})
        pass_rate = automated_results.get("test_execution", {}).get("pass_rate", 0)
        integration_health = self.results.get("integration_assessment", {}).get("overall_health", "UNKNOWN")
        performance_status = self.results.get("performance_analysis", {}).get("performance_status", "UNKNOWN")
        
        # Determine overall readiness
        if pass_rate >= 90 and integration_health == "HEALTHY" and performance_status == "PASS":
            readiness_status = "READY_FOR_PRODUCTION"
        elif pass_rate >= 80 and integration_health in ["HEALTHY", "DEGRADED"]:
            readiness_status = "READY_WITH_CONDITIONS"
        else:
            readiness_status = "NOT_READY"
        
        final_report = {
            **self.results,
            "final_assessment": {
                "overall_readiness": readiness_status,
                "test_completion_time": total_duration,
                "key_metrics": {
                    "automated_test_pass_rate": pass_rate,
                    "integration_health": integration_health,
                    "performance_status": performance_status
                },
                "next_steps": self.get_next_steps(readiness_status),
                "report_generated": datetime.now().isoformat()
            }
        }
        
        return final_report
    
    def get_next_steps(self, readiness_status: str) -> List[str]:
        """Get next steps based on readiness status"""
        if readiness_status == "READY_FOR_PRODUCTION":
            return [
                "Execute manual test scenarios to validate user experience",
                "Set up production monitoring and alerting",
                "Prepare production deployment procedures",
                "Schedule production deployment"
            ]
        elif readiness_status == "READY_WITH_CONDITIONS":
            return [
                "Address identified issues from recommendations",
                "Re-run automated tests after fixes",
                "Complete manual testing scenarios",
                "Review performance optimizations"
            ]
        else:
            return [
                "Fix critical service health issues",
                "Address failing automated tests",
                "Resolve integration problems",
                "Re-run comprehensive test suite"
            ]

async def main():
    """Main execution function"""
    runner = Sprint2ComprehensiveTestRunner()
    
    try:
        final_report = await runner.run_comprehensive_test_suite()
        
        # Save final report
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        final_report_path = f"sprint2_final_comprehensive_report_{timestamp}.json"
        
        with open(final_report_path, 'w') as f:
            json.dump(final_report, f, indent=2, default=str)
        
        # Print final summary
        logger.info("\n" + "="*80)
        logger.info("SPRINT 2 COMPREHENSIVE TEST SUITE - FINAL RESULTS")
        logger.info("="*80)
        
        readiness = final_report["final_assessment"]["overall_readiness"]
        test_duration = final_report["final_assessment"]["test_completion_time"]
        pass_rate = final_report["final_assessment"]["key_metrics"]["automated_test_pass_rate"]
        
        logger.info(f"Overall Readiness: {readiness}")
        logger.info(f"Test Duration: {test_duration:.2f} seconds")
        logger.info(f"Automated Test Pass Rate: {pass_rate:.1f}%")
        logger.info(f"Integration Health: {final_report['final_assessment']['key_metrics']['integration_health']}")
        logger.info(f"Performance Status: {final_report['final_assessment']['key_metrics']['performance_status']}")
        
        deliverables = final_report.get("deliverables", [])
        if deliverables:
            logger.info(f"\nGenerated Deliverables ({len(deliverables)}):")
            for deliverable in deliverables:
                logger.info(f"  📄 {deliverable}")
        
        logger.info(f"\nFinal comprehensive report saved to: {final_report_path}")
        
        # Print next steps
        next_steps = final_report["final_assessment"]["next_steps"]
        if next_steps:
            logger.info("\nNext Steps:")
            for i, step in enumerate(next_steps, 1):
                logger.info(f"  {i}. {step}")
        
        # Return success based on readiness status
        return readiness != "NOT_READY"
        
    except Exception as e:
        logger.error(f"Comprehensive test suite failed: {e}")
        return False

if __name__ == "__main__":
    success = asyncio.run(main())
    sys.exit(0 if success else 1)