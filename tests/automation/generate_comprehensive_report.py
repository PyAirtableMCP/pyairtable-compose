#!/usr/bin/env python3
"""
Comprehensive Test Report Generator for PyAirtable Test Automation
Aggregates results from all test suites and generates detailed reports
"""

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional
import logging
import subprocess
from dataclasses import dataclass
from jinja2 import Template

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


@dataclass
class TestResult:
    """Individual test result"""
    name: str
    status: str  # "passed", "failed", "skipped", "error"
    duration: float
    message: Optional[str] = None
    traceback: Optional[str] = None
    suite: Optional[str] = None


@dataclass
class TestSuiteResult:
    """Test suite aggregated results"""
    name: str
    total_tests: int
    passed_tests: int
    failed_tests: int
    skipped_tests: int
    error_tests: int
    total_duration: float
    success_rate: float
    tests: List[TestResult]


class TestReportGenerator:
    """Comprehensive test report generator"""
    
    def __init__(self, input_dir: str, output_dir: str, environment: str = "ci"):
        self.input_dir = Path(input_dir)
        self.output_dir = Path(output_dir)
        self.environment = environment
        self.timestamp = datetime.utcnow()
        
        # Create output directory
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Test suite definitions
        self.test_suites = {
            "unit": {
                "name": "Unit Tests",
                "patterns": ["unit-test-results-*", "**/unit*.xml"],
                "critical": True
            },
            "integration": {
                "name": "Integration Tests", 
                "patterns": ["integration-test-results*", "**/integration*.xml"],
                "critical": True
            },
            "security": {
                "name": "Security Tests",
                "patterns": ["security-test-results*", "**/security*.xml"],
                "critical": True
            },
            "e2e": {
                "name": "End-to-End Tests",
                "patterns": ["e2e-test-results-*", "**/e2e*.xml"],
                "critical": False
            },
            "performance": {
                "name": "Performance Tests",
                "patterns": ["performance-test-results*", "**/performance*.xml"],
                "critical": False
            },
            "chaos": {
                "name": "Chaos Tests",
                "patterns": ["chaos-test-results*", "**/chaos*.xml"],
                "critical": False
            },
            "deployment": {
                "name": "Deployment Tests",
                "patterns": ["deployment-test-results*", "**/deployment*.xml"],
                "critical": True
            },
            "contract": {
                "name": "Contract Tests",
                "patterns": ["**/contract*.xml"],
                "critical": False
            }
        }
    
    def find_test_files(self) -> Dict[str, List[Path]]:
        """Find all test result files"""
        logger.info(f"Scanning for test files in: {self.input_dir}")
        
        found_files = {}
        
        for suite_key, suite_config in self.test_suites.items():
            found_files[suite_key] = []
            
            for pattern in suite_config["patterns"]:
                # Find XML files
                xml_files = list(self.input_dir.rglob("*.xml"))
                for xml_file in xml_files:
                    if self._matches_pattern(xml_file.name, pattern) or \
                       self._matches_pattern(str(xml_file.relative_to(self.input_dir)), pattern):
                        found_files[suite_key].append(xml_file)
                
                # Find JSON files for additional data
                json_files = list(self.input_dir.rglob("*.json"))
                for json_file in json_files:
                    if self._matches_pattern(json_file.name, pattern) or \
                       self._matches_pattern(str(json_file.relative_to(self.input_dir)), pattern):
                        found_files[suite_key].append(json_file)
        
        # Log found files
        for suite_key, files in found_files.items():
            logger.info(f"Found {len(files)} files for {suite_key}: {[f.name for f in files]}")
        
        return found_files
    
    def _matches_pattern(self, filename: str, pattern: str) -> bool:
        """Check if filename matches pattern"""
        import fnmatch
        return fnmatch.fnmatch(filename, pattern)
    
    def parse_junit_xml(self, xml_file: Path) -> List[TestResult]:
        """Parse JUnit XML test results"""
        try:
            tree = ET.parse(xml_file)
            root = tree.getroot()
            
            tests = []
            
            # Handle different XML formats
            if root.tag == "testsuites":
                testsuites = root.findall("testsuite")
            else:
                testsuites = [root]
            
            for testsuite in testsuites:
                suite_name = testsuite.get("name", xml_file.stem)
                
                for testcase in testsuite.findall("testcase"):
                    name = testcase.get("name", "unknown")
                    classname = testcase.get("classname", "")
                    duration = float(testcase.get("time", "0"))
                    
                    # Determine status
                    if testcase.find("failure") is not None:
                        status = "failed"
                        failure_elem = testcase.find("failure")
                        message = failure_elem.get("message", "") if failure_elem is not None else ""
                        traceback = failure_elem.text if failure_elem is not None else ""
                    elif testcase.find("error") is not None:
                        status = "error"
                        error_elem = testcase.find("error")
                        message = error_elem.get("message", "") if error_elem is not None else ""
                        traceback = error_elem.text if error_elem is not None else ""
                    elif testcase.find("skipped") is not None:
                        status = "skipped"
                        skipped_elem = testcase.find("skipped")
                        message = skipped_elem.get("message", "") if skipped_elem is not None else ""
                        traceback = None
                    else:
                        status = "passed"
                        message = None
                        traceback = None
                    
                    test_name = f"{classname}.{name}" if classname else name
                    
                    tests.append(TestResult(
                        name=test_name,
                        status=status,
                        duration=duration,
                        message=message,
                        traceback=traceback,
                        suite=suite_name
                    ))
            
            return tests
            
        except Exception as e:
            logger.error(f"Error parsing XML file {xml_file}: {e}")
            return []
    
    def parse_json_results(self, json_file: Path) -> Dict[str, Any]:
        """Parse JSON test results for additional metadata"""
        try:
            with open(json_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Error parsing JSON file {json_file}: {e}")
            return {}
    
    def aggregate_test_results(self, test_files: Dict[str, List[Path]]) -> Dict[str, TestSuiteResult]:
        """Aggregate test results by suite"""
        suite_results = {}
        
        for suite_key, files in test_files.items():
            suite_config = self.test_suites[suite_key]
            all_tests = []
            
            # Parse all files for this suite
            for file_path in files:
                if file_path.suffix == '.xml':
                    tests = self.parse_junit_xml(file_path)
                    all_tests.extend(tests)
                elif file_path.suffix == '.json':
                    # JSON files may contain additional metadata
                    json_data = self.parse_json_results(file_path)
                    # Convert JSON results to TestResult objects if needed
                    # This would depend on the specific JSON format
            
            if all_tests:
                # Calculate aggregated metrics
                total_tests = len(all_tests)
                passed_tests = len([t for t in all_tests if t.status == "passed"])
                failed_tests = len([t for t in all_tests if t.status == "failed"])
                skipped_tests = len([t for t in all_tests if t.status == "skipped"])
                error_tests = len([t for t in all_tests if t.status == "error"])
                total_duration = sum(t.duration for t in all_tests)
                success_rate = (passed_tests / total_tests * 100) if total_tests > 0 else 0
                
                suite_results[suite_key] = TestSuiteResult(
                    name=suite_config["name"],
                    total_tests=total_tests,
                    passed_tests=passed_tests,
                    failed_tests=failed_tests,
                    skipped_tests=skipped_tests,
                    error_tests=error_tests,
                    total_duration=total_duration,
                    success_rate=success_rate,
                    tests=all_tests
                )
            else:
                # Create empty result if no tests found
                suite_results[suite_key] = TestSuiteResult(
                    name=suite_config["name"],
                    total_tests=0,
                    passed_tests=0,
                    failed_tests=0,
                    skipped_tests=0,
                    error_tests=0,
                    total_duration=0.0,
                    success_rate=0.0,
                    tests=[]
                )
        
        return suite_results
    
    def calculate_quality_metrics(self, suite_results: Dict[str, TestSuiteResult]) -> Dict[str, Any]:
        """Calculate overall quality metrics"""
        # Overall totals
        total_tests = sum(suite.total_tests for suite in suite_results.values())
        total_passed = sum(suite.passed_tests for suite in suite_results.values())
        total_failed = sum(suite.failed_tests for suite in suite_results.values())
        total_errors = sum(suite.error_tests for suite in suite_results.values())
        total_duration = sum(suite.total_duration for suite in suite_results.values())
        
        overall_success_rate = (total_passed / total_tests * 100) if total_tests > 0 else 0
        
        # Critical failures (from critical test suites)
        critical_failures = 0
        for suite_key, suite_result in suite_results.items():
            if self.test_suites[suite_key]["critical"]:
                critical_failures += suite_result.failed_tests + suite_result.error_tests
        
        # Test coverage and quality indicators
        quality_score = self._calculate_quality_score(suite_results)
        
        # Performance metrics
        slowest_tests = []
        for suite in suite_results.values():
            slowest_tests.extend(suite.tests)
        slowest_tests.sort(key=lambda t: t.duration, reverse=True)
        slowest_tests = slowest_tests[:10]  # Top 10 slowest
        
        return {
            "overall": {
                "total_tests": total_tests,
                "passed_tests": total_passed,
                "failed_tests": total_failed,
                "error_tests": total_errors,
                "success_rate": f"{overall_success_rate:.1f}%",
                "total_duration": f"{total_duration:.2f}s",
                "average_test_duration": f"{total_duration / total_tests:.3f}s" if total_tests > 0 else "0s"
            },
            "critical_failures": critical_failures,
            "quality_score": quality_score,
            "slowest_tests": [
                {
                    "name": test.name,
                    "duration": f"{test.duration:.3f}s",
                    "suite": test.suite
                }
                for test in slowest_tests
            ]
        }
    
    def _calculate_quality_score(self, suite_results: Dict[str, TestSuiteResult]) -> float:
        """Calculate overall quality score (0-100)"""
        weights = {
            "unit": 0.3,
            "integration": 0.25,
            "security": 0.2,
            "e2e": 0.15,
            "deployment": 0.1
        }
        
        weighted_score = 0.0
        total_weight = 0.0
        
        for suite_key, suite_result in suite_results.items():
            if suite_key in weights and suite_result.total_tests > 0:
                suite_score = suite_result.success_rate
                weight = weights[suite_key]
                weighted_score += suite_score * weight
                total_weight += weight
        
        return weighted_score / total_weight if total_weight > 0 else 0.0
    
    def generate_html_report(self, suite_results: Dict[str, TestSuiteResult], 
                           quality_metrics: Dict[str, Any]) -> str:
        """Generate comprehensive HTML report"""
        
        html_template = Template("""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PyAirtable Test Report - {{ timestamp.strftime('%Y-%m-%d %H:%M UTC') }}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px 0; margin-bottom: 30px; border-radius: 8px; }
        .header h1 { text-align: center; font-size: 2.5em; margin-bottom: 10px; }
        .header .subtitle { text-align: center; font-size: 1.2em; opacity: 0.9; }
        .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .metric-card { background: white; border-radius: 8px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); border-left: 4px solid #667eea; }
        .metric-card h3 { color: #667eea; margin-bottom: 10px; }
        .metric-value { font-size: 2em; font-weight: bold; margin: 10px 0; }
        .metric-value.success { color: #27ae60; }
        .metric-value.warning { color: #f39c12; }
        .metric-value.danger { color: #e74c3c; }
        .suite-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(400px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .suite-card { background: white; border-radius: 8px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .suite-header { display: flex; justify-content: between; align-items: center; margin-bottom: 15px; }
        .suite-title { font-size: 1.3em; font-weight: bold; }
        .success-rate { font-size: 1.1em; font-weight: bold; padding: 5px 10px; border-radius: 20px; }
        .success-rate.high { background: #d4edda; color: #155724; }
        .success-rate.medium { background: #fff3cd; color: #856404; }
        .success-rate.low { background: #f8d7da; color: #721c24; }
        .test-stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; text-align: center; }
        .test-stat { padding: 10px; border-radius: 4px; }
        .stat-passed { background: #d4edda; color: #155724; }
        .stat-failed { background: #f8d7da; color: #721c24; }
        .stat-skipped { background: #e2e3e5; color: #6c757d; }
        .stat-total { background: #e3f2fd; color: #1565c0; }
        .failed-tests { margin-top: 15px; }
        .failed-test { background: #f8f9fa; border-left: 3px solid #dc3545; padding: 10px; margin: 5px 0; border-radius: 0 4px 4px 0; }
        .test-name { font-weight: bold; color: #dc3545; }
        .test-message { color: #6c757d; font-size: 0.9em; margin-top: 5px; }
        .quality-indicator { text-align: center; margin: 30px 0; }
        .quality-score { font-size: 3em; font-weight: bold; margin: 20px 0; }
        .quality-score.excellent { color: #27ae60; }
        .quality-score.good { color: #f39c12; }
        .quality-score.poor { color: #e74c3c; }
        .slowest-tests { background: white; border-radius: 8px; padding: 20px; margin: 20px 0; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .test-list { list-style: none; }
        .test-item { display: flex; justify-content: between; padding: 8px 0; border-bottom: 1px solid #eee; }
        .footer { text-align: center; color: #6c757d; margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; }
        @media (max-width: 768px) {
            .metrics-grid, .suite-grid { grid-template-columns: 1fr; }
            .test-stats { grid-template-columns: repeat(2, 1fr); }
            .header h1 { font-size: 2em; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🧪 PyAirtable Test Report</h1>
            <div class="subtitle">{{ environment|title }} Environment • {{ timestamp.strftime('%Y-%m-%d %H:%M UTC') }}</div>
        </div>

        <!-- Overall Metrics -->
        <div class="metrics-grid">
            <div class="metric-card">
                <h3>📊 Total Tests</h3>
                <div class="metric-value stat-total">{{ quality_metrics.overall.total_tests }}</div>
                <div>Across all test suites</div>
            </div>
            <div class="metric-card">
                <h3>✅ Success Rate</h3>
                <div class="metric-value {% if quality_metrics.overall.success_rate|replace('%','')|float >= 95 %}success{% elif quality_metrics.overall.success_rate|replace('%','')|float >= 80 %}warning{% else %}danger{% endif %}">{{ quality_metrics.overall.success_rate }}</div>
                <div>{{ quality_metrics.overall.passed_tests }} passed, {{ quality_metrics.overall.failed_tests }} failed</div>
            </div>
            <div class="metric-card">
                <h3>⏱️ Total Duration</h3>
                <div class="metric-value">{{ quality_metrics.overall.total_duration }}</div>
                <div>Average: {{ quality_metrics.overall.average_test_duration }}</div>
            </div>
            <div class="metric-card">
                <h3>🚨 Critical Failures</h3>
                <div class="metric-value {% if quality_metrics.critical_failures > 0 %}danger{% else %}success{% endif %}">{{ quality_metrics.critical_failures }}</div>
                <div>From critical test suites</div>
            </div>
        </div>

        <!-- Quality Score -->
        <div class="quality-indicator">
            <h2>Overall Quality Score</h2>
            <div class="quality-score {% if quality_metrics.quality_score >= 90 %}excellent{% elif quality_metrics.quality_score >= 70 %}good{% else %}poor{% endif %}">
                {{ "%.1f"|format(quality_metrics.quality_score) }}%
            </div>
            <div>
                {% if quality_metrics.quality_score >= 90 %}
                    🎉 Excellent! Your tests are in great shape.
                {% elif quality_metrics.quality_score >= 70 %}
                    👍 Good! Some areas need attention.
                {% else %}
                    ⚠️ Needs improvement. Review failed tests.
                {% endif %}
            </div>
        </div>

        <!-- Test Suites -->
        <h2>📋 Test Suites</h2>
        <div class="suite-grid">
            {% for suite_key, suite in suite_results.items() %}
            <div class="suite-card">
                <div class="suite-header">
                    <div class="suite-title">{{ suite.name }}</div>
                    <div class="success-rate {% if suite.success_rate >= 95 %}high{% elif suite.success_rate >= 80 %}medium{% else %}low{% endif %}">
                        {{ "%.1f"|format(suite.success_rate) }}%
                    </div>
                </div>
                
                <div class="test-stats">
                    <div class="test-stat stat-total">
                        <div>{{ suite.total_tests }}</div>
                        <div>Total</div>
                    </div>
                    <div class="test-stat stat-passed">
                        <div>{{ suite.passed_tests }}</div>
                        <div>Passed</div>
                    </div>
                    <div class="test-stat stat-failed">
                        <div>{{ suite.failed_tests + suite.error_tests }}</div>
                        <div>Failed</div>
                    </div>
                    <div class="test-stat stat-skipped">
                        <div>{{ suite.skipped_tests }}</div>
                        <div>Skipped</div>
                    </div>
                </div>

                {% if suite.failed_tests > 0 or suite.error_tests > 0 %}
                <div class="failed-tests">
                    <h4>❌ Failed Tests</h4>
                    {% for test in suite.tests if test.status in ['failed', 'error'] %}
                    <div class="failed-test">
                        <div class="test-name">{{ test.name }}</div>
                        {% if test.message %}
                        <div class="test-message">{{ test.message[:200] }}{% if test.message|length > 200 %}...{% endif %}</div>
                        {% endif %}
                    </div>
                    {% endfor %}
                </div>
                {% endif %}
            </div>
            {% endfor %}
        </div>

        <!-- Slowest Tests -->
        {% if quality_metrics.slowest_tests %}
        <div class="slowest-tests">
            <h3>🐌 Slowest Tests</h3>
            <ul class="test-list">
                {% for test in quality_metrics.slowest_tests %}
                <li class="test-item">
                    <span>{{ test.name }}</span>
                    <span><strong>{{ test.duration }}</strong> ({{ test.suite }})</span>
                </li>
                {% endfor %}
            </ul>
        </div>
        {% endif %}

        <div class="footer">
            <p>Generated by PyAirtable Test Automation Framework</p>
            <p>Report created at {{ timestamp.strftime('%Y-%m-%d %H:%M:%S UTC') }}</p>
        </div>
    </div>
</body>
</html>
        """)
        
        return html_template.render(
            suite_results=suite_results,
            quality_metrics=quality_metrics,
            timestamp=self.timestamp,
            environment=self.environment
        )
    
    def generate_json_summary(self, suite_results: Dict[str, TestSuiteResult], 
                            quality_metrics: Dict[str, Any]) -> Dict[str, Any]:
        """Generate JSON summary for CI/CD integration"""
        summary = {
            "timestamp": self.timestamp.isoformat(),
            "environment": self.environment,
            "overall": quality_metrics["overall"],
            "critical_failures": quality_metrics["critical_failures"],
            "quality_score": quality_metrics["quality_score"]
        }
        
        # Add suite summaries
        for suite_key, suite_result in suite_results.items():
            summary[suite_key] = {
                "status": "✅ PASS" if suite_result.failed_tests == 0 and suite_result.error_tests == 0 else "❌ FAIL",
                "total": suite_result.total_tests,
                "passed": suite_result.passed_tests,
                "failed": suite_result.failed_tests + suite_result.error_tests,
                "success_rate": f"{suite_result.success_rate:.1f}%",
                "duration": f"{suite_result.total_duration:.2f}s"
            }
        
        return summary
    
    def generate_reports(self) -> bool:
        """Generate all reports"""
        try:
            logger.info("Starting test report generation...")
            
            # Find test files
            test_files = self.find_test_files()
            
            # Aggregate results
            suite_results = self.aggregate_test_results(test_files)
            
            # Calculate quality metrics
            quality_metrics = self.calculate_quality_metrics(suite_results)
            
            # Generate HTML report
            html_content = self.generate_html_report(suite_results, quality_metrics)
            html_file = self.output_dir / "comprehensive_test_report.html"
            with open(html_file, 'w', encoding='utf-8') as f:
                f.write(html_content)
            logger.info(f"HTML report generated: {html_file}")
            
            # Generate JSON summary
            json_summary = self.generate_json_summary(suite_results, quality_metrics)
            json_file = self.output_dir / "summary.json"
            with open(json_file, 'w', encoding='utf-8') as f:
                json.dump(json_summary, f, indent=2, default=str)
            logger.info(f"JSON summary generated: {json_file}")
            
            # Generate detailed JSON report
            detailed_report = {
                "metadata": {
                    "timestamp": self.timestamp.isoformat(),
                    "environment": self.environment,
                    "generator": "PyAirtable Test Automation Framework"
                },
                "quality_metrics": quality_metrics,
                "suite_results": {
                    suite_key: {
                        "name": suite.name,
                        "total_tests": suite.total_tests,
                        "passed_tests": suite.passed_tests,
                        "failed_tests": suite.failed_tests,
                        "skipped_tests": suite.skipped_tests,
                        "error_tests": suite.error_tests,
                        "success_rate": suite.success_rate,
                        "total_duration": suite.total_duration,
                        "tests": [
                            {
                                "name": test.name,
                                "status": test.status,
                                "duration": test.duration,
                                "message": test.message,
                                "suite": test.suite
                            }
                            for test in suite.tests
                        ]
                    }
                    for suite_key, suite in suite_results.items()
                }
            }
            
            detailed_file = self.output_dir / "detailed_test_report.json"
            with open(detailed_file, 'w', encoding='utf-8') as f:
                json.dump(detailed_report, f, indent=2, default=str)
            logger.info(f"Detailed report generated: {detailed_file}")
            
            # Print summary to console
            print("\n" + "="*80)
            print("🧪 PYAIRTABLE TEST REPORT SUMMARY")
            print("="*80)
            print(f"Environment: {self.environment}")
            print(f"Timestamp: {self.timestamp.strftime('%Y-%m-%d %H:%M:%S UTC')}")
            print(f"Total Tests: {quality_metrics['overall']['total_tests']}")
            print(f"Success Rate: {quality_metrics['overall']['success_rate']}")
            print(f"Critical Failures: {quality_metrics['critical_failures']}")
            print(f"Quality Score: {quality_metrics['quality_score']:.1f}%")
            print("-"*80)
            
            for suite_key, suite_result in suite_results.items():
                status_emoji = "✅" if suite_result.failed_tests == 0 and suite_result.error_tests == 0 else "❌"
                print(f"{status_emoji} {suite_result.name}: {suite_result.passed_tests}/{suite_result.total_tests} passed ({suite_result.success_rate:.1f}%)")
            
            print("="*80)
            
            return quality_metrics['critical_failures'] == 0 and quality_metrics['quality_score'] >= 70
            
        except Exception as e:
            logger.error(f"Error generating reports: {e}")
            return False


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Generate comprehensive test reports")
    parser.add_argument("--input-dir", required=True, help="Directory containing test results")
    parser.add_argument("--output-dir", required=True, help="Directory to output reports")
    parser.add_argument("--environment", default="ci", help="Test environment name")
    
    args = parser.parse_args()
    
    generator = TestReportGenerator(args.input_dir, args.output_dir, args.environment)
    success = generator.generate_reports()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()