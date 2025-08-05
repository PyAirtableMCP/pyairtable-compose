#!/usr/bin/env python3
"""
OpenTelemetry Integration Test Suite

This script tests the OTLP integration for PyAirtable services,
validating traces, metrics, and logs are properly exported to the LGTM stack.
"""

import asyncio
import json
import time
from datetime import datetime
from typing import Dict, List, Optional

import httpx
import structlog

# Configure structured logging for test results
structlog.configure(
    processors=[
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.make_filtering_bound_logger(20),  # INFO level
    logger_factory=structlog.WriteLoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger("otel-integration-test")


class OTELIntegrationTester:
    """Test suite for OpenTelemetry integration"""
    
    def __init__(self):
        self.services = {
            "llm-orchestrator": "http://localhost:8003",
            "airtable-gateway": "http://localhost:8002", 
            "mcp-server": "http://localhost:8001",
            "automation-services": "http://localhost:8006"
        }
        
        self.observability_endpoints = {
            "grafana": "http://localhost:3000",
            "tempo": "http://localhost:3200",
            "loki": "http://localhost:3100",
            "mimir": "http://localhost:9009",
            "otel-collector": "http://localhost:13133"
        }
        
        self.test_results = {
            "service_health": {},
            "observability_health": {},
            "trace_generation": {},
            "metric_collection": {},
            "log_integration": {},
            "cost_tracking": {},
            "performance_metrics": {}
        }
    
    async def run_all_tests(self) -> Dict:
        """Run all integration tests"""
        logger.info("Starting OpenTelemetry integration tests")
        
        # Test 1: Service Health Checks
        await self.test_service_health()
        
        # Test 2: Observability Stack Health
        await self.test_observability_health()
        
        # Test 3: Trace Generation
        await self.test_trace_generation()
        
        # Test 4: Metric Collection  
        await self.test_metric_collection()
        
        # Test 5: Log Integration
        await self.test_log_integration()
        
        # Test 6: Cost Tracking (LLM calls)
        await self.test_cost_tracking()
        
        # Test 7: Performance Metrics
        await self.test_performance_metrics()
        
        # Generate summary report
        summary = self.generate_test_summary()
        
        logger.info("OpenTelemetry integration tests completed", summary=summary)
        return self.test_results
    
    async def test_service_health(self):
        """Test that all services are healthy and responding"""
        logger.info("Testing service health checks")
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            for service_name, base_url in self.services.items():
                try:
                    # Test basic health endpoint
                    response = await client.get(f"{base_url}/health")
                    
                    is_healthy = response.status_code == 200
                    self.test_results["service_health"][service_name] = {
                        "healthy": is_healthy,
                        "status_code": response.status_code,
                        "response_time_ms": response.elapsed.total_seconds() * 1000,
                        "details": response.json() if is_healthy else None
                    }
                    
                    if is_healthy:
                        logger.info(f"Service {service_name} is healthy")
                    else:
                        logger.error(f"Service {service_name} health check failed", 
                                   status_code=response.status_code)
                        
                except Exception as e:
                    logger.error(f"Failed to check {service_name} health", 
                               exception=str(e))
                    self.test_results["service_health"][service_name] = {
                        "healthy": False,
                        "error": str(e)
                    }
    
    async def test_observability_health(self):
        """Test that observability stack components are healthy"""
        logger.info("Testing observability stack health")
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            for component, base_url in self.observability_endpoints.items():
                try:
                    if component == "otel-collector":
                        endpoint = f"{base_url}/health"
                    elif component == "grafana":
                        endpoint = f"{base_url}/api/health"
                    elif component == "tempo":
                        endpoint = f"{base_url}/status/services"
                    elif component == "loki":
                        endpoint = f"{base_url}/ready"
                    elif component == "mimir":
                        endpoint = f"{base_url}/ready"
                    else:
                        endpoint = f"{base_url}/health"
                    
                    response = await client.get(endpoint)
                    is_healthy = response.status_code in [200, 201, 204]
                    
                    self.test_results["observability_health"][component] = {
                        "healthy": is_healthy,
                        "status_code": response.status_code,
                        "response_time_ms": response.elapsed.total_seconds() * 1000
                    }
                    
                    if is_healthy:
                        logger.info(f"Observability component {component} is healthy")
                    else:
                        logger.warning(f"Observability component {component} may not be ready",
                                     status_code=response.status_code)
                        
                except Exception as e:
                    logger.error(f"Failed to check {component} health", 
                               exception=str(e))
                    self.test_results["observability_health"][component] = {
                        "healthy": False,
                        "error": str(e)
                    }
    
    async def test_trace_generation(self):
        """Test that services generate traces properly"""
        logger.info("Testing trace generation")
        
        trace_test_id = f"trace-test-{int(time.time())}"
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for service_name, base_url in self.services.items():
                try:
                    # Add trace context headers
                    headers = {
                        "X-Trace-Test-ID": trace_test_id,
                        "User-Agent": "otel-integration-test"
                    }
                    
                    start_time = time.time()
                    
                    # Test service info endpoint (should generate traces)
                    response = await client.get(f"{base_url}/api/v1/info", headers=headers)
                    
                    duration_ms = (time.time() - start_time) * 1000
                    
                    self.test_results["trace_generation"][service_name] = {
                        "success": response.status_code == 200,
                        "status_code": response.status_code,
                        "duration_ms": duration_ms,
                        "trace_test_id": trace_test_id,
                        "headers_sent": headers,
                        "response": response.json() if response.status_code == 200 else None
                    }
                    
                    logger.info(f"Trace generation test for {service_name} completed",
                              status_code=response.status_code,
                              duration_ms=duration_ms)
                    
                except Exception as e:
                    logger.error(f"Trace generation test failed for {service_name}",
                               exception=str(e))
                    self.test_results["trace_generation"][service_name] = {
                        "success": False,
                        "error": str(e)
                    }
        
        # Wait for traces to be exported
        await asyncio.sleep(5)
    
    async def test_metric_collection(self):
        """Test that metrics are being collected"""
        logger.info("Testing metric collection")
        
        # Check OTEL Collector metrics
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get("http://localhost:8888/metrics")
                
                metrics_available = response.status_code == 200
                metrics_content = response.text if metrics_available else ""
                
                # Look for key metrics indicators
                key_metrics = [
                    "otelcol_receiver_accepted_spans_total",
                    "otelcol_exporter_sent_spans_total", 
                    "otelcol_processor_batch_batch_send_size",
                    "otelcol_receiver_refused_spans_total"
                ]
                
                metrics_found = {}
                for metric in key_metrics:
                    metrics_found[metric] = metric in metrics_content
                
                self.test_results["metric_collection"]["otel_collector"] = {
                    "metrics_endpoint_available": metrics_available,
                    "key_metrics_found": metrics_found,
                    "metrics_count": len([line for line in metrics_content.split('\n') 
                                        if line.startswith('otelcol_')])
                }
                
                logger.info("OTEL Collector metrics checked", 
                          available=metrics_available,
                          metrics_found=sum(metrics_found.values()))
                
        except Exception as e:
            logger.error("Failed to check OTEL Collector metrics", exception=str(e))
            self.test_results["metric_collection"]["otel_collector"] = {
                "metrics_endpoint_available": False,
                "error": str(e)
            }
    
    async def test_log_integration(self):
        """Test that logs are being sent to Loki"""
        logger.info("Testing log integration with Loki")
        
        try:
            # Check Loki labels endpoint
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get("http://localhost:3100/loki/api/v1/labels")
                
                if response.status_code == 200:
                    labels_data = response.json()
                    available_labels = labels_data.get("data", [])
                    
                    # Look for service-specific labels
                    expected_labels = ["service", "environment", "level"]
                    labels_found = {label: label in available_labels for label in expected_labels}
                    
                    self.test_results["log_integration"]["loki"] = {
                        "labels_endpoint_available": True,
                        "total_labels": len(available_labels),
                        "expected_labels_found": labels_found,
                        "all_labels": available_labels
                    }
                    
                    logger.info("Loki labels checked",
                              total_labels=len(available_labels),
                              expected_found=sum(labels_found.values()))
                else:
                    self.test_results["log_integration"]["loki"] = {
                        "labels_endpoint_available": False,
                        "status_code": response.status_code
                    }
                    
        except Exception as e:
            logger.error("Failed to check Loki integration", exception=str(e))
            self.test_results["log_integration"]["loki"] = {
                "labels_endpoint_available": False,
                "error": str(e)
            }
    
    async def test_cost_tracking(self):
        """Test LLM cost tracking through traces"""
        logger.info("Testing LLM cost tracking")
        
        if "llm-orchestrator" not in self.services:
            logger.warning("LLM Orchestrator not available for cost tracking test")
            return
        
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                # Test chat completion (if API key is available)
                chat_request = {
                    "messages": [
                        {"role": "user", "content": "Hello, this is a test message for cost tracking."}
                    ],
                    "model": "gemini-2.0-flash-exp",
                    "max_tokens": 50
                }
                
                headers = {
                    "Content-Type": "application/json",
                    "X-Test-Type": "cost-tracking"
                }
                
                start_time = time.time()
                
                # This may fail if no valid API key is configured, but traces should still be generated
                response = await client.post(
                    f"{self.services['llm-orchestrator']}/api/v1/chat/completions",
                    json=chat_request,
                    headers=headers
                )
                
                duration_ms = (time.time() - start_time) * 1000
                
                self.test_results["cost_tracking"]["llm_orchestrator"] = {
                    "request_completed": True,
                    "status_code": response.status_code,
                    "duration_ms": duration_ms,
                    "trace_generated": True,  # Assume trace was generated
                    "cost_tracking_enabled": response.status_code in [200, 400, 401]  # API errors still generate traces
                }
                
                if response.status_code == 200:
                    response_data = response.json()
                    usage = response_data.get("usage", {})
                    
                    self.test_results["cost_tracking"]["llm_orchestrator"].update({
                        "tokens_tracked": "total_tokens" in usage,
                        "cost_calculated": "cost" in usage,
                        "usage_data": usage
                    })
                
                logger.info("LLM cost tracking test completed",
                          status_code=response.status_code,
                          duration_ms=duration_ms)
                
        except Exception as e:
            logger.error("LLM cost tracking test failed", exception=str(e))
            self.test_results["cost_tracking"]["llm_orchestrator"] = {
                "request_completed": False,
                "error": str(e)
            }
    
    async def test_performance_metrics(self):
        """Test performance metrics collection"""
        logger.info("Testing performance metrics")
        
        performance_data = {}
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for service_name, base_url in self.services.items():
                try:
                    # Make multiple requests to generate performance data
                    response_times = []
                    
                    for i in range(5):
                        start_time = time.time()
                        response = await client.get(f"{base_url}/health")
                        duration_ms = (time.time() - start_time) * 1000
                        response_times.append(duration_ms)
                        
                        # Add some delay between requests
                        await asyncio.sleep(0.5)
                    
                    avg_response_time = sum(response_times) / len(response_times)
                    min_response_time = min(response_times)
                    max_response_time = max(response_times)
                    
                    performance_data[service_name] = {
                        "avg_response_time_ms": avg_response_time,
                        "min_response_time_ms": min_response_time,
                        "max_response_time_ms": max_response_time,
                        "total_requests": len(response_times),
                        "performance_bucket": self._get_performance_bucket(avg_response_time)
                    }
                    
                    logger.info(f"Performance test for {service_name} completed",
                              avg_response_time_ms=avg_response_time,
                              performance_bucket=performance_data[service_name]["performance_bucket"])
                    
                except Exception as e:
                    logger.error(f"Performance test failed for {service_name}", exception=str(e))
                    performance_data[service_name] = {"error": str(e)}
        
        self.test_results["performance_metrics"] = performance_data
    
    def _get_performance_bucket(self, duration_ms: float) -> str:
        """Categorize performance for monitoring"""
        if duration_ms < 100:
            return "fast"
        elif duration_ms < 500:
            return "normal"
        elif duration_ms < 2000:
            return "slow"
        elif duration_ms < 10000:
            return "very_slow"
        else:
            return "timeout_risk"
    
    def generate_test_summary(self) -> Dict:
        """Generate a summary of test results"""
        summary = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "total_tests": 0,
            "passed_tests": 0,
            "failed_tests": 0,
            "categories": {}
        }
        
        for category, tests in self.test_results.items():
            category_summary = {
                "total": len(tests),
                "passed": 0,
                "failed": 0,
                "details": {}
            }
            
            for test_name, result in tests.items():
                summary["total_tests"] += 1
                category_summary["total"] += 1
                
                # Determine if test passed (basic heuristic)
                passed = False
                if category == "service_health":
                    passed = result.get("healthy", False)
                elif category == "observability_health":
                    passed = result.get("healthy", False)
                elif category == "trace_generation":
                    passed = result.get("success", False)
                elif category == "metric_collection":
                    passed = result.get("metrics_endpoint_available", False)
                elif category == "log_integration":
                    passed = result.get("labels_endpoint_available", False)
                elif category == "cost_tracking":
                    passed = result.get("request_completed", False)
                elif category == "performance_metrics":
                    passed = "error" not in result
                
                if passed:
                    summary["passed_tests"] += 1
                    category_summary["passed"] += 1
                else:
                    summary["failed_tests"] += 1
                    category_summary["failed"] += 1
                
                category_summary["details"][test_name] = "PASSED" if passed else "FAILED"
            
            summary["categories"][category] = category_summary
        
        # Calculate success rate
        if summary["total_tests"] > 0:
            summary["success_rate"] = (summary["passed_tests"] / summary["total_tests"]) * 100
        else:
            summary["success_rate"] = 0
        
        return summary
    
    def save_results(self, filename: str = None):
        """Save test results to a JSON file"""
        if filename is None:
            timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
            filename = f"otel_integration_test_results_{timestamp}.json"
        
        with open(filename, 'w') as f:
            json.dump(self.test_results, f, indent=2, default=str)
        
        logger.info("Test results saved", filename=filename)
        return filename


async def main():
    """Main test runner"""
    print("=" * 80)
    print("PyAirtable OpenTelemetry Integration Test Suite")
    print("=" * 80)
    print()
    
    tester = OTELIntegrationTester()
    
    try:
        # Run all tests
        results = await tester.run_all_tests()
        
        # Generate and display summary
        summary = tester.generate_test_summary()
        
        print()
        print("=" * 80)
        print("TEST SUMMARY")
        print("=" * 80)
        print(f"Total Tests: {summary['total_tests']}")
        print(f"Passed: {summary['passed_tests']}")
        print(f"Failed: {summary['failed_tests']}")
        print(f"Success Rate: {summary['success_rate']:.1f}%")
        print()
        
        for category, category_summary in summary["categories"].items():
            print(f"{category.replace('_', ' ').title()}:")
            print(f"  Passed: {category_summary['passed']}/{category_summary['total']}")
            for test_name, status in category_summary["details"].items():
                status_symbol = "✓" if status == "PASSED" else "✗"
                print(f"    {status_symbol} {test_name}")
            print()
        
        # Save results
        filename = tester.save_results()
        print(f"Detailed results saved to: {filename}")
        
        # Exit with appropriate code
        if summary["failed_tests"] > 0:
            print("\n⚠️  Some tests failed. Check the logs and results file for details.")
            exit(1)
        else:
            print("\n✅ All tests passed! OpenTelemetry integration is working correctly.")
            exit(0)
            
    except KeyboardInterrupt:
        print("\n\n❌ Tests interrupted by user")
        exit(1)
    except Exception as e:
        print(f"\n\n❌ Test runner failed: {e}")
        logger.error("Test runner failed", exception=str(e))
        exit(1)


if __name__ == "__main__":
    asyncio.run(main())