#!/usr/bin/env python3
"""
PyAirtable Integration Test Metrics Generator

This script generates comprehensive metrics from integration test results
for monitoring, alerting, and trend analysis.
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional
from datetime import datetime
import statistics
import glob

class MetricsGenerator:
    def __init__(self, input_dir: str):
        self.input_dir = Path(input_dir)
        
    def generate_metrics(self) -> Dict[str, Any]:
        """Generate comprehensive metrics from test results."""
        
        categories = []
        overall_metrics = {
            "total_tests": 0,
            "total_passed": 0,
            "total_failed": 0,
            "total_skipped": 0,
            "total_duration": 0.0,
            "success_rate": 0.0,
            "overall_status": "unknown"
        }
        
        performance_metrics = {}
        reliability_metrics = {}
        coverage_metrics = {}
        
        # Process each test category
        for category_dir in self.input_dir.iterdir():
            if category_dir.is_dir() and category_dir.name.startswith('test-results-'):
                category = category_dir.name.replace('test-results-', '').replace(f'-{os.environ.get("GITHUB_RUN_NUMBER", "0")}', '')
                
                category_metrics = self._process_category_metrics(category_dir, category)
                if category_metrics:
                    categories.append(category_metrics)
                    
                    # Aggregate overall metrics
                    overall_metrics["total_tests"] += category_metrics["total"]
                    overall_metrics["total_passed"] += category_metrics["passed"]
                    overall_metrics["total_failed"] += category_metrics["failed"] 
                    overall_metrics["total_skipped"] += category_metrics["skipped"]
                    overall_metrics["total_duration"] += category_metrics["duration"]
                    
                    # Collect performance metrics
                    if category == "performance":
                        performance_metrics = self._extract_performance_metrics(category_dir)
                    
                    # Collect reliability metrics
                    if category in ["chaos", "stress"]:
                        reliability_metrics.update(self._extract_reliability_metrics(category_dir, category))
        
        # Calculate derived metrics
        if overall_metrics["total_tests"] > 0:
            overall_metrics["success_rate"] = overall_metrics["total_passed"] / overall_metrics["total_tests"]
            overall_metrics["overall_status"] = "passed" if overall_metrics["total_failed"] == 0 else "failed"
        
        # Generate quality score
        quality_score = self._calculate_quality_score(overall_metrics, performance_metrics, reliability_metrics)
        
        # Generate trend analysis
        trend_metrics = self._generate_trend_metrics(categories)
        
        # Build final metrics structure
        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
            "build_info": {
                "commit": os.environ.get("GITHUB_SHA", ""),
                "branch": os.environ.get("GITHUB_REF_NAME", ""),
                "run_id": os.environ.get("GITHUB_RUN_ID", ""),
                "run_number": os.environ.get("GITHUB_RUN_NUMBER", ""),
                "actor": os.environ.get("GITHUB_ACTOR", ""),
                "workflow": os.environ.get("GITHUB_WORKFLOW", ""),
            },
            "overall": overall_metrics,
            "categories": categories,
            "performance": performance_metrics,
            "reliability": reliability_metrics,
            "coverage": coverage_metrics,
            "quality_score": quality_score,
            "trends": trend_metrics,
            "alerts": self._generate_alerts(overall_metrics, performance_metrics, reliability_metrics),
            "recommendations": self._generate_recommendations(overall_metrics, performance_metrics, reliability_metrics)
        }
        
        return metrics
    
    def _process_category_metrics(self, category_dir: Path, category: str) -> Optional[Dict[str, Any]]:
        """Process metrics for a specific test category."""
        
        # Initialize counters
        total = passed = failed = skipped = 0
        duration = 0.0
        test_durations = []
        error_types = {}
        
        # Look for test result files
        json_files = list(category_dir.glob("*.json"))
        xml_files = list(category_dir.glob("*.xml"))
        log_files = list(category_dir.glob("*test*.log"))
        
        # Process different file types
        for json_file in json_files:
            metrics = self._parse_json_metrics(json_file)
            if metrics:
                total += metrics.get("total", 0)
                passed += metrics.get("passed", 0)
                failed += metrics.get("failed", 0)
                skipped += metrics.get("skipped", 0)
                duration += metrics.get("duration", 0)
                test_durations.extend(metrics.get("durations", []))
                
                # Collect error types
                for error_type, count in metrics.get("error_types", {}).items():
                    error_types[error_type] = error_types.get(error_type, 0) + count
        
        # Process XML files (JUnit format)
        for xml_file in xml_files:
            metrics = self._parse_xml_metrics(xml_file)
            if metrics:
                total += metrics.get("total", 0)
                passed += metrics.get("passed", 0)
                failed += metrics.get("failed", 0)
                skipped += metrics.get("skipped", 0)
                duration += metrics.get("duration", 0)
                test_durations.extend(metrics.get("durations", []))
        
        # Process log files
        for log_file in log_files:
            metrics = self._parse_log_metrics(log_file)
            if metrics:
                total += metrics.get("total", 0)
                passed += metrics.get("passed", 0)
                failed += metrics.get("failed", 0)
                skipped += metrics.get("skipped", 0)
                duration += metrics.get("duration", 0)
                test_durations.extend(metrics.get("durations", []))
        
        if total == 0:
            return None
        
        # Calculate statistics
        success_rate = passed / total if total > 0 else 0
        failure_rate = failed / total if total > 0 else 0
        
        # Duration statistics
        duration_stats = {}
        if test_durations:
            duration_stats = {
                "min": min(test_durations),
                "max": max(test_durations),
                "mean": statistics.mean(test_durations),
                "median": statistics.median(test_durations),
                "p95": self._percentile(test_durations, 95),
                "p99": self._percentile(test_durations, 99)
            }
        
        return {
            "name": category,
            "status": "passed" if failed == 0 else "failed",
            "total": total,
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "duration": duration,
            "success_rate": success_rate,
            "failure_rate": failure_rate,
            "duration_stats": duration_stats,
            "error_types": error_types,
            "category_specific": self._get_category_specific_metrics(category_dir, category)
        }
    
    def _parse_json_metrics(self, json_file: Path) -> Optional[Dict[str, Any]]:
        """Parse metrics from JSON files."""
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
            
            # Handle different JSON formats
            if "test_results" in data:
                # Custom test results format
                tests = data["test_results"]
                total = len(tests)
                passed = sum(1 for t in tests if t.get("status") == "passed")
                failed = sum(1 for t in tests if t.get("status") == "failed")
                skipped = sum(1 for t in tests if t.get("status") == "skipped")
                duration = sum(t.get("duration", 0) for t in tests)
                durations = [t.get("duration", 0) for t in tests]
                
                return {
                    "total": total,
                    "passed": passed,
                    "failed": failed,
                    "skipped": skipped,
                    "duration": duration,
                    "durations": durations
                }
            
            elif "metrics" in data:
                # k6 or performance test format
                return self._parse_k6_metrics(data)
            
        except Exception as e:
            print(f"Error parsing JSON file {json_file}: {e}")
        
        return None
    
    def _parse_xml_metrics(self, xml_file: Path) -> Optional[Dict[str, Any]]:
        """Parse metrics from XML files (JUnit format)."""
        try:
            import xml.etree.ElementTree as ET
            tree = ET.parse(xml_file)
            root = tree.getroot()
            
            total = failed = skipped = 0
            duration = 0.0
            durations = []
            
            for testcase in root.findall(".//testcase"):
                total += 1
                test_duration = float(testcase.get("time", "0"))
                duration += test_duration
                durations.append(test_duration)
                
                if testcase.find("failure") is not None or testcase.find("error") is not None:
                    failed += 1
                elif testcase.find("skipped") is not None:
                    skipped += 1
            
            passed = total - failed - skipped
            
            return {
                "total": total,
                "passed": passed,
                "failed": failed,
                "skipped": skipped,
                "duration": duration,
                "durations": durations
            }
            
        except Exception as e:
            print(f"Error parsing XML file {xml_file}: {e}")
        
        return None
    
    def _parse_log_metrics(self, log_file: Path) -> Optional[Dict[str, Any]]:
        """Parse metrics from log files."""
        try:
            with open(log_file, 'r') as f:
                content = f.read()
            
            # Count test results from Go test output
            total = content.count("=== RUN")
            passed = content.count("--- PASS:")
            failed = content.count("--- FAIL:")
            skipped = content.count("--- SKIP:")
            
            # Extract durations (simplified)
            import re
            duration_matches = re.findall(r'\((\d+\.\d+)s\)', content)
            durations = [float(d) for d in duration_matches]
            total_duration = sum(durations)
            
            if total > 0:
                return {
                    "total": total,
                    "passed": passed,
                    "failed": failed,
                    "skipped": skipped,
                    "duration": total_duration,
                    "durations": durations
                }
            
        except Exception as e:
            print(f"Error parsing log file {log_file}: {e}")
        
        return None
    
    def _parse_k6_metrics(self, data: Dict) -> Optional[Dict[str, Any]]:
        """Parse k6 performance test metrics."""
        try:
            metrics = data.get("metrics", {})
            
            # Extract key metrics
            http_req_duration = metrics.get("http_req_duration", {}).get("values", {})
            http_req_failed = metrics.get("http_req_failed", {}).get("values", {})
            iterations = metrics.get("iterations", {}).get("values", {})
            
            # Convert to test-like metrics
            total_requests = iterations.get("count", 0)
            failed_requests = int(total_requests * http_req_failed.get("rate", 0))
            passed_requests = total_requests - failed_requests
            
            return {
                "total": int(total_requests),
                "passed": passed_requests,
                "failed": failed_requests,
                "skipped": 0,
                "duration": http_req_duration.get("avg", 0) * total_requests / 1000,  # Convert to seconds
                "durations": [],
                "performance_metrics": {
                    "avg_duration": http_req_duration.get("avg", 0),
                    "p90_duration": http_req_duration.get("p(90)", 0),
                    "p95_duration": http_req_duration.get("p(95)", 0),
                    "p99_duration": http_req_duration.get("p(99)", 0),
                    "failure_rate": http_req_failed.get("rate", 0),
                    "total_requests": total_requests
                }
            }
            
        except Exception as e:
            print(f"Error parsing k6 metrics: {e}")
        
        return None
    
    def _extract_performance_metrics(self, category_dir: Path) -> Dict[str, Any]:
        """Extract performance-specific metrics."""
        performance_metrics = {
            "response_times": {},
            "throughput": {},
            "error_rates": {},
            "resource_usage": {},
            "sla_compliance": {}
        }
        
        # Look for k6 results
        k6_files = list(category_dir.glob("*k6*.json"))
        for k6_file in k6_files:
            try:
                with open(k6_file, 'r') as f:
                    data = json.load(f)
                
                metrics = data.get("metrics", {})
                
                # Response time metrics
                http_duration = metrics.get("http_req_duration", {}).get("values", {})
                performance_metrics["response_times"] = {
                    "avg": http_duration.get("avg", 0),
                    "min": http_duration.get("min", 0),
                    "max": http_duration.get("max", 0),
                    "p50": http_duration.get("p(50)", 0),
                    "p90": http_duration.get("p(90)", 0),
                    "p95": http_duration.get("p(95)", 0),
                    "p99": http_duration.get("p(99)", 0)
                }
                
                # Throughput metrics
                iterations = metrics.get("iterations", {}).get("values", {})
                performance_metrics["throughput"] = {
                    "total_requests": iterations.get("count", 0),
                    "requests_per_second": iterations.get("rate", 0)
                }
                
                # Error rate metrics
                http_failures = metrics.get("http_req_failed", {}).get("values", {})
                performance_metrics["error_rates"] = {
                    "failure_rate": http_failures.get("rate", 0),
                    "total_failures": http_failures.get("count", 0)
                }
                
                # SLA compliance
                performance_metrics["sla_compliance"] = self._calculate_sla_compliance(performance_metrics)
                
            except Exception as e:
                print(f"Error extracting performance metrics from {k6_file}: {e}")
        
        return performance_metrics
    
    def _extract_reliability_metrics(self, category_dir: Path, category: str) -> Dict[str, Any]:
        """Extract reliability and resilience metrics."""
        reliability_metrics = {
            "chaos_experiments": {},
            "recovery_times": {},
            "availability": {},
            "fault_tolerance": {}
        }
        
        # Look for chaos test results
        if category == "chaos":
            chaos_files = list(category_dir.glob("*chaos*.json"))
            for chaos_file in chaos_files:
                try:
                    with open(chaos_file, 'r') as f:
                        data = json.load(f)
                    
                    # Extract chaos experiment results
                    reliability_metrics["chaos_experiments"] = data.get("experiments", {})
                    reliability_metrics["recovery_times"] = data.get("recovery_times", {})
                    reliability_metrics["fault_tolerance"] = data.get("fault_tolerance", {})
                    
                except Exception as e:
                    print(f"Error extracting reliability metrics from {chaos_file}: {e}")
        
        return reliability_metrics
    
    def _get_category_specific_metrics(self, category_dir: Path, category: str) -> Dict[str, Any]:
        """Get category-specific metrics."""
        specific_metrics = {}
        
        if category == "security":
            # Extract security scan results
            security_files = list(category_dir.glob("*security*.json"))
            for security_file in security_files:
                try:
                    with open(security_file, 'r') as f:
                        data = json.load(f)
                    specific_metrics["vulnerabilities"] = data.get("vulnerabilities", [])
                    specific_metrics["security_score"] = data.get("security_score", 0)
                except:
                    pass
        
        elif category == "contract":
            # Extract contract test results
            contract_files = list(category_dir.glob("*contract*.json"))
            for contract_file in contract_files:
                try:
                    with open(contract_file, 'r') as f:
                        data = json.load(f)
                    specific_metrics["contract_violations"] = data.get("violations", [])
                    specific_metrics["api_compatibility"] = data.get("compatibility_score", 0)
                except:
                    pass
        
        return specific_metrics
    
    def _calculate_quality_score(self, overall_metrics: Dict, performance_metrics: Dict, reliability_metrics: Dict) -> Dict[str, Any]:
        """Calculate overall quality score."""
        
        # Base score from test success rate
        base_score = overall_metrics.get("success_rate", 0) * 100
        
        # Performance score
        performance_score = 100
        if performance_metrics.get("response_times"):
            p95 = performance_metrics["response_times"].get("p95", 0)
            if p95 > 500:  # 500ms threshold
                performance_score -= min(50, (p95 - 500) / 10)
        
        # Reliability score
        reliability_score = 100
        if reliability_metrics.get("chaos_experiments"):
            failed_experiments = sum(1 for exp in reliability_metrics["chaos_experiments"].values() if not exp.get("passed", True))
            total_experiments = len(reliability_metrics["chaos_experiments"])
            if total_experiments > 0:
                reliability_score = (total_experiments - failed_experiments) / total_experiments * 100
        
        # Calculate weighted average
        weights = {"base": 0.5, "performance": 0.3, "reliability": 0.2}
        overall_score = (
            base_score * weights["base"] +
            performance_score * weights["performance"] +
            reliability_score * weights["reliability"]
        )
        
        return {
            "overall": round(overall_score, 1),
            "components": {
                "test_success": round(base_score, 1),
                "performance": round(performance_score, 1),
                "reliability": round(reliability_score, 1)
            },
            "grade": self._score_to_grade(overall_score)
        }
    
    def _generate_trend_metrics(self, categories: List[Dict]) -> Dict[str, Any]:
        """Generate trend analysis metrics."""
        # This would typically compare with historical data
        # For now, return current snapshot
        return {
            "test_count_trend": "stable",
            "success_rate_trend": "stable", 
            "duration_trend": "stable",
            "quality_trend": "stable"
        }
    
    def _generate_alerts(self, overall_metrics: Dict, performance_metrics: Dict, reliability_metrics: Dict) -> List[Dict[str, Any]]:
        """Generate alerts based on metrics."""
        alerts = []
        
        # Test failure alerts
        if overall_metrics.get("total_failed", 0) > 0:
            alerts.append({
                "type": "test_failure",
                "severity": "high" if overall_metrics["total_failed"] > 5 else "medium",
                "message": f"{overall_metrics['total_failed']} tests failed",
                "recommendation": "Review failed tests and fix issues"
            })
        
        # Performance alerts
        if performance_metrics.get("response_times", {}).get("p95", 0) > 500:
            alerts.append({
                "type": "performance_degradation",
                "severity": "medium",
                "message": f"95th percentile response time is {performance_metrics['response_times']['p95']}ms",
                "recommendation": "Investigate performance bottlenecks"
            })
        
        # Success rate alerts
        if overall_metrics.get("success_rate", 1) < 0.95:
            alerts.append({
                "type": "low_success_rate",
                "severity": "high",
                "message": f"Success rate is {overall_metrics['success_rate']*100:.1f}%",
                "recommendation": "Improve test stability and fix failing tests"
            })
        
        return alerts
    
    def _generate_recommendations(self, overall_metrics: Dict, performance_metrics: Dict, reliability_metrics: Dict) -> List[str]:
        """Generate improvement recommendations."""
        recommendations = []
        
        success_rate = overall_metrics.get("success_rate", 1)
        if success_rate < 0.9:
            recommendations.append("Focus on improving test stability - success rate is below 90%")
        
        if performance_metrics.get("response_times", {}).get("p95", 0) > 300:
            recommendations.append("Optimize application performance - response times are above target")
        
        if overall_metrics.get("total_duration", 0) > 1800:  # 30 minutes
            recommendations.append("Consider parallelizing tests to reduce execution time")
        
        if not recommendations:
            recommendations.append("All metrics look good - maintain current practices")
        
        return recommendations
    
    def _calculate_sla_compliance(self, performance_metrics: Dict) -> Dict[str, Any]:
        """Calculate SLA compliance metrics."""
        response_times = performance_metrics.get("response_times", {})
        error_rates = performance_metrics.get("error_rates", {})
        
        # Define SLA thresholds
        sla_thresholds = {
            "p95_response_time": 500,  # ms
            "p99_response_time": 1000,  # ms
            "error_rate": 0.01  # 1%
        }
        
        compliance = {}
        
        # Check response time SLAs
        p95 = response_times.get("p95", 0)
        p99 = response_times.get("p99", 0)
        error_rate = error_rates.get("failure_rate", 0)
        
        compliance["p95_response_time"] = p95 <= sla_thresholds["p95_response_time"]
        compliance["p99_response_time"] = p99 <= sla_thresholds["p99_response_time"]
        compliance["error_rate"] = error_rate <= sla_thresholds["error_rate"]
        
        compliance["overall"] = all(compliance.values())
        compliance["score"] = sum(compliance.values()) / len(compliance) * 100
        
        return compliance
    
    def _percentile(self, data: List[float], percentile: float) -> float:
        """Calculate percentile of a list."""
        if not data:
            return 0.0
        sorted_data = sorted(data)
        index = int(len(sorted_data) * percentile / 100)
        return sorted_data[min(index, len(sorted_data) - 1)]
    
    def _score_to_grade(self, score: float) -> str:
        """Convert numeric score to letter grade."""
        if score >= 95:
            return "A+"
        elif score >= 90:
            return "A"
        elif score >= 85:
            return "B+"
        elif score >= 80:
            return "B"
        elif score >= 75:
            return "C+"
        elif score >= 70:
            return "C"
        elif score >= 65:
            return "D+"
        elif score >= 60:
            return "D"
        else:
            return "F"

def main():
    parser = argparse.ArgumentParser(description="Generate PyAirtable integration test metrics")
    parser.add_argument("--input-dir", required=True, help="Directory containing test results")
    parser.add_argument("--output", required=True, help="Output file for metrics")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.input_dir):
        print(f"Error: Input directory {args.input_dir} does not exist")
        sys.exit(1)
    
    # Generate metrics
    generator = MetricsGenerator(args.input_dir)
    metrics = generator.generate_metrics()
    
    # Write metrics to file
    with open(args.output, 'w') as f:
        json.dump(metrics, f, indent=2)
    
    # Print summary
    print(f"Metrics generated successfully:")
    print(f"Overall Status: {metrics['overall']['overall_status'].upper()}")
    print(f"Success Rate: {metrics['overall']['success_rate']*100:.1f}%")
    print(f"Quality Score: {metrics['quality_score']['overall']}/100 ({metrics['quality_score']['grade']})")
    
    if metrics['alerts']:
        print(f"Alerts: {len(metrics['alerts'])}")
        for alert in metrics['alerts']:
            print(f"  - {alert['severity'].upper()}: {alert['message']}")

if __name__ == "__main__":
    main()