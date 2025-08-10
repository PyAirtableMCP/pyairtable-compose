# PyAirtable Monitoring Stack Deployment Guide

## Overview

This comprehensive monitoring solution provides complete observability for the PyAirtable platform, including all 6 consolidated services:

1. **API Gateway** - Main entry point
2. **LLM Orchestrator** - AI/ML service with cost tracking
3. **MCP Server** - Protocol implementation
4. **Airtable Gateway** - External API integration
5. **Platform Services** - Auth & Analytics
6. **Automation Services** - Workflows & Files
7. **SAGA Orchestrator** - Distributed transactions
8. **Frontend** - Next.js web interface

## Architecture

### Core Components

- **Prometheus** - Metrics collection and alerting
- **Grafana** - Visualization and dashboards
- **Jaeger** - Distributed tracing
- **OpenTelemetry Collector** - Telemetry data processing
- **Alertmanager** - Alert handling and routing

### Logging Options

**Option 1: Loki Stack (Lightweight)**
- **Loki** - Log aggregation
- **Promtail** - Log shipping

**Option 2: ELK Stack (Comprehensive)**
- **Elasticsearch** - Log storage and search
- **Kibana** - Log visualization
- **Logstash** - Log processing
- **Filebeat** - Log shipping

### Infrastructure Monitoring

- **Node Exporter** - Host metrics
- **cAdvisor** - Container metrics
- **Redis Exporter** - Redis metrics
- **PostgreSQL Exporter** - Database metrics

## Quick Start

### 1. Deploy Monitoring Stack

```bash
# Deploy with lightweight logging (recommended for development)
./deploy-monitoring-stack.sh deploy loki

# Deploy with comprehensive logging (recommended for production)
./deploy-monitoring-stack.sh deploy elk

# Deploy with both logging stacks
./deploy-monitoring-stack.sh deploy both
```

### 2. Access Services

```bash
# Show all service URLs
./deploy-monitoring-stack.sh urls

# Core services will be available at:
# - Grafana: http://localhost:3001 (admin/admin123)
# - Prometheus: http://localhost:9090
# - Jaeger: http://localhost:16686
# - AlertManager: http://localhost:9093
```

### 3. Verify Deployment

```bash
# Verify all services are healthy
./deploy-monitoring-stack.sh verify loki

# Show available dashboards
./deploy-monitoring-stack.sh dashboards
```

## Dashboards

### Platform Dashboards

1. **PyAirtable Platform Overview**
   - Service health status
   - Request rates and error rates
   - Response times and resource usage

2. **AI/LLM Cost Tracking**
   - Daily AI API costs and token usage
   - Cost breakdown by model
   - Request latency percentiles
   - Error rates and trends

3. **Business Metrics**
   - User engagement metrics
   - Workflow execution statistics
   - File processing activity
   - SAGA transaction patterns

### Infrastructure Dashboards

1. **Infrastructure Overview**
   - System resource usage (CPU, Memory, Disk)
   - Network I/O and container metrics
   - Database and cache performance

## Configuration

### Environment Variables

Edit `.env` file to customize the monitoring stack:

```bash
# Grafana Configuration
GRAFANA_ADMIN_PASSWORD=your_secure_password

# Alerting Configuration
SMTP_HOST=your.smtp.server:587
ALERT_FROM_EMAIL=alerts@your-domain.com
SLACK_WEBHOOK_URL=https://hooks.slack.com/your-webhook

# Notification Emails
CRITICAL_EMAIL=ops@your-domain.com
ONCALL_EMAIL=oncall@your-domain.com
SECURITY_EMAIL=security@your-domain.com
```

### Retention Policies

- **Prometheus**: 15 days (configurable)
- **Loki**: 14 days (configurable)
- **Jaeger**: 2 days (memory-based)

## Service Integration

### Adding Metrics to Services

To enable monitoring for your services, add these endpoints:

```python
# Python services - add to your main application
from prometheus_client import Counter, Histogram, generate_latest

# Metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'HTTP request duration')

@app.route('/metrics')
def metrics():
    return generate_latest()
```

### OpenTelemetry Integration

