"""
Test Reporting and Failure Diagnostics Framework
================================================

This module provides comprehensive test reporting, failure diagnostics, and result analysis
for the PyAirtable integration testing framework.
"""

import json
import logging
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any, Union, Tuple
import uuid
from dataclasses import dataclass, field
from collections import defaultdict
import traceback

logger = logging.getLogger(__name__)

@dataclass
class TestIssue:
    """Represents a test issue/problem found during testing"""
    severity: str  # critical, high, medium, low
    title: str
    description: str
    element: Optional[str] = None
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            "severity": self.severity,
            "title": self.title,
            "description": self.description,
            "element": self.element,
            "timestamp": self.timestamp,
            "metadata": self.metadata
        }

@dataclass
class TestLog:
    """Represents a test log entry"""
    level: str  # info, warning, error, debug
    message: str
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())
    details: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            "level": self.level,
            "message": self.message,
            "timestamp": self.timestamp,
            "details": self.details
        }

@dataclass
class TestScreenshot:
    """Represents a test screenshot"""
    path: str
    description: str
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            "path": self.path,
            "description": self.description,
            "timestamp": self.timestamp
        }

class TestResult:
    """Container for individual test results and metadata"""
    
    def __init__(self, agent_name: str, test_name: str):
        self.agent_name = agent_name
        self.test_name = test_name
        self.start_time = datetime.now()
        self.end_time: Optional[datetime] = None
        self.status = "running"  # running, passed, failed, error, skipped
        self.duration: float = 0.0
        
        # Test artifacts
        self.screenshots: List[TestScreenshot] = []
        self.logs: List[TestLog] = []
        self.issues_found: List[TestIssue] = []
        self.performance_metrics: Dict[str, Any] = {}
        self.recommendations: List[str] = []
        
        # Test metadata
        self.test_id = str(uuid.uuid4())
        self.tags: List[str] = []
        self.environment_info: Dict[str, Any] = {}
        
    def add_log(self, level: str, message: str, details: Dict[str, Any] = None):
        """Add a log entry"""
        log_entry = TestLog(level, message, details=details or {})
        self.logs.append(log_entry)
        
        # Also log to Python logger
        log_level = getattr(logging, level.upper(), logging.INFO)
        logger.log(log_level, f"{self.agent_name} - {self.test_name}: {message}")
    
    def add_screenshot(self, path: str, description: str):
        """Add a screenshot"""
        screenshot = TestScreenshot(path, description)
        self.screenshots.append(screenshot)
    
    def add_issue(self, severity: str, title: str, description: str, element: str = None, 
                  metadata: Dict[str, Any] = None):
        """Add an issue found during testing"""
        issue = TestIssue(severity, title, description, element, metadata=metadata or {})
        self.issues_found.append(issue)
        
        # Log the issue
        self.add_log("warning" if severity in ["low", "medium"] else "error", 
                     f"{severity.upper()}: {title} - {description}")
    
    def add_recommendation(self, recommendation: str):
        """Add a recommendation for improvement"""
        self.recommendations.append(recommendation)
    
    def complete(self, status: str):
        """Mark test as complete"""
        self.end_time = datetime.now()
        self.status = status
        self.duration = (self.end_time - self.start_time).total_seconds()
        
        # Add final log
        self.add_log("info", f"Test completed with status: {status} (duration: {self.duration:.2f}s)")
    
    def get_severity_counts(self) -> Dict[str, int]:
        """Get count of issues by severity"""
        counts = defaultdict(int)
        for issue in self.issues_found:
            counts[issue.severity] += 1
        return dict(counts)
    
    def has_critical_issues(self) -> bool:
        """Check if test has critical issues"""
        return any(issue.severity == "critical" for issue in self.issues_found)
    
    def has_high_issues(self) -> bool:
        """Check if test has high severity issues"""
        return any(issue.severity == "high" for issue in self.issues_found)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            "test_id": self.test_id,
            "agent_name": self.agent_name,
            "test_name": self.test_name,
            "status": self.status,
            "start_time": self.start_time.isoformat(),
            "end_time": self.end_time.isoformat() if self.end_time else None,
            "duration": self.duration,
            "tags": self.tags,
            "environment_info": self.environment_info,
            "performance_metrics": self.performance_metrics,
            "recommendations": self.recommendations,
            "screenshots": [screenshot.to_dict() for screenshot in self.screenshots],
            "logs": [log.to_dict() for log in self.logs],
            "issues_found": [issue.to_dict() for issue in self.issues_found],
            "severity_counts": self.get_severity_counts()
        }

