# OpenTelemetry (OTLP) Integration for PyAirtable Services

This document describes the OpenTelemetry integration for PyAirtable Python services, providing comprehensive observability through traces, metrics, and logs exported to the LGTM stack (Loki, Grafana, Tempo, Mimir).

## 🎯 Overview

The OpenTelemetry integration provides:

- **Distributed Tracing**: End-to-end request tracing across all Python services
- **Metrics Collection**: Performance and business metrics exported to Mimir
- **Structured Logging**: JSON logs with trace correlation sent to Loki
- **Cost Tracking**: LLM API call cost monitoring and attribution
- **Auto-instrumentation**: FastAPI, SQLAlchemy, Redis, and HTTP client tracing

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Python Service │───▶│  OTEL Collector  │───▶│   LGTM Stack    │
│  (Port 8001-8006)│    │  (Port 4317/4318)│    │                 │
└─────────────────┘    └──────────────────┘    │ - Tempo (Traces)│
                                               │ - Mimir (Metrics)│
                                               │ - Loki (Logs)   │
                                               │ - Grafana (UI)  │
                                               └─────────────────┘
```

## 🔧 Services Configured

| Service | Port | Type | Layer |
|---------|------|------|-------|
| LLM Orchestrator | 8003 | ai-ml | ai-processing |
| Airtable Gateway | 8002 | integration | api-integration |
| MCP Server | 8001 | protocol | protocol-gateway |
| Automation Services | 8006 | automation | workflow-processing |

## 📦 Dependencies Added

All services now include the following OpenTelemetry dependencies:

```txt
# OpenTelemetry dependencies
opentelemetry-api==1.21.0
opentelemetry-sdk==1.21.0
opentelemetry-exporter-otlp==1.21.0
opentelemetry-exporter-jaeger==1.21.0
opentelemetry-instrumentation==0.42b0
opentelemetry-instrumentation-fastapi==0.42b0
opentelemetry-instrumentation-httpx==0.42b0
opentelemetry-instrumentation-redis==0.42b0
opentelemetry-instrumentation-sqlalchemy==0.42b0
opentelemetry-instrumentation-asyncpg==0.42b0
opentelemetry-instrumentation-logging==0.42b0
opentelemetry-instrumentation-system-metrics==0.42b0
opentelemetry-distro==0.42b0
opentelemetry-propagator-b3==1.21.0
opentelemetry-propagator-jaeger==1.21.0
opentelemetry-semantic-conventions==0.42b0

# Structured logging for Loki integration
structlog==23.2.0
```

## ⚙️ Configuration

### Environment Variables

Copy the environment template and configure for your environment:

```bash
cp python-services/.env.otel.template python-services/.env.otel
```

Key configuration variables:

```bash
# OTLP Endpoints
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://localhost:4318

# Environment and Sampling
ENVIRONMENT=development
OTEL_SAMPLING_RATIO=1.0  # 100% sampling for dev, 0.1 for prod
OTEL_DEBUG=true

# Service Configuration
SERVICE_VERSION=1.0.0
LOG_LEVEL=INFO

# LGTM Stack Endpoints
LOKI_ENDPOINT=http://localhost:3100
GRAFANA_URL=http://localhost:3000
TEMPO_URL=http://localhost:3200
MIMIR_URL=http://localhost:9009
```

### Service-Specific Configuration

Each service is configured with specific resource attributes:

- **Service Port**: Identifies the service by its port number
- **Service Type**: Categorizes the service functionality
- **Service Layer**: Defines the architectural layer

## 🚀 Getting Started

### 1. Start the LGTM Stack

```bash
# Start the monitoring stack
cd monitoring/lgtm-stack
docker-compose up -d
```

### 2. Start Services with OpenTelemetry

```bash
# Using Docker Compose (recommended for testing)
docker-compose -f docker-compose.otel-test.yml up -d

# Or start individual services
cd python-services/llm-orchestrator
source ../.env.otel
python src/main.py
```

### 3. Run Integration Tests

```bash
# Install test dependencies
pip install httpx structlog

# Run the integration test suite
python test-otel-integration.py
```

### 4. Access Observability Dashboards

- **Grafana**: http://localhost:3000 (admin/admin)
- **Tempo**: http://localhost:3200
- **Loki**: http://localhost:3100
- **Mimir**: http://localhost:9009

## 📊 Features

### Distributed Tracing

- **Automatic Request Tracing**: Every HTTP request generates a trace
- **Cross-Service Correlation**: Traces span multiple services
- **Database Query Tracing**: SQLAlchemy and AsyncPG operations
- **Redis Operation Tracing**: Cache operations and session management
- **HTTP Client Tracing**: External API calls and inter-service communication

### LLM Cost Tracking

The LLM Orchestrator includes specialized instrumentation for cost tracking:

```python
# Automatic cost tracking for Gemini API calls
with TraceContext("gemini.chat_completion") as span:
    # ... API call logic ...
    
    add_ai_attributes(
        span,
        provider="google",
        model=model_name,
        input_tokens=usage["prompt_tokens"],
        output_tokens=usage["completion_tokens"],
        cost_usd=cost
    )
