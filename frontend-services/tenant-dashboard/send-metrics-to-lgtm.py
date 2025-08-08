#!/usr/bin/env python3
"""
Send Playwright test metrics to LGTM monitoring stack
Pushes test results to Prometheus, logs to Loki, and creates Grafana annotations
"""

import json
import time
import requests
import sys
from datetime import datetime
from pathlib import Path

class LGTMMetricsSender:
    def __init__(self):
        self.prometheus_url = "http://localhost:9090"
        self.loki_url = "http://localhost:3100"
        self.grafana_url = "http://localhost:3003"
        self.timestamp = int(time.time() * 1000)
        
    def read_test_results(self):
        """Read Playwright test results from JSON files"""
        results_file = Path("test-results-simple/results.json")
        visual_results_file = Path("test-results-visual/results.json")
        
        results = {}
        
        if results_file.exists():
            with open(results_file, 'r') as f:
                results['core'] = json.load(f)
                
        if visual_results_file.exists():
            with open(visual_results_file, 'r') as f:
                results['visual'] = json.load(f)
        
        return results
    
    def extract_metrics(self, results):
        """Extract key metrics from test results"""
        metrics = {
            'core_tests': {
                'total': 0,
                'passed': 0,
                'failed': 0,
                'success_rate': 0,
                'avg_duration': 0,
                'total_duration': 0
            },
            'visual_tests': {
                'total': 0,
                'passed': 0,
                'failed': 0,
                'success_rate': 0,
                'avg_duration': 0,
                'total_duration': 0
            },
            'mobile_tests': {
                'total': 0,
                'passed': 0,
                'failed': 0,
                'success_rate': 0
            },
            'airtable_integration': {
                'total': 0,
                'passed': 0,
                'failed': 0,
                'success_rate': 0
            }
        }
        
        for test_type, data in results.items():
            if 'suites' in data:
                for suite in data['suites']:
                    for test in self._extract_tests_from_suite(suite):
                        test_name = test.get('title', '').lower()
                        status = test.get('status', 'unknown')
                        duration = test.get('duration', 0)
                        
                        # Categorize tests
                        if 'airtable' in test_name or 'integration' in test_name:
                            category = 'airtable_integration'
                        elif 'mobile' in test_name or test_type == 'visual':
                            category = 'mobile_tests'
                        elif test_type == 'visual':
                            category = 'visual_tests'
                        else:
                            category = 'core_tests'
                        
                        metrics[category]['total'] += 1
                        metrics[category]['total_duration'] += duration
                        
                        if status == 'passed':
                            metrics[category]['passed'] += 1
                        else:
                            metrics[category]['failed'] += 1
        
        # Calculate success rates and averages
        for category in metrics:
            total = metrics[category]['total']
            if total > 0:
                metrics[category]['success_rate'] = (metrics[category]['passed'] / total) * 100
                metrics[category]['avg_duration'] = metrics[category]['total_duration'] / total
            else:
                metrics[category]['success_rate'] = 0
                metrics[category]['avg_duration'] = 0
        
        return metrics
    
    def _extract_tests_from_suite(self, suite):
        """Recursively extract all tests from a suite"""
        tests = []
        if 'tests' in suite:
            tests.extend(suite['tests'])
        if 'suites' in suite:
            for subsuite in suite['suites']:
                tests.extend(self._extract_tests_from_suite(subsuite))
        return tests
    
    def send_to_prometheus(self, metrics):
        """Send metrics to Prometheus via pushgateway or direct metrics endpoint"""
        prometheus_metrics = []
        
        for category, data in metrics.items():
            prometheus_metrics.extend([
                f'playwright_tests_total{{category="{category}"}} {data["total"]}',
                f'playwright_tests_passed{{category="{category}"}} {data["passed"]}',
                f'playwright_tests_failed{{category="{category}"}} {data["failed"]}',
                f'playwright_success_rate{{category="{category}"}} {data["success_rate"]}',
                f'playwright_avg_duration_ms{{category="{category}"}} {data["avg_duration"]}'
            ])
        
        # Add timestamp metrics
        prometheus_metrics.append(f'playwright_test_execution_timestamp {self.timestamp}')
        
        try:
            # Try to push to Prometheus pushgateway (if available)
            pushgateway_url = f"{self.prometheus_url.replace('9090', '9091')}/metrics/job/playwright_tests"
            
            payload = "\\n".join(prometheus_metrics)
            response = requests.post(pushgateway_url, data=payload, timeout=5)
            
            if response.status_code == 200:
                print(f"✅ Metrics sent to Prometheus pushgateway")
                return True
        except requests.exceptions.RequestException:
            pass
        
        # Fallback: Print metrics for manual collection
        print("📊 Prometheus Metrics (manual collection needed):")
        for metric in prometheus_metrics:
            print(f"  {metric}")
        
        return False
    
    def send_to_loki(self, metrics, results):
        """Send structured logs to Loki"""
        log_entries = []
        
        # Create log entries for each test category
        for category, data in metrics.items():
            log_entry = {
                "timestamp": f"{self.timestamp}000000",  # Loki expects nanoseconds
                "line": json.dumps({
                    "level": "info",
                    "service": "playwright_tests",
                    "category": category,
                    "total_tests": data["total"],
                    "passed": data["passed"],
                    "failed": data["failed"],
                    "success_rate": data["success_rate"],
                    "avg_duration_ms": data["avg_duration"],
                    "timestamp": datetime.now().isoformat()
                })
            }
            log_entries.append(log_entry)
        
        # Add failure details
        for test_type, data in results.items():
            if 'suites' in data:
                for suite in data['suites']:
                    for test in self._extract_tests_from_suite(suite):
                        if test.get('status') != 'passed':
                            error_entry = {
                                "timestamp": f"{self.timestamp}000000",
                                "line": json.dumps({
                                    "level": "error",
                                    "service": "playwright_tests",
                                    "test_name": test.get('title', 'Unknown'),
                                    "status": test.get('status', 'unknown'),
                                    "duration": test.get('duration', 0),
                                    "error": test.get('error', {}).get('message', 'No error message'),
                                    "timestamp": datetime.now().isoformat()
                                })
                            }
                            log_entries.append(error_entry)
        
        # Send to Loki
        loki_payload = {
            "streams": [
                {
                    "stream": {"job": "playwright_tests", "service": "frontend_testing"},
                    "values": [[entry["timestamp"], entry["line"]] for entry in log_entries]
                }
            ]
        }
        
        try:
            response = requests.post(
                f"{self.loki_url}/loki/api/v1/push",
                json=loki_payload,
                headers={"Content-Type": "application/json"},
                timeout=5
            )
            
            if response.status_code == 204:
                print(f"✅ Logs sent to Loki ({len(log_entries)} entries)")
                return True
        except requests.exceptions.RequestException as e:
            pass
        
        print("📝 Loki Logs (manual collection needed):")
        for entry in log_entries[:3]:  # Show first 3 entries
            print(f"  {json.loads(entry['line'])}")
        print(f"  ... and {len(log_entries) - 3} more entries")
        
        return False
    
    def create_grafana_annotation(self, metrics):
        """Create Grafana annotation for test run"""
        total_tests = sum(data['total'] for data in metrics.values())
        total_passed = sum(data['passed'] for data in metrics.values())
        overall_success_rate = (total_passed / total_tests) * 100 if total_tests > 0 else 0
        
        annotation = {
            "time": self.timestamp,
            "timeEnd": self.timestamp + 60000,  # 1 minute duration
            "tags": ["playwright", "frontend-testing", "automation"],
            "text": f"Playwright Test Run Completed\\n"
                   f"Total Tests: {total_tests}\\n"
                   f"Passed: {total_passed}\\n"
                   f"Success Rate: {overall_success_rate:.1f}%\\n"
                   f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        }
        
        try:
            # Try to create annotation via Grafana API
            response = requests.post(
                f"{self.grafana_url}/api/annotations",
                json=annotation,
                headers={"Authorization": "Bearer admin", "Content-Type": "application/json"},
                timeout=5
            )
            
            if response.status_code in [200, 201]:
                print(f"✅ Grafana annotation created")
                return True
        except requests.exceptions.RequestException:
            pass
        
        print("📈 Grafana Annotation (manual creation needed):")
        print(f"  {annotation}")
        
        return False
    
    def run(self):
        """Main execution function"""
        print("🚀 Starting LGTM metrics collection for Playwright tests...")
        
        # Read test results
        results = self.read_test_results()
        if not results:
            print("❌ No test results found")
            return False
        
        # Extract metrics
        metrics = self.extract_metrics(results)
        
        # Print summary
        total_tests = sum(data['total'] for data in metrics.values())
        total_passed = sum(data['passed'] for data in metrics.values())
        overall_success_rate = (total_passed / total_tests) * 100 if total_tests > 0 else 0
        
        print(f"\\n📊 Test Results Summary:")
        print(f"  Total Tests: {total_tests}")
        print(f"  Passed: {total_passed}")
        print(f"  Failed: {total_tests - total_passed}")
        print(f"  Overall Success Rate: {overall_success_rate:.1f}%")
        
        print(f"\\n📈 Category Breakdown:")
        for category, data in metrics.items():
            if data['total'] > 0:
                print(f"  {category}: {data['passed']}/{data['total']} ({data['success_rate']:.1f}%)")
        
        # Send to monitoring systems
        print(f"\\n📤 Sending to LGTM stack...")
        
        prometheus_success = self.send_to_prometheus(metrics)
        loki_success = self.send_to_loki(metrics, results)
        grafana_success = self.create_grafana_annotation(metrics)
        
        print(f"\\n✅ LGTM Integration Summary:")
        print(f"  Prometheus: {'✅ Success' if prometheus_success else '❌ Failed (metrics printed)'}")
        print(f"  Loki: {'✅ Success' if loki_success else '❌ Failed (logs printed)'}")
        print(f"  Grafana: {'✅ Success' if grafana_success else '❌ Failed (annotation printed)'}")
        
        return True

if __name__ == "__main__":
    sender = LGTMMetricsSender()
    success = sender.run()
    sys.exit(0 if success else 1)