class TestReport:
    """Comprehensive test report generator and analyzer"""
    
    def __init__(self, suite_name: str, output_dir: str = "test-results"):
        self.suite_name = suite_name
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Report metadata
        self.report_id = str(uuid.uuid4())
        self.start_time = datetime.now()
        self.end_time: Optional[datetime] = None
        
        # Test results
        self.test_results: List[TestResult] = []
        
        # Report configuration
        self.generate_html = True
        self.generate_json = True
        self.include_artifacts = True
        
    def add_test_result(self, result: TestResult):
        """Add a test result to the report"""
        self.test_results.append(result)
    
    def get_summary_stats(self) -> Dict[str, Any]:
        """Get summary statistics for all tests"""
        total_tests = len(self.test_results)
        
        # Count by status
        status_counts = defaultdict(int)
        for result in self.test_results:
            status_counts[result.status] += 1
        
        # Count issues by severity
        severity_counts = defaultdict(int)
        for result in self.test_results:
            for issue in result.issues_found:
                severity_counts[issue.severity] += 1
        
        # Performance metrics
        total_duration = sum(result.duration for result in self.test_results)
        avg_duration = total_duration / total_tests if total_tests > 0 else 0
        
        # Success rate
        passed_tests = status_counts.get("passed", 0)
        success_rate = (passed_tests / total_tests * 100) if total_tests > 0 else 0
        
        return {
            "total_tests": total_tests,
            "status_counts": dict(status_counts),
            "severity_counts": dict(severity_counts),
            "total_duration": total_duration,
            "avg_duration": avg_duration,
            "success_rate": success_rate,
            "total_issues": sum(severity_counts.values()),
            "tests_with_issues": len([r for r in self.test_results if r.issues_found])
        }
    
    def get_agent_summary(self) -> Dict[str, Dict[str, Any]]:
        """Get summary statistics by agent"""
        agent_stats = defaultdict(lambda: {
            "total_tests": 0,
            "passed": 0,
            "failed": 0,
            "error": 0,
            "total_duration": 0,
            "total_issues": 0,
            "severity_counts": defaultdict(int)
        })
        
        for result in self.test_results:
            agent = agent_stats[result.agent_name]
            agent["total_tests"] += 1
            agent[result.status] += 1
            agent["total_duration"] += result.duration
            agent["total_issues"] += len(result.issues_found)
            
            for issue in result.issues_found:
                agent["severity_counts"][issue.severity] += 1
        
        # Convert defaultdicts to regular dicts
        return {
            agent_name: {
                **stats,
                "severity_counts": dict(stats["severity_counts"]),
                "avg_duration": stats["total_duration"] / stats["total_tests"] if stats["total_tests"] > 0 else 0,
                "success_rate": stats["passed"] / stats["total_tests"] * 100 if stats["total_tests"] > 0 else 0
            }
            for agent_name, stats in agent_stats.items()
        }
    
    def get_test_trends(self) -> Dict[str, Any]:
        """Analyze test trends and patterns"""
        # Sort results by start time
        sorted_results = sorted(self.test_results, key=lambda r: r.start_time)
        
        # Test duration trends
        durations = [result.duration for result in sorted_results]
        
        # Issue trends
        issue_counts = [len(result.issues_found) for result in sorted_results]
        
        # Performance trends (if available)
        response_times = []
        for result in sorted_results:
            if "response_time" in result.performance_metrics:
                response_times.append(result.performance_metrics["response_time"])
            elif "avg_response_time" in result.performance_metrics:
                response_times.append(result.performance_metrics["avg_response_time"])
        
        return {
            "duration_trend": durations,
            "issue_count_trend": issue_counts,
            "response_time_trend": response_times,
            "avg_duration": sum(durations) / len(durations) if durations else 0,
            "avg_issues_per_test": sum(issue_counts) / len(issue_counts) if issue_counts else 0,
            "avg_response_time": sum(response_times) / len(response_times) if response_times else 0
        }
    
    def get_failure_analysis(self) -> Dict[str, Any]:
        """Analyze failures and provide insights"""
        failed_results = [r for r in self.test_results if r.status in ["failed", "error"]]
        
        # Common failure patterns
        failure_patterns = defaultdict(int)
        common_issues = defaultdict(int)
        
        for result in failed_results:
            # Analyze log messages for patterns
            for log in result.logs:
                if log.level in ["error", "warning"]:
                    # Simple pattern matching (can be enhanced with regex)
                    message = log.message.lower()
                    if "timeout" in message:
                        failure_patterns["timeout"] += 1
                    elif "connection" in message:
                        failure_patterns["connection"] += 1
                    elif "not found" in message or "404" in message:
                        failure_patterns["not_found"] += 1
                    elif "auth" in message or "401" in message or "403" in message:
                        failure_patterns["authentication"] += 1
                    elif "server error" in message or "500" in message:
                        failure_patterns["server_error"] += 1
            
            # Count common issue types
            for issue in result.issues_found:
                common_issues[issue.title] += 1
        
        # Generate recommendations
        recommendations = []
        if failure_patterns["timeout"] > 0:
            recommendations.append("Consider increasing timeout values or optimizing service response times")
        if failure_patterns["connection"] > 0:
            recommendations.append("Check network connectivity and service availability")
        if failure_patterns["authentication"] > 0:
            recommendations.append("Verify API keys and authentication configuration")
        if failure_patterns["server_error"] > 0:
            recommendations.append("Check server logs for internal errors")
        
        return {
            "total_failures": len(failed_results),
            "failure_rate": len(failed_results) / len(self.test_results) * 100 if self.test_results else 0,
            "failure_patterns": dict(failure_patterns),
            "common_issues": dict(common_issues),
            "recommendations": recommendations,
            "most_failing_agent": max(
                [(result.agent_name, 1) for result in failed_results], 
                key=lambda x: x[1], 
                default=("none", 0)
            )[0] if failed_results else "none"
        }
    
    async def generate_report(self) -> Tuple[str, str]:
        """Generate comprehensive test report"""
        self.end_time = datetime.now()
        
        # Generate JSON report
        json_report_path = await self._generate_json_report()
        
        # Generate HTML report
        html_report_path = await self._generate_html_report()
        
        # Generate summary log
        self._log_summary()
        
        return json_report_path, html_report_path
    
    async def _generate_json_report(self) -> str:
        """Generate JSON report"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        json_file = self.output_dir / f"test_report_{timestamp}.json"
        
        report_data = {
            "report_id": self.report_id,
            "suite_name": self.suite_name,
            "start_time": self.start_time.isoformat(),
            "end_time": self.end_time.isoformat() if self.end_time else None,
            "total_duration": (self.end_time - self.start_time).total_seconds() if self.end_time else 0,
            "summary": self.get_summary_stats(),
            "agent_summary": self.get_agent_summary(),
            "trends": self.get_test_trends(),
            "failure_analysis": self.get_failure_analysis(),
            "test_results": [result.to_dict() for result in self.test_results]
        }
        
        with open(json_file, 'w') as f:
            json.dump(report_data, f, indent=2, default=str)
        
        logger.info(f"JSON report generated: {json_file}")
        return str(json_file)
    
    async def _generate_html_report(self) -> str:
        """Generate HTML report"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        html_file = self.output_dir / f"test_report_{timestamp}.html"
        
        summary = self.get_summary_stats()
        agent_summary = self.get_agent_summary()
        failure_analysis = self.get_failure_analysis()
        
        html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PyAirtable Test Report - {self.suite_name}</title>
    <style>
        {self._get_html_styles()}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 PyAirtable Integration Test Report</h1>
            <div class="header-info">
                <p><strong>Suite:</strong> {self.suite_name}</p>
                <p><strong>Generated:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
                <p><strong>Report ID:</strong> {self.report_id}</p>
            </div>
        </div>
        
        <div class="summary-grid">
            <div class="metric-card">
                <h3>Total Tests</h3>
                <div class="metric-value">{summary['total_tests']}</div>
            </div>
            <div class="metric-card success">
                <h3>Success Rate</h3>
                <div class="metric-value">{summary['success_rate']:.1f}%</div>
            </div>
            <div class="metric-card">
                <h3>Total Duration</h3>
                <div class="metric-value">{summary['total_duration']:.1f}s</div>
            </div>
            <div class="metric-card">
                <h3>Total Issues</h3>
                <div class="metric-value">{summary['total_issues']}</div>
            </div>
        </div>
        
        <div class="status-overview">
            <h2>Test Status Overview</h2>
            <div class="status-grid">
                <div class="status-item passed">
                    <span class="status-count">{summary['status_counts'].get('passed', 0)}</span>
                    <span class="status-label">Passed</span>
                </div>
                <div class="status-item failed">
                    <span class="status-count">{summary['status_counts'].get('failed', 0)}</span>
                    <span class="status-label">Failed</span>
                </div>
                <div class="status-item error">
                    <span class="status-count">{summary['status_counts'].get('error', 0)}</span>
                    <span class="status-label">Error</span>
                </div>
                <div class="status-item skipped">
                    <span class="status-count">{summary['status_counts'].get('skipped', 0)}</span>
                    <span class="status-label">Skipped</span>
                </div>
            </div>
        </div>
        
        <div class="agent-summary">
            <h2>Agent Performance Summary</h2>
            <div class="agent-grid">
                {self._generate_agent_cards(agent_summary)}
            </div>
        </div>
        
        {self._generate_failure_analysis_html(failure_analysis)}
        
        <div class="test-details">
            <h2>Detailed Test Results</h2>
            {self._generate_test_details_html()}
        </div>
    </div>
    
    <script>
        {self._get_html_scripts()}
    </script>
