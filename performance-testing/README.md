# PyAirtable Performance Testing Framework

A comprehensive, enterprise-grade performance testing framework for the PyAirtable platform, featuring multiple testing tools, real-time monitoring, and automated orchestration.

## 🚀 Overview

This performance testing framework provides comprehensive testing capabilities for all 8 core PyAirtable services:

- **API Gateway** - Main entry point and routing
- **LLM Orchestrator** - AI/ML processing and chat
- **MCP Server** - Protocol implementation
- **Airtable Gateway** - External API integration
- **Platform Services** - Core business logic
- **Automation Services** - Workflow processing
- **Saga Orchestrator** - Transaction coordination
- **Redis** - Caching and session storage

## 🏗️ Architecture

```
performance-testing/
├── k6/                          # K6 load testing scripts
├── jmeter/                      # JMeter test plans
├── locust/                      # Locust user scenarios
├── artillery/                   # Artillery quick tests
├── stress-tests/                # Extreme load scenarios
├── soak-tests/                  # Long-running stability tests
├── test-data/                   # Test datasets and users
├── configs/                     # Configuration files and SLOs
├── orchestrator/                # Test coordination and automation
├── scripts/                     # Automation and utility scripts
├── reports/                     # Test results and artifacts
├── grafana/                     # Monitoring dashboards
└── benchmarks/                  # Performance benchmarks
```

## 🎯 Features

### Multi-Tool Testing
- **K6** - Modern load testing with JavaScript
- **JMeter** - Enterprise-grade performance testing
- **Locust** - Python-based user behavior simulation
- **Artillery** - Quick performance validation

### Test Types
- **Smoke Tests** - Basic functionality validation (2-5 minutes)
- **Load Tests** - Normal expected load testing (10-20 minutes)
- **Stress Tests** - Breaking point identification (15-30 minutes)
- **Soak Tests** - Long-running stability testing (2-4 hours)
- **Database Tests** - Connection pool and query performance (15-30 minutes)

### Real-Time Monitoring
- **LGTM Stack** - Loki, Grafana, Tempo, Mimir integration
- **Custom Dashboards** - Service-specific performance visualization
- **Alert Management** - Automated threshold-based alerting
- **Distributed Tracing** - End-to-end request tracking

### Performance SLOs
- **Response Time Targets** - Service-specific latency requirements
- **Error Rate Thresholds** - Acceptable failure rates per service
- **Throughput Goals** - Requests per second targets
- **Resource Limits** - CPU, memory, and connection constraints

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose
- PyAirtable platform running
- At least 8GB RAM and 4 CPU cores for comprehensive testing

### 1. Basic Smoke Test
```bash
cd /Users/kg/IdeaProjects/pyairtable-compose/performance-testing
./scripts/run-performance-suite.sh --suite smoke --environment development
```

### 2. Full Load Test Suite
```bash
./scripts/run-performance-suite.sh --suite load --environment staging --parallel
```

### 3. Comprehensive Testing
```bash
./scripts/run-performance-suite.sh --suite all --environment staging --monitoring
```

### 4. Database Performance Testing
```bash
./scripts/run-performance-suite.sh --suite database --environment development
```

## 📊 Performance SLOs

### Service Level Objectives

| Service | P95 Response Time | P99 Response Time | Error Rate | Throughput (RPS) |
|---------|------------------|-------------------|------------|------------------|
| API Gateway | 500ms | 1000ms | <0.1% | 1000 |
| LLM Orchestrator | 2000ms | 5000ms | <1% | 100 |
| MCP Server | 200ms | 500ms | <0.05% | 2000 |
| Airtable Gateway | 1000ms | 2000ms | <0.5% | 500 |
| Platform Services | 500ms | 1000ms | <0.1% | 1500 |
| Automation Services | 1000ms | 3000ms | <1% | 200 |
| Saga Orchestrator | 500ms | 2000ms | <0.5% | 300 |
| Redis | 5ms | 10ms | <0.01% | 10000 |

### Database Performance Targets

| Query Type | Target Response Time | Connection Pool | Throughput |
|------------|---------------------|-----------------|------------|
| Simple Queries | <50ms | 100 connections | 5000/sec |
| Complex Queries | <500ms | Max lifetime: 1h | 1000/sec |
| Aggregations | <2000ms | Idle timeout: 5m | 500/sec |
| Full-text Search | <500ms | - | 200/sec |

## 🔧 Configuration

### Environment Configuration
```yaml
# configs/performance-slos.yml
environments:
  development:
    base_url: 'http://api-gateway:8000'
    max_users_scale: 0.5
    duration_scale: 0.5
  staging:
    base_url: 'http://staging-api-gateway:8000'
    max_users_scale: 0.8
    duration_scale: 0.8
  production:
    base_url: 'https://api.pyairtable.com'
    max_users_scale: 1.0
    duration_scale: 1.0
```

### Test Suite Configuration
```bash
# Environment variables
export ENVIRONMENT=staging
export TEST_SUITE=load
export PARALLEL=true
export MONITORING=true
export BASE_URL=http://api-gateway:8000
```

## 📈 Monitoring and Dashboards