For distributed tracing, configure OpenTelemetry in your services:

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Configure tracing
trace.set_tracer_provider(TracerProvider())
otlp_exporter = OTLPSpanExporter(endpoint="http://otel-collector:4317")
span_processor = BatchSpanProcessor(otlp_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)
```

## Alerting

### Alert Categories

1. **Critical Alerts**
   - Service down
   - High error rates
   - Database issues

2. **Performance Alerts**
   - High response times
   - Resource exhaustion
   - Slow queries

3. **Security Alerts**
   - Authentication failures
   - Suspicious activity

4. **Cost Optimization**
   - Unused services
   - High AI API costs
   - Inefficient resource usage

5. **Business Metrics**
   - Low user engagement
   - Workflow failures

### Notification Channels

- **Email** - Critical alerts and reports
- **Slack** - Real-time notifications
- **PagerDuty** - Incident escalation
- **Webhooks** - Custom integrations

## Troubleshooting

### Common Issues

1. **Services Not Starting**
   ```bash
   # Check Docker resources
   docker system df
   
   # Check service logs
   ./deploy-monitoring-stack.sh logs prometheus
   ```

2. **High Resource Usage**
   ```bash
   # Monitor container resources
   docker stats
   
   # Adjust retention in .env file
   PROMETHEUS_RETENTION=7d
   LOKI_RETENTION=7d
   ```

3. **Metrics Not Appearing**
   - Verify service /metrics endpoints
   - Check Prometheus targets: http://localhost:9090/targets
   - Review Prometheus configuration

### Log Management

```bash
# View specific service logs
./deploy-monitoring-stack.sh logs grafana

# View all logs
./deploy-monitoring-stack.sh logs

# Check log volume usage
docker system df
```

## Maintenance

### Regular Tasks

1. **Monitor Disk Usage**
   ```bash
   # Check volume usage
   docker system df -v
   
   # Clean up old data if needed
   docker system prune -f
   ```

2. **Update Dashboards**
   - Dashboards are automatically provisioned
   - Edit JSON files in `monitoring/grafana/dashboards/`
   - Restart Grafana to reload

3. **Backup Configuration**
   ```bash
   # Backup Grafana data
   docker run --rm -v pyairtable-compose_grafana-data:/source:ro \
     -v $(pwd):/backup alpine tar czf /backup/grafana-backup.tar.gz -C /source .
   ```

### Scaling Considerations

For production environments:

1. **External Prometheus Storage**
   - Configure remote write to external TSDB
   - Use Prometheus federation for multiple clusters

2. **High Availability**
   - Deploy multiple Prometheus instances
   - Use external storage for Grafana
   - Implement load balancing

3. **Security**
   - Enable authentication for all services
   - Use TLS certificates
   - Implement network segmentation

## Advanced Configuration

### Custom Metrics

Add business-specific metrics to your services:

```python
# AI/LLM Cost Tracking
AI_COST_COUNTER = Counter('ai_api_cost_total', 'Total AI API costs', ['model', 'service'])
AI_TOKEN_COUNTER = Counter('ai_tokens_used_total', 'Total tokens used', ['type', 'model'])

# Business Metrics
USER_SESSION_COUNTER = Counter('user_sessions_total', 'Total user sessions')
WORKFLOW_COUNTER = Counter('workflow_executions_total', 'Workflow executions', ['type', 'status'])
```

### Alert Customization

Edit `monitoring/prometheus/alert_rules.yml` to add custom alerts:

```yaml
- alert: CustomBusinessMetric
  expr: rate(your_custom_metric[5m]) > threshold
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Custom business alert triggered"
```

## Cost Optimization

### Resource Limits

The monitoring stack is configured with resource limits:

- **Prometheus**: 512MB RAM, 0.5 CPU
- **Grafana**: 256MB RAM, 0.3 CPU
- **Loki**: 512MB RAM, 0.4 CPU
- **Elasticsearch**: 1GB RAM, 0.7 CPU (if using ELK)

### Storage Management

- Automatic data retention policies
- Compression for long-term storage
- Tiered storage for cost optimization

## Support

### Getting Help

1. Check service logs: `./deploy-monitoring-stack.sh logs [service]`
2. Verify service health: `./deploy-monitoring-stack.sh verify`
3. Review Prometheus targets: http://localhost:9090/targets
4. Check Grafana datasources: http://localhost:3001/datasources

### Cleanup

```bash
# Stop services
./deploy-monitoring-stack.sh stop

# Remove everything including data
./deploy-monitoring-stack.sh cleanup
```

---

## Service URLs Quick Reference

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3001 | admin/admin123 |
| Prometheus | http://localhost:9090 | - |
| Jaeger | http://localhost:16686 | - |
| AlertManager | http://localhost:9093 | - |
| Loki | http://localhost:3100 | - |
| Kibana | http://localhost:5601 | - (if ELK enabled) |
| Node Exporter | http://localhost:9100 | - |
| cAdvisor | http://localhost:8080 | - |

For questions or issues, check the logs and service health endpoints first.