</body>
</html>
"""
        
        with open(html_file, 'w') as f:
            f.write(html_content)
        
        logger.info(f"HTML report generated: {html_file}")
        return str(html_file)
    
    def _get_html_styles(self) -> str:
        """Get CSS styles for HTML report"""
        return """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f5f7fa;
            color: #333;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem;
            border-radius: 12px;
            margin-bottom: 2rem;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 1rem;
        }
        
        .header-info {
            display: flex;
            justify-content: center;
            gap: 2rem;
            flex-wrap: wrap;
        }
        
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin-bottom: 2rem;
        }
        
        .metric-card {
            background: white;
            padding: 1.5rem;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }
        
        .metric-card h3 {
            color: #666;
            font-size: 0.9rem;
            margin-bottom: 0.5rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .metric-value {
            font-size: 2.5rem;
            font-weight: bold;
            color: #333;
        }
        
        .metric-card.success .metric-value {
            color: #10b981;
        }
        
        .status-overview, .agent-summary, .test-details {
            background: white;
            padding: 2rem;
            border-radius: 12px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 2rem;
        }
        
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 1rem;
            margin-top: 1rem;
        }
        
        .status-item {
            text-align: center;
            padding: 1rem;
            border-radius: 8px;
            color: white;
        }
        
        .status-item.passed { background: #10b981; }
        .status-item.failed { background: #ef4444; }
        .status-item.error { background: #f59e0b; }
        .status-item.skipped { background: #6b7280; }
        
        .status-count {
            display: block;
            font-size: 2rem;
            font-weight: bold;
        }
        
        .status-label {
            font-size: 0.9rem;
            opacity: 0.9;
        }
        
        .agent-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1rem;
            margin-top: 1rem;
        }
        
        .agent-card {
            border: 1px solid #e5e7eb;
            border-radius: 8px;
            padding: 1.5rem;
            background: #f9fafb;
        }
        
        .agent-name {
            font-size: 1.2rem;
            font-weight: bold;
            margin-bottom: 1rem;
            color: #374151;
        }
        
        .agent-stats {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 0.5rem;
            font-size: 0.9rem;
        }
        
        .test-item {
            border: 1px solid #e5e7eb;
            border-radius: 8px;
            margin-bottom: 1rem;
            overflow: hidden;
        }
        
        .test-header {
            padding: 1rem;
            background: #f9fafb;
            border-bottom: 1px solid #e5e7eb;
            display: flex;
            justify-content: space-between;
            align-items: center;
            cursor: pointer;
        }
        
        .test-name {
            font-weight: bold;
            color: #374151;
        }
        
        .test-status {
            padding: 0.25rem 0.75rem;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: bold;
            text-transform: uppercase;
        }
        
        .test-status.passed { background: #d1fae5; color: #065f46; }
        .test-status.failed { background: #fecaca; color: #991b1b; }
        .test-status.error { background: #fef3c7; color: #92400e; }
        
        .test-body {
            padding: 1rem;
            display: none;
        }
        
        .test-body.expanded {
            display: block;
        }
        
        .issue {
            padding: 0.75rem;
            margin: 0.5rem 0;
            border-radius: 4px;
            border-left: 4px solid;
        }
        
        .issue.critical { background: #fef2f2; border-color: #dc2626; }
        .issue.high { background: #fffbeb; border-color: #d97706; }
        .issue.medium { background: #eff6ff; border-color: #2563eb; }
        .issue.low { background: #f0fdf4; border-color: #16a34a; }
        
        .issue-title {
            font-weight: bold;
            margin-bottom: 0.25rem;
        }
        
        .issue-description {
            font-size: 0.9rem;
            color: #666;
        }
        
        @media (max-width: 768px) {
            .header-info {
                flex-direction: column;
                gap: 0.5rem;
            }
            
            .summary-grid {
                grid-template-columns: repeat(2, 1fr);
            }
        }
        """
    
    def _generate_agent_cards(self, agent_summary: Dict[str, Dict[str, Any]]) -> str:
        """Generate HTML for agent performance cards"""
        cards_html = ""
        
        for agent_name, stats in agent_summary.items():
            cards_html += f"""
            <div class="agent-card">
                <div class="agent-name">{agent_name}</div>
                <div class="agent-stats">
                    <div>Tests: {stats['total_tests']}</div>
                    <div>Success: {stats['success_rate']:.1f}%</div>
                    <div>Duration: {stats['total_duration']:.1f}s</div>
                    <div>Issues: {stats['total_issues']}</div>
                    <div>Passed: {stats['passed']}</div>
                    <div>Failed: {stats['failed']}</div>
                </div>
            </div>
            """
        
        return cards_html
    
    def _generate_failure_analysis_html(self, failure_analysis: Dict[str, Any]) -> str:
        """Generate HTML for failure analysis section"""
        if failure_analysis['total_failures'] == 0:
            return """
            <div class="failure-analysis">
                <h2>🎉 No Failures Detected</h2>
                <p>All tests completed successfully!</p>
            </div>
            """
        
        patterns_html = ""
        for pattern, count in failure_analysis['failure_patterns'].items():
            patterns_html += f"<li>{pattern.replace('_', ' ').title()}: {count}</li>"
        
        recommendations_html = ""
        for rec in failure_analysis['recommendations']:
            recommendations_html += f"<li>{rec}</li>"
        
        return f"""
        <div class="failure-analysis status-overview">
            <h2>🔍 Failure Analysis</h2>
            <div class="failure-stats">
                <p><strong>Total Failures:</strong> {failure_analysis['total_failures']}</p>
                <p><strong>Failure Rate:</strong> {failure_analysis['failure_rate']:.1f}%</p>
                <p><strong>Most Failing Agent:</strong> {failure_analysis['most_failing_agent']}</p>
            </div>
            
            {f'<h3>Common Failure Patterns</h3><ul>{patterns_html}</ul>' if patterns_html else ''}
            
            {f'<h3>Recommendations</h3><ul>{recommendations_html}</ul>' if recommendations_html else ''}
        </div>
        """
    
    def _generate_test_details_html(self) -> str:
        """Generate HTML for detailed test results"""
        tests_html = ""
        
        for result in self.test_results:
            # Generate issues HTML
            issues_html = ""
            for issue in result.issues_found:
                issues_html += f"""
                <div class="issue {issue.severity}">
                    <div class="issue-title">{issue.title}</div>
                    <div class="issue-description">{issue.description}</div>
                </div>
                """
            
            # Generate logs HTML (showing only important ones)
            important_logs = [log for log in result.logs if log.level in ['error', 'warning']]
            logs_html = ""
            for log in important_logs[:5]:  # Limit to 5 most important logs
                logs_html += f"<div><strong>{log.level.upper()}:</strong> {log.message}</div>"
            
            tests_html += f"""
            <div class="test-item">
                <div class="test-header" onclick="toggleTest('{result.test_id}')">
                    <div>
                        <div class="test-name">{result.agent_name} - {result.test_name}</div>
                        <div style="font-size: 0.8rem; color: #666;">
                            Duration: {result.duration:.2f}s | Issues: {len(result.issues_found)}
                        </div>
                    </div>
                    <div class="test-status {result.status}">{result.status}</div>
                </div>
                <div class="test-body" id="test-{result.test_id}">
                    {f'<h4>Issues Found</h4>{issues_html}' if issues_html else '<p>✅ No issues found</p>'}
                    {f'<h4>Important Logs</h4>{logs_html}' if logs_html else ''}
                    {f'<h4>Performance Metrics</h4><pre>{json.dumps(result.performance_metrics, indent=2)}</pre>' if result.performance_metrics else ''}
                </div>
            </div>
            """
        
        return tests_html
    
    def _get_html_scripts(self) -> str:
        """Get JavaScript for HTML report"""
        return """
        function toggleTest(testId) {
            const testBody = document.getElementById('test-' + testId);
            if (testBody.classList.contains('expanded')) {
                testBody.classList.remove('expanded');
            } else {
                testBody.classList.add('expanded');
            }
        }
        
        // Auto-expand failed tests
        document.addEventListener('DOMContentLoaded', function() {
            const failedTests = document.querySelectorAll('.test-status.failed, .test-status.error');
            failedTests.forEach(function(status) {
                const testHeader = status.closest('.test-header');
                const testId = testHeader.getAttribute('onclick').match(/toggleTest\\('([^']+)'\\)/)[1];
                const testBody = document.getElementById('test-' + testId);
                testBody.classList.add('expanded');
            });
        });
        """
    
    def _log_summary(self):
        """Log a summary of the test results"""
        summary = self.get_summary_stats()
        
        logger.info("=" * 80)
        logger.info(f"TEST SUITE SUMMARY: {self.suite_name}")
        logger.info("=" * 80)
        logger.info(f"Total Tests: {summary['total_tests']}")
        logger.info(f"Passed: {summary['status_counts'].get('passed', 0)}")
        logger.info(f"Failed: {summary['status_counts'].get('failed', 0)}")
        logger.info(f"Errors: {summary['status_counts'].get('error', 0)}")
        logger.info(f"Success Rate: {summary['success_rate']:.1f}%")
        logger.info(f"Total Duration: {summary['total_duration']:.2f}s")
        logger.info(f"Total Issues: {summary['total_issues']}")
        
        if summary['severity_counts']:
            logger.info("Issues by Severity:")
            for severity, count in summary['severity_counts'].items():
                logger.info(f"  {severity.title()}: {count}")
        
        logger.info("=" * 80)