### Grafana Dashboards
- **Performance Overview** - http://localhost:3000/d/performance-overview
- **Service Metrics** - http://localhost:3000/d/service-metrics
- **Database Performance** - http://localhost:3000/d/database-performance
- **Real-time Monitoring** - http://localhost:3000/d/realtime-monitoring

### Key Metrics
- Response time percentiles (P50, P95, P99)
- Error rates and types
- Throughput (requests per second)
- Resource utilization (CPU, memory, network)
- Database connection pool statistics
- Cache hit rates
- Concurrent user load

## 🧪 Test Scenarios

### K6 Load Testing
```javascript
// Example: API endpoint testing
export const options = {
  scenarios: {
    api_load_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '5m', target: 50 },
        { duration: '10m', target: 50 },
        { duration: '5m', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    http_req_failed: ['rate<0.01'],
  },
};
```

### Locust User Scenarios
```python
# Example: User journey simulation
class RegularUser(HttpUser):
    weight = 70  # 70% of users
    wait_time = between(1, 5)
    
    @task(30)
    def browse_workspaces(self):
        self.client.get("/api/workspaces")
    
    @task(25)
    def work_with_records(self):
        self.client.post("/api/records", json={...})
```

## 📋 Test Reports

### Automated Reports
- **HTML Reports** - Visual performance summaries
- **JSON Results** - Detailed metrics and timings
- **CSV Exports** - Raw data for analysis
- **Dashboard Screenshots** - Monitoring snapshots

### Report Locations
- **Local Reports** - `./reports/`
- **Grafana Dashboards** - http://localhost:3000
- **Prometheus Metrics** - http://localhost:9090
- **Log Aggregation** - http://localhost:3100

## 🔍 Troubleshooting

### Common Issues

1. **Services Not Starting**
   ```bash
   # Check Docker network
   docker network ls | grep pyairtable
   
   # Start PyAirtable services
   cd .. && docker-compose up -d
   ```

2. **Monitoring Stack Issues**
   ```bash
   # Restart monitoring
   docker-compose -f configs/lgtm-integration.yml restart
   
   # Check logs
   docker-compose -f configs/lgtm-integration.yml logs grafana
   ```

3. **Test Failures**
   ```bash
   # Check test logs
   tail -f reports/performance-suite-*.log
   
   # Verify service health
   curl http://localhost:8000/api/health
   ```

### Performance Debugging
- Use Grafana dashboards to identify bottlenecks
- Check Prometheus metrics for resource usage
- Review Loki logs for error patterns
- Analyze Tempo traces for slow requests

## 🚀 Advanced Usage

### Custom Test Scenarios
```bash
# Run specific K6 test
docker run --rm --network pyairtable-network \
  -v $(pwd):/scripts:ro \
  -v $(pwd)/reports:/reports:rw \
  -e BASE_URL=http://api-gateway:8000 \
  grafana/k6:latest run /scripts/k6/custom-test.js
```

### Orchestrated Testing
```python
# Use Python orchestrator
python orchestrator/orchestrator.py load_tests staging
```

### CI/CD Integration
```yaml
# GitHub Actions example
- name: Run Performance Tests
  run: |
    ./scripts/run-performance-suite.sh \
      --suite smoke \
      --environment staging \
      --no-monitoring
```

## 📚 Best Practices

### Test Design
1. **Start Small** - Begin with smoke tests
2. **Gradual Scaling** - Increase load progressively
3. **Realistic Data** - Use production-like datasets
4. **Environment Parity** - Match production configuration

### Performance Monitoring
1. **Baseline Establishment** - Record initial performance
2. **Trend Analysis** - Monitor performance over time
3. **Alert Thresholds** - Set meaningful SLO-based alerts
4. **Regular Testing** - Schedule automated performance runs

### Resource Management
1. **Resource Limits** - Set appropriate container limits
2. **Connection Pooling** - Optimize database connections
3. **Caching Strategy** - Implement effective caching
4. **Cleanup Procedures** - Regular cleanup of test data

## 🤝 Contributing

### Adding New Tests
1. Create test scripts in appropriate tool directory
2. Update orchestrator configuration
3. Add monitoring dashboards if needed
4. Document SLOs and expected results

### Monitoring Extensions
1. Add custom Grafana dashboards to `grafana/dashboards/`
2. Create Prometheus alert rules in `configs/`
3. Configure Loki log parsing rules
4. Set up Tempo trace sampling

## 📝 License

This performance testing framework is part of the PyAirtable platform and follows the same licensing terms.

---

## 🎯 Summary

This comprehensive performance testing framework provides:

✅ **Multi-tool testing** with K6, JMeter, Locust, and Artillery  
✅ **Complete test coverage** for all 8 PyAirtable services  
✅ **Real-time monitoring** with LGTM stack integration  
✅ **Automated orchestration** and report generation  
✅ **Production-ready SLOs** and performance benchmarks  
✅ **CI/CD integration** for continuous performance validation  

**Quick Start**: `./scripts/run-performance-suite.sh --suite smoke`

For questions or support, refer to the troubleshooting section or check the generated reports in the `reports/` directory.