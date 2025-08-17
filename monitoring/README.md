# PyAirtable Monitoring Stack

A comprehensive monitoring and observability solution for the PyAirtable platform using the LGTM stack (Loki, Grafana, Tempo, Mimir/Prometheus).

## Overview

This monitoring setup provides:

- **Metrics Collection**: Prometheus for application and infrastructure metrics
- **Log Aggregation**: Loki for centralized log collection and analysis
- **Distributed Tracing**: Tempo for request tracing across services
- **Visualization**: Grafana for dashboards and alerting
- **Alerting**: AlertManager for notification routing

## Quick Start

### 1. Start the Monitoring Stack

```bash
# Start monitoring services
docker-compose -f docker-compose.monitoring.yml up -d

# Verify services are running
docker-compose -f docker-compose.monitoring.yml ps
```

### 2. Access Dashboards

- **Grafana**: http://localhost:3001 (admin/admin123)
- **Prometheus**: http://localhost:9090
- **AlertManager**: http://localhost:9093
- **Tempo**: http://localhost:3200

### 3. Add Monitoring to Services

Add the monitoring middleware to your Python services:

```python
from monitoring.monitoring_middleware import PyAirtableMonitoring, create_fastapi_middleware, create_health_endpoints

# Initialize monitoring
monitoring = PyAirtableMonitoring(
    service_name="your-service-name",
    service_version="1.0.0"
)

# Add to FastAPI app
app.add_middleware(create_fastapi_middleware(monitoring))
app.include_router(create_health_endpoints(monitoring))

# Mark service as ready
monitoring.mark_ready()
```

## Service Discovery

The monitoring stack automatically discovers and monitors:

### Application Services
- **API Gateway** (port 8000): `/metrics`
- **AI Processing Service** (port 8001): `/metrics`
- **Airtable Gateway** (port 8002): `/metrics`
- **Workspace Service** (port 8003): `/metrics`
- **Platform Services** (port 8007): `/metrics`
- **Automation Services** (port 8006): `/metrics`
- **SAGA Orchestrator** (port 8008): `/metrics`
- **Frontend** (port 3000): `/api/metrics`

### Infrastructure Services
- **PostgreSQL**: via postgres-exporter (port 9187)
- **Redis** (main): via redis-exporter (port 9121)
- **Redis Streams**: via redis-streams-exporter (port 9122)
- **Redis Queue**: via redis-queue-exporter (port 9123)

### System Metrics
- **Node Exporter** (port 9100): Host system metrics
- **cAdvisor** (port 8080): Container metrics

## Dashboards

### System Overview Dashboard
- Service health status
- Request rates and latency
- Error rates
- Resource utilization

### Service-Specific Dashboards
Individual dashboards for each service showing:
- HTTP metrics (requests, latency, errors)
- Database operations
- Cache performance
- External API calls
- Business metrics

### Infrastructure Dashboard
- PostgreSQL performance
- Redis performance
- Container metrics
- Host system metrics

## Alerting Rules

### Service Health Alerts
- **ServiceDown**: Service is completely unavailable
- **ServiceHighErrorRate**: Error rate > 10%
- **ServiceHighLatency**: 95th percentile latency > 1s

### Infrastructure Alerts
- **RedisDown**: Redis instance unavailable
- **RedisHighMemoryUsage**: Redis memory usage > 80%
- **PostgreSQLDown**: PostgreSQL unavailable
- **PostgreSQLTooManyConnections**: Connection usage > 80%

### Performance Alerts
- **APIGatewayHighLatency**: API Gateway latency > 2s
- **APIGatewayHighErrorRate**: API Gateway error rate > 5%
- **SAGAOrchestratorFailureRate**: SAGA failure rate > 1%

### Resource Alerts
- **HighCPUUsage**: CPU usage > 80%
- **HighMemoryUsage**: Memory usage > 80%
- **HighDiskUsage**: Disk usage > 80%

## Log Aggregation

Promtail collects logs from all Docker containers and ships them to Loki. Logs are parsed and labeled with:

- Service name
- Container name
- Log level
- Trace ID (for correlation)
- Request ID

### Log Parsing

Different parsers for different services:
- **JSON logs**: Standard structured logs
- **API Gateway**: HTTP request logs with method, path, status
- **AI Processing**: Model usage and token consumption
- **PostgreSQL**: Database query logs
- **Redis**: Redis operation logs

## Distributed Tracing

OpenTelemetry provides distributed tracing through Tempo:

### Automatic Instrumentation
- HTTP requests (requests library)
- Database queries (psycopg2)
- Redis operations
- Inter-service calls

### Custom Spans
```python
with monitoring.create_span("custom-operation") as span:
    span.set_attribute("user_id", user_id)
    # Your code here
```

### Trace Correlation
Logs are automatically correlated with traces using trace IDs.

## Custom Metrics

### Business Metrics
- **airtable_requests_total**: Airtable API requests by base, table, operation
- **ai_processing_requests_total**: AI requests by model and operation
- **saga_operations_total**: SAGA operations by type and step

### Application Metrics
- **database_operations_total**: Database operations by table and type
- **cache_operations_total**: Cache operations
- **external_api_requests_total**: External API calls
- **queue_operations_total**: Queue operations

## Health Checks

Each service provides multiple health check endpoints:

- **`/health`**: Comprehensive health status
- **`/health/ready`**: Readiness check for load balancer
- **`/health/live`**: Liveness check for container orchestrator
- **`/metrics`**: Prometheus metrics

## Configuration

### Environment Variables

```bash
# Service configuration
SERVICE_NAME=your-service
SERVICE_VERSION=1.0.0

# OpenTelemetry
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
OTEL_SERVICE_NAME=your-service

# Prometheus
PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus

# Logging
LOG_LEVEL=INFO
LOG_FORMAT=json
```

### Custom Health Checks

```python
def check_database():
    # Your database connectivity check
    return True

def check_redis():
    # Your Redis connectivity check
    return True

monitoring.add_health_check("database", check_database)
monitoring.add_health_check("redis", check_redis)
```

## Troubleshooting

### Common Issues

1. **Metrics not appearing**
   - Check if `/metrics` endpoint is accessible
   - Verify Prometheus can reach the service
   - Check Prometheus targets page

2. **Traces not showing**
   - Verify OpenTelemetry collector is running
   - Check OTLP endpoint configuration
   - Look for errors in service logs

3. **Logs not aggregating**
   - Check Promtail configuration
   - Verify Docker socket access
   - Check Loki ingestion logs

### Debug Commands

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Check Loki readiness
curl http://localhost:3100/ready

# Check Tempo readiness
curl http://localhost:3200/ready

# Check service metrics
curl http://localhost:8000/metrics

# Check service health
curl http://localhost:8000/health
```

## Security Considerations

- Metrics endpoints should be internal-only in production
- Use authentication for Grafana dashboard access
- Secure AlertManager webhook endpoints
- Consider TLS for inter-service communication
- Implement rate limiting on health check endpoints

## Performance Impact

The monitoring stack is designed for minimal performance impact:

- **Metrics collection**: ~1-2ms overhead per request
- **Tracing**: ~100μs overhead per span
- **Log shipping**: Asynchronous, no request blocking
- **Health checks**: Cached responses, configurable intervals

## Scaling Considerations

For production deployments:

- Use external storage for Prometheus (Thanos, Cortex, or Mimir)
- Configure log retention policies in Loki
- Set up Tempo with object storage backend
- Use Grafana clustering for high availability
- Implement metric federation for multi-cluster setups