```

### Custom Business Metrics

Services can add business context to traces:

```python
add_business_attributes(
    span,
    user_id="user123",
    tenant_id="tenant456",
    api_key_hash="abc***xyz",
    cost_center="engineering"
)
```

### Structured Logging

JSON logs with trace correlation:

```json
{
  "timestamp": "2025-01-08T12:00:00Z",
  "level": "INFO",
  "service": {
    "name": "llm-orchestrator",
    "version": "1.0.0"
  },
  "message": "LLM API call completed",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "context": {
    "ai_provider": "google",
    "ai_model": "gemini-2.0-flash-exp",
    "ai_cost_usd": 0.001234,
    "duration_ms": 450
  }
}
```

## 🧪 Testing

The integration test suite validates:

1. **Service Health**: All services are responding
2. **Observability Health**: LGTM stack components are ready
3. **Trace Generation**: Services generate proper traces
4. **Metric Collection**: OTEL Collector is receiving metrics
5. **Log Integration**: Logs are being sent to Loki
6. **Cost Tracking**: LLM calls include cost data
7. **Performance Metrics**: Response time categorization

Run tests:

```bash
python test-otel-integration.py
```

Expected output:
```
✅ All tests passed! OpenTelemetry integration is working correctly.
```

## 📈 Monitoring and Alerts

### Key Metrics to Monitor

1. **Service Performance**
   - Request duration percentiles (p50, p95, p99)
   - Error rates by service and endpoint
   - Throughput (requests per second)

2. **LLM Cost Tracking**
   - Total cost per service/tenant/user
   - Token usage trends
   - Cost per request ratios

3. **System Health**
   - Database connection pool utilization
   - Redis cache hit rates
   - Memory and CPU usage

### Grafana Dashboards

Pre-configured dashboards are available in `monitoring/lgtm-stack/grafana/dashboards/`:

- **PyAirtable Services Overview**: Service health and performance
- **LLM Cost Tracking**: AI/ML cost monitoring and attribution
- **Distributed Tracing**: Request flow visualization
- **Error Analysis**: Error rates and patterns

## 🔍 Troubleshooting

### Common Issues

1. **Traces Not Appearing in Tempo**
   - Check OTEL Collector health: `curl http://localhost:13133/health`
   - Verify sampling configuration: `OTEL_SAMPLING_RATIO=1.0`
   - Check service logs for OpenTelemetry initialization messages

2. **Logs Not in Loki**
   - Verify Loki endpoint: `curl http://localhost:3100/ready`
   - Check structured logging configuration in service logs
   - Ensure `structlog` dependency is installed

3. **High Cost Tracking Not Working**
   - Verify Gemini API key is configured
   - Check LLM Orchestrator service logs for cost calculation
   - Ensure trace context is properly propagated

4. **Metrics Missing in Mimir**
   - Check OTEL Collector metrics endpoint: `curl http://localhost:8888/metrics`
   - Verify Mimir is receiving data: `curl http://localhost:9009/ready`
   - Check collector configuration for metrics pipeline

### Debug Mode

Enable debug mode for detailed logging:

```bash
export OTEL_DEBUG=true
export LOG_LEVEL=DEBUG
```

### Performance Impact

The OpenTelemetry integration is designed for minimal performance impact:

- **Production Sampling**: 10% of requests traced (configurable)
- **Batch Processing**: Spans and metrics exported in batches
- **Async Export**: Non-blocking telemetry export
- **Resource Limits**: Configured memory and CPU limits

## 🛠️ Advanced Configuration

### Custom Instrumentation

Add custom spans to your code:

```python
from python-services.shared.telemetry import TraceContext, add_workflow_attributes

with TraceContext("custom.workflow.execution") as span:
    add_workflow_attributes(
        span,
        workflow_id="wf123",
        workflow_type="data_processing",
        status="running"
    )
    
    # Your workflow logic here
    result = process_workflow()
    
    span.set_attribute("workflow.result_count", len(result))
```

### Sampling Configuration

Configure different sampling rates for different environments:

```python
# Development: 100% sampling
OTEL_SAMPLING_RATIO=1.0

# Staging: 50% sampling  
OTEL_SAMPLING_RATIO=0.5

# Production: 10% sampling
OTEL_SAMPLING_RATIO=0.1
```

### Resource Attributes

Add custom resource attributes for better service identification:

```bash
OTEL_RESOURCE_ATTRIBUTES=platform.name=pyairtable,platform.cluster=prod-east,deployment.version=v2.1.0
```

## 📚 References

- [OpenTelemetry Python Documentation](https://opentelemetry.io/docs/instrumentation/python/)
- [OTLP Specification](https://opentelemetry.io/docs/reference/specification/protocol/otlp/)
- [Grafana LGTM Stack](https://grafana.com/oss/lgtm-stack/)
- [Tempo Tracing](https://grafana.com/oss/tempo/)
- [Loki Logging](https://grafana.com/oss/loki/)

## 🤝 Contributing

When adding new services or features:

1. Include OpenTelemetry dependencies in `requirements.txt`
2. Initialize telemetry in the service's `main.py`
3. Add service-specific instrumentation as needed
4. Update this documentation
5. Add tests to the integration test suite

## 🔒 Security Considerations

- **API Key Protection**: Never log sensitive data in traces or logs
- **Data Sanitization**: Sanitize SQL queries and request bodies
- **Access Control**: Secure observability endpoints in production
- **TLS Configuration**: Enable TLS for OTLP export in production

---

For questions or issues, please check the service logs and monitoring dashboards first, then consult this documentation or contact the platform team.