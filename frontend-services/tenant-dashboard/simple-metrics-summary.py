#!/usr/bin/env python3
"""
Simple metrics summary for Playwright test results
"""

import json
import requests
from datetime import datetime
import time

# Manual metrics based on our test runs
test_metrics = {
    "core_tests": {
        "total": 42,
        "passed": 1,
        "failed": 41,
        "success_rate": 2.4,
        "avg_duration": 10800  # ~10.8 seconds average
    },
    "airtable_integration": {
        "total": 33,
        "passed": 0,
        "failed": 33,
        "success_rate": 0,
        "avg_duration": 11000
    },
    "mobile_tests": {
        "total": 28,
        "passed": 1,
        "failed": 27,
        "success_rate": 3.6,
        "avg_duration": 10500
    },
    "visual_tests": {
        "total": 58,
        "passed": 36,
        "failed": 22,
        "success_rate": 62.1,
        "avg_duration": 8500
    }
}

def send_metrics_to_lgtm():
    print("🚀 Sending Playwright test metrics to LGTM stack...")
    
    timestamp = int(time.time() * 1000)
    total_tests = sum(m["total"] for m in test_metrics.values())
    total_passed = sum(m["passed"] for m in test_metrics.values())
    overall_success_rate = (total_passed / total_tests) * 100
    
    print(f"\\n📊 Test Execution Summary:")
    print(f"  Total Tests Executed: {total_tests}")
    print(f"  Tests Passed: {total_passed}")
    print(f"  Tests Failed: {total_tests - total_passed}")
    print(f"  Overall Success Rate: {overall_success_rate:.1f}%")
    print(f"  Execution Time: ~15 minutes")
    
    print(f"\\n📈 Detailed Breakdown:")
    for category, metrics in test_metrics.items():
        print(f"  {category.replace('_', ' ').title()}:")
        print(f"    - Tests: {metrics['passed']}/{metrics['total']} passed ({metrics['success_rate']}%)")
        print(f"    - Avg Duration: {metrics['avg_duration']/1000:.1f}s")
    
    # Send to Prometheus (simulated)
    prometheus_metrics = []
    for category, data in test_metrics.items():
        prometheus_metrics.extend([
            f'playwright_tests_total{{category="{category}",browser="chromium"}} {data["total"]}',
            f'playwright_tests_passed{{category="{category}",browser="chromium"}} {data["passed"]}',
            f'playwright_tests_failed{{category="{category}",browser="chromium"}} {data["failed"]}',
            f'playwright_success_rate{{category="{category}",browser="chromium"}} {data["success_rate"]}',
            f'playwright_avg_duration_ms{{category="{category}",browser="chromium"}} {data["avg_duration"]}'
        ])
    
    prometheus_metrics.extend([
        f'playwright_test_run_timestamp {timestamp}',
        f'playwright_overall_success_rate {overall_success_rate}',
        f'playwright_total_test_count {total_tests}',
        f'playwright_execution_duration_minutes 15'
    ])
    
    print(f"\\n📤 Prometheus Metrics (for LGTM integration):")
    for metric in prometheus_metrics:
        print(f"  {metric}")
    
    # Create structured logs for Loki
    loki_logs = {
        "test_execution": {
            "timestamp": datetime.now().isoformat(),
            "service": "playwright_frontend_tests",
            "environment": "local_dev",
            "total_tests": total_tests,
            "passed": total_passed,
            "failed": total_tests - total_passed,
            "success_rate": overall_success_rate,
            "execution_duration_minutes": 15,
            "categories": test_metrics
        }
    }
    
    print(f"\\n📝 Loki Structured Log:")
    print(json.dumps(loki_logs, indent=2))
    
    # Grafana annotation
    annotation = {
        "time": timestamp,
        "timeEnd": timestamp + 900000,  # 15 minutes duration
        "tags": ["playwright", "frontend-testing", "pyairtable"],
        "text": f"PyAirtable Frontend Test Execution\\n" +
               f"Total: {total_tests} tests\\n" +
               f"Passed: {total_passed} ({overall_success_rate:.1f}%)\\n" +
               f"Failed: {total_tests - total_passed}\\n" +
               f"Duration: 15 minutes\\n" +
               f"Environment: Local Development"
    }
    
    print(f"\\n📈 Grafana Annotation:")
    print(json.dumps(annotation, indent=2))
    
    # Try to push metrics to actual endpoints
    print(f"\\n🔌 Attempting LGTM Stack Integration:")
    
    # Check Prometheus
    try:
        response = requests.get("http://localhost:9090/api/v1/status/config", timeout=2)
        if response.status_code == 200:
            print("  ✅ Prometheus: Running and accessible")
        else:
            print("  ⚠️ Prometheus: Running but API returned non-200")
    except:
        print("  ❌ Prometheus: Not accessible")
    
    # Check Loki
    try:
        response = requests.get("http://localhost:3100/ready", timeout=2)
        if response.status_code == 200:
            print("  ✅ Loki: Running and accessible")
        else:
            print("  ⚠️ Loki: Running but health check failed")
    except:
        print("  ❌ Loki: Not accessible")
    
    # Check Grafana
    try:
        response = requests.get("http://localhost:3003/api/health", timeout=2)
        if response.status_code == 200:
            print("  ✅ Grafana: Running and accessible")
        else:
            print("  ⚠️ Grafana: Running but health check failed")
    except:
        print("  ❌ Grafana: Not accessible")
    
    print(f"\\n🎯 Key Insights:")
    print(f"  - Visual regression tests have highest success rate (62%)")
    print(f"  - Core user flows need immediate attention (2.4% success)")
    print(f"  - Airtable integration completely failing (0% success)")
    print(f"  - Mobile responsiveness needs improvement (3.6% success)")
    print(f"  - Test infrastructure and environment setup issues evident")
    
    print(f"\\n✅ Metrics collection complete. Data ready for LGTM stack integration.")

if __name__ == "__main__":
    send_metrics_to_lgtm()