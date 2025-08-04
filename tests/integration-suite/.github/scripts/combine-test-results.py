#!/usr/bin/env python3
"""
PyAirtable Integration Test Results Combiner

This script combines test results from multiple test categories into unified reports
supporting multiple output formats (HTML, JSON, JUnit XML).
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
import xml.etree.ElementTree as ET
from xml.dom import minidom
import glob

@dataclass
class TestResult:
    name: str
    category: str
    status: str  # passed, failed, skipped
    duration: float
    error_message: Optional[str] = None
    stack_trace: Optional[str] = None
    output: Optional[str] = None

@dataclass
class TestSuite:
    name: str
    category: str
    total_tests: int
    passed: int
    failed: int
    skipped: int
    duration: float
    tests: List[TestResult]
    timestamp: str

@dataclass
class CombinedResults:
    suites: List[TestSuite]
    total_tests: int
    total_passed: int
    total_failed: int
    total_skipped: int
    total_duration: float
    overall_status: str
    timestamp: str
    metadata: Dict[str, Any]

class TestResultsCombiner:
    def __init__(self, input_dir: str, output_dir: str):
        self.input_dir = Path(input_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
    def combine_results(self) -> CombinedResults:
        """Combine all test results from input directory."""
        suites = []
        
        # Find all test result directories
        for category_dir in self.input_dir.iterdir():
            if category_dir.is_dir() and category_dir.name.startswith('test-results-'):
                category = category_dir.name.replace('test-results-', '').replace(f'-{os.environ.get("GITHUB_RUN_NUMBER", "0")}', '')
                suite = self._process_category_results(category_dir, category)
                if suite:
                    suites.append(suite)
        
        # Calculate totals
        total_tests = sum(suite.total_tests for suite in suites)
        total_passed = sum(suite.passed for suite in suites)
        total_failed = sum(suite.failed for suite in suites)
        total_skipped = sum(suite.skipped for suite in suites)
        total_duration = sum(suite.duration for suite in suites)
        
        overall_status = "passed" if total_failed == 0 else "failed"
        
        return CombinedResults(
            suites=suites,
            total_tests=total_tests,
            total_passed=total_passed,
            total_failed=total_failed,
            total_skipped=total_skipped,
            total_duration=total_duration,
            overall_status=overall_status,
            timestamp=datetime.utcnow().isoformat(),
            metadata={
                "github_ref": os.environ.get("GITHUB_REF", ""),
                "github_sha": os.environ.get("GITHUB_SHA", ""),
                "github_run_id": os.environ.get("GITHUB_RUN_ID", ""),
                "github_run_number": os.environ.get("GITHUB_RUN_NUMBER", ""),
                "github_actor": os.environ.get("GITHUB_ACTOR", ""),
                "github_workflow": os.environ.get("GITHUB_WORKFLOW", ""),
            }
        )
    
    def _process_category_results(self, category_dir: Path, category: str) -> Optional[TestSuite]:
        """Process test results for a specific category."""
        tests = []
        
        # Look for different result formats
        json_files = list(category_dir.glob("*.json"))
        xml_files = list(category_dir.glob("*.xml"))
        go_test_files = list(category_dir.glob("*test*.log"))
        
        # Process JSON results (from k6, custom tools)
        for json_file in json_files:
            try:
                with open(json_file, 'r') as f:
                    data = json.load(f)
                    tests.extend(self._parse_json_results(data, category))
            except Exception as e:
                print(f"Error parsing JSON file {json_file}: {e}")
        
        # Process XML results (JUnit format)
        for xml_file in xml_files:
            try:
                tests.extend(self._parse_xml_results(xml_file, category))
            except Exception as e:
                print(f"Error parsing XML file {xml_file}: {e}")
        
        # Process Go test output
        for log_file in go_test_files:
            try:
                tests.extend(self._parse_go_test_output(log_file, category))
            except Exception as e:
                print(f"Error parsing Go test file {log_file}: {e}")
        
        if not tests:
            return None
        
        # Calculate suite statistics
        total_tests = len(tests)
        passed = sum(1 for t in tests if t.status == "passed")
        failed = sum(1 for t in tests if t.status == "failed")
        skipped = sum(1 for t in tests if t.status == "skipped")
        duration = sum(t.duration for t in tests)
        
        return TestSuite(
            name=f"{category.title()} Tests",
            category=category,
            total_tests=total_tests,
            passed=passed,
            failed=failed,
            skipped=skipped,
            duration=duration,
            tests=tests,
            timestamp=datetime.utcnow().isoformat()
        )
    
    def _parse_json_results(self, data: Dict, category: str) -> List[TestResult]:
        """Parse JSON test results (k6, custom formats)."""
        tests = []
        
        if category == "performance" and "metrics" in data:
            # k6 results format
            for metric_name, metric_data in data["metrics"].items():
                if "checks" in metric_name:
                    for check_name, check_data in metric_data.get("values", {}).items():
                        tests.append(TestResult(
                            name=check_name,
                            category=category,
                            status="passed" if check_data.get("rate", 0) > 0.95 else "failed",
                            duration=check_data.get("avg", 0),
                            error_message=None if check_data.get("rate", 0) > 0.95 else "Check failed"
                        ))
        
        elif "test_results" in data:
            # Custom test results format
            for test_data in data["test_results"]:
                tests.append(TestResult(
                    name=test_data.get("name", "Unknown"),
                    category=category,
                    status=test_data.get("status", "unknown"),
                    duration=test_data.get("duration", 0),
                    error_message=test_data.get("error"),
                    output=test_data.get("output")
                ))
        
        return tests
    
    def _parse_xml_results(self, xml_file: Path, category: str) -> List[TestResult]:
        """Parse JUnit XML test results."""
        tests = []
        
        try:
            tree = ET.parse(xml_file)
            root = tree.getroot()
            
            for testcase in root.findall(".//testcase"):
                name = testcase.get("name", "Unknown")
                duration = float(testcase.get("time", "0"))
                
                # Determine status
                if testcase.find("failure") is not None:
                    status = "failed"
                    error_element = testcase.find("failure")
                    error_message = error_element.get("message", "")
                    stack_trace = error_element.text
                elif testcase.find("error") is not None:
                    status = "failed"
                    error_element = testcase.find("error")
                    error_message = error_element.get("message", "")
                    stack_trace = error_element.text
                elif testcase.find("skipped") is not None:
                    status = "skipped"
                    error_message = None
                    stack_trace = None
                else:
                    status = "passed"
                    error_message = None
                    stack_trace = None
                
                tests.append(TestResult(
                    name=name,
                    category=category,
                    status=status,
                    duration=duration,
                    error_message=error_message,
                    stack_trace=stack_trace
                ))
        
        except ET.ParseError as e:
            print(f"Error parsing XML file {xml_file}: {e}")
        
        return tests
    
    def _parse_go_test_output(self, log_file: Path, category: str) -> List[TestResult]:
        """Parse Go test output logs."""
        tests = []
        
        try:
            with open(log_file, 'r') as f:
                content = f.read()
            
            # Parse Go test output format
            lines = content.split('\n')
            current_test = None
            
            for line in lines:
                line = line.strip()
                
                if line.startswith("=== RUN"):
                    current_test = line.replace("=== RUN", "").strip()
                elif line.startswith("--- PASS:") and current_test:
                    duration_str = line.split("(")[1].split(")")[0] if "(" in line else "0s"
                    duration = self._parse_duration(duration_str)
                    tests.append(TestResult(
                        name=current_test,
                        category=category,
                        status="passed",
                        duration=duration
                    ))
                    current_test = None
                elif line.startswith("--- FAIL:") and current_test:
                    duration_str = line.split("(")[1].split(")")[0] if "(" in line else "0s"
                    duration = self._parse_duration(duration_str)
                    tests.append(TestResult(
                        name=current_test,
                        category=category,
                        status="failed",
                        duration=duration,
                        error_message="Test failed"
                    ))
                    current_test = None
                elif line.startswith("--- SKIP:") and current_test:
                    tests.append(TestResult(
                        name=current_test,
                        category=category,
                        status="skipped",
                        duration=0
                    ))
                    current_test = None
        
        except Exception as e:
            print(f"Error parsing Go test file {log_file}: {e}")
        
        return tests
    
    def _parse_duration(self, duration_str: str) -> float:
        """Parse Go duration string to seconds."""
        try:
            if duration_str.endswith("s"):
                return float(duration_str[:-1])
            elif duration_str.endswith("ms"):
                return float(duration_str[:-2]) / 1000
            elif duration_str.endswith("µs"):
                return float(duration_str[:-2]) / 1000000
            elif duration_str.endswith("ns"):
                return float(duration_str[:-2]) / 1000000000
            else:
                return 0.0
        except:
            return 0.0
    
    def generate_html_report(self, results: CombinedResults, output_file: str):
        """Generate HTML report."""
        html_template = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PyAirtable Integration Test Results</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 8px 8px 0 0; }
        .header h1 { margin: 0; font-size: 2.5rem; }
        .header p { margin: 10px 0 0 0; opacity: 0.9; }
        .summary { padding: 30px; display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
        .stat-card { background: #f8f9fa; padding: 20px; border-radius: 8px; text-align: center; border-left: 4px solid #667eea; }
        .stat-number { font-size: 2rem; font-weight: bold; color: #333; }
        .stat-label { color: #666; margin-top: 5px; }
        .status-passed { border-left-color: #28a745; }
        .status-failed { border-left-color: #dc3545; }
        .status-skipped { border-left-color: #ffc107; }
        .suites { padding: 0 30px 30px; }
        .suite { margin-bottom: 30px; border: 1px solid #dee2e6; border-radius: 8px; overflow: hidden; }
        .suite-header { background: #f8f9fa; padding: 20px; border-bottom: 1px solid #dee2e6; }
        .suite-title { margin: 0; font-size: 1.25rem; color: #333; }
        .suite-stats { display: flex; gap: 20px; margin-top: 10px; }
        .suite-stat { font-size: 0.9rem; color: #666; }
        .tests-table { width: 100%; border-collapse: collapse; }
        .tests-table th, .tests-table td { padding: 12px; text-align: left; border-bottom: 1px solid #dee2e6; }
        .tests-table th { background: #f8f9fa; font-weight: 600; }
        .status-badge { padding: 4px 8px; border-radius: 4px; font-size: 0.8rem; font-weight: 500; }
        .badge-passed { background: #d4edda; color: #155724; }
        .badge-failed { background: #f8d7da; color: #721c24; }
        .badge-skipped { background: #fff3cd; color: #856404; }
        .duration { color: #666; font-family: monospace; }
        .error-message { color: #dc3545; font-size: 0.9rem; max-width: 300px; overflow: hidden; text-overflow: ellipsis; }
        .metadata { padding: 20px 30px; background: #f8f9fa; border-top: 1px solid #dee2e6; }
        .metadata-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 10px; }
        .metadata-item { display: flex; justify-content: space-between; }
        .metadata-label { color: #666; }
        .metadata-value { font-family: monospace; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Integration Test Results</h1>
            <p>Generated on {timestamp}</p>
        </div>
        
        <div class="summary">
            <div class="stat-card">
                <div class="stat-number">{total_tests}</div>
                <div class="stat-label">Total Tests</div>
            </div>
            <div class="stat-card status-passed">
                <div class="stat-number">{total_passed}</div>
                <div class="stat-label">Passed</div>
            </div>
            <div class="stat-card status-failed">
                <div class="stat-number">{total_failed}</div>
                <div class="stat-label">Failed</div>
            </div>
            <div class="stat-card status-skipped">
                <div class="stat-number">{total_skipped}</div>
                <div class="stat-label">Skipped</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">{total_duration:.1f}s</div>
                <div class="stat-label">Total Duration</div>
            </div>
            <div class="stat-card {overall_status_class}">
                <div class="stat-number">{overall_status_text}</div>
                <div class="stat-label">Overall Status</div>
            </div>
        </div>
        
        <div class="suites">
            {suites_html}
        </div>
        
        <div class="metadata">
            <h3>Build Information</h3>
            <div class="metadata-grid">
                {metadata_html}
            </div>
        </div>
    </div>
</body>
</html>
        """
        
        # Generate suites HTML
        suites_html = ""
        for suite in results.suites:
            suite_html = f"""
            <div class="suite">
                <div class="suite-header">
                    <h3 class="suite-title">{suite.name}</h3>
                    <div class="suite-stats">
                        <span class="suite-stat">Tests: {suite.total_tests}</span>
                        <span class="suite-stat">Passed: {suite.passed}</span>
                        <span class="suite-stat">Failed: {suite.failed}</span>
                        <span class="suite-stat">Duration: {suite.duration:.1f}s</span>
                    </div>
                </div>
                <table class="tests-table">
                    <thead>
                        <tr>
                            <th>Test Name</th>
                            <th>Status</th>
                            <th>Duration</th>
                            <th>Error</th>
                        </tr>
                    </thead>
                    <tbody>
            """
            
            for test in suite.tests:
                status_class = f"badge-{test.status}"
                error_display = test.error_message or ""
                
                suite_html += f"""
                        <tr>
                            <td>{test.name}</td>
                            <td><span class="status-badge {status_class}">{test.status.title()}</span></td>
                            <td class="duration">{test.duration:.3f}s</td>
                            <td class="error-message">{error_display}</td>
                        </tr>
                """
            
            suite_html += """
                    </tbody>
                </table>
            </div>
            """
            suites_html += suite_html
        
        # Generate metadata HTML
        metadata_html = ""
        for key, value in results.metadata.items():
            if value:
                metadata_html += f"""
                <div class="metadata-item">
                    <span class="metadata-label">{key.replace('_', ' ').title()}:</span>
                    <span class="metadata-value">{value}</span>
                </div>
                """
        
        # Fill template
        html_content = html_template.format(
            timestamp=results.timestamp,
            total_tests=results.total_tests,
            total_passed=results.total_passed,
            total_failed=results.total_failed,
            total_skipped=results.total_skipped,
            total_duration=results.total_duration,
            overall_status_text=results.overall_status.title(),
            overall_status_class=f"status-{results.overall_status}",
            suites_html=suites_html,
            metadata_html=metadata_html
        )
        
        # Write HTML file
        with open(self.output_dir / output_file, 'w') as f:
            f.write(html_content)
    
    def generate_json_report(self, results: CombinedResults, output_file: str):
        """Generate JSON report."""
        json_data = {
            "timestamp": results.timestamp,
            "overall_status": results.overall_status,
            "summary": {
                "total_tests": results.total_tests,
                "total_passed": results.total_passed,
                "total_failed": results.total_failed,
                "total_skipped": results.total_skipped,
                "total_duration": results.total_duration
            },
            "suites": [
                {
                    "name": suite.name,
                    "category": suite.category,
                    "total_tests": suite.total_tests,
                    "passed": suite.passed,
                    "failed": suite.failed,
                    "skipped": suite.skipped,
                    "duration": suite.duration,
                    "timestamp": suite.timestamp,
                    "tests": [
                        {
                            "name": test.name,
                            "status": test.status,
                            "duration": test.duration,
                            "error_message": test.error_message,
                            "output": test.output
                        }
                        for test in suite.tests
                    ]
                }
                for suite in results.suites
            ],
            "metadata": results.metadata
        }
        
        with open(self.output_dir / output_file, 'w') as f:
            json.dump(json_data, f, indent=2)
    
    def generate_junit_report(self, results: CombinedResults, output_file: str):
        """Generate JUnit XML report."""
        root = ET.Element("testsuites")
        root.set("name", "PyAirtable Integration Tests")
        root.set("tests", str(results.total_tests))
        root.set("failures", str(results.total_failed))
        root.set("skipped", str(results.total_skipped))
        root.set("time", str(results.total_duration))
        root.set("timestamp", results.timestamp)
        
        for suite in results.suites:
            testsuite = ET.SubElement(root, "testsuite")
            testsuite.set("name", suite.name)
            testsuite.set("tests", str(suite.total_tests))
            testsuite.set("failures", str(suite.failed))
            testsuite.set("skipped", str(suite.skipped))
            testsuite.set("time", str(suite.duration))
            testsuite.set("timestamp", suite.timestamp)
            
            for test in suite.tests:
                testcase = ET.SubElement(testsuite, "testcase")
                testcase.set("name", test.name)
                testcase.set("classname", f"{suite.category}.{test.name}")
                testcase.set("time", str(test.duration))
                
                if test.status == "failed":
                    failure = ET.SubElement(testcase, "failure")
                    failure.set("message", test.error_message or "Test failed")
                    if test.stack_trace:
                        failure.text = test.stack_trace
                elif test.status == "skipped":
                    ET.SubElement(testcase, "skipped")
                
                if test.output:
                    system_out = ET.SubElement(testcase, "system-out")
                    system_out.text = test.output
        
        # Write formatted XML
        rough_string = ET.tostring(root, 'unicode')
        reparsed = minidom.parseString(rough_string)
        
        with open(self.output_dir / output_file, 'w') as f:
            f.write(reparsed.toprettyxml(indent="  "))

def main():
    parser = argparse.ArgumentParser(description="Combine PyAirtable integration test results")
    parser.add_argument("--input-dir", required=True, help="Directory containing test results")
    parser.add_argument("--output-dir", required=True, help="Output directory for combined results")
    parser.add_argument("--format", default="html,json,junit", help="Output formats (comma-separated)")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.input_dir):
        print(f"Error: Input directory {args.input_dir} does not exist")
        sys.exit(1)
    
    # Initialize combiner
    combiner = TestResultsCombiner(args.input_dir, args.output_dir)
    
    # Combine results
    print("Combining test results...")
    results = combiner.combine_results()
    
    # Generate reports in requested formats
    formats = [f.strip().lower() for f in args.format.split(',')]
    
    if 'html' in formats:
        print("Generating HTML report...")
        combiner.generate_html_report(results, "report.html")
    
    if 'json' in formats:
        print("Generating JSON report...")
        combiner.generate_json_report(results, "report.json")
    
    if 'junit' in formats:
        print("Generating JUnit XML report...")
        combiner.generate_junit_report(results, "junit.xml")
    
    # Print summary
    print(f"\nTest Results Summary:")
    print(f"Total Tests: {results.total_tests}")
    print(f"Passed: {results.total_passed}")
    print(f"Failed: {results.total_failed}")
    print(f"Skipped: {results.total_skipped}")
    print(f"Duration: {results.total_duration:.1f}s")
    print(f"Overall Status: {results.overall_status.upper()}")
    
    # Exit with appropriate code
    sys.exit(0 if results.overall_status == "passed" else 1)

if __name__ == "__main__":
    main()