# PyAirtable Service Dashboards

This directory contains comprehensive Grafana dashboards for all 6 PyAirtable services, designed for the LGTM (Loki, Grafana, Tempo, Mimir) observability stack.

## Dashboard Structure

### Platform Overview
- **pyairtable-overview.json** - Unified view of all services with key metrics and health status

### Service-Specific Dashboards

#### 1. API Gateway (Port 8000)
**File:** `services/api-gateway.json`
**Metrics:**
- Request rates and response times
- Authentication success/failure rates
- Rate limiting effectiveness
- Backend service routing performance
- Error analysis by status code
- Resource utilization (CPU, memory, connections)

**Key Panels:**
- Service health status
- Request rate by endpoint
- Authentication & rate limiting metrics
- Backend service routing distribution
- Response time percentiles (P50, P95, P99)

#### 2. Airtable Gateway (Port 8002)  
**File:** `services/airtable-gateway.json`
**Metrics:**
- Airtable API call rates by operation (CRUD operations)
- Cache performance (hit/miss rates, evictions)
- Data synchronization metrics
- Rate limiting and quota management
- API response time distribution
- Connection pool utilization

**Key Panels:**
- Cache hit rate gauge
- API request rate by operation type
- Sync lag and error tracking
- Rate limit remaining and queue depth
- Error analysis (4xx, 5xx, timeouts)

#### 3. LLM Orchestrator (Port 8003)
**File:** `services/llm-orchestrator.json`
**Metrics:**
- AI model usage and performance
- Cost tracking by model and operation
- Token consumption (input/output)
- MCP Server integration performance
- Response time percentiles
- Error rates by model

**Key Panels:**
- Daily AI cost tracking
- Token usage rate by model
- Cost breakdown by operation
- MCP integration metrics
- Model-specific error rates
- Thinking budget tracking

#### 4. MCP Server (Port 8001)
**File:** `services/mcp-server.json`
**Metrics:**
- MCP protocol message rates
- Tool usage statistics
- Connection management (WebSocket/HTTP)
- Resource management
- Protocol error analysis
- Session handling

**Key Panels:**
- Active MCP connections
- Available tools registry
- Tool execution times
- Protocol error breakdown
- Message queue depth
- Session resource utilization

#### 5. Platform Services (Port 8007)
**File:** `services/platform-services.json`
**Metrics:**
- User management operations
- Authentication metrics
- Analytics and usage tracking
- GDPR compliance metrics
- Database performance
- CQRS event processing

**Key Panels:**
- Total users and active sessions
- Authentication success/failure rates
- User management operations (CRUD)
- GDPR request tracking
- Database connection pool status
- Event processing lag

#### 6. Automation Services (Port 8006)
**File:** `services/automation-services.json`
**Metrics:**
- Workflow execution rates
- File processing metrics
- Webhook processing
- Scheduled task management
- Error analysis
- Worker pool utilization

**Key Panels:**
- Active workflows count
- File queue depth
- Webhook processing success/error rates
- Workflow execution time percentiles
- Scheduled task registry and execution
- Worker resource utilization

## LGTM Stack Integration

### Data Sources
All dashboards are configured to use:
- **Mimir** (primary metrics source) - `uid: mimir`
- **Loki** (logs correlation) - `uid: loki`  
- **Tempo** (distributed tracing) - `uid: tempo`

### Features
- **Trace-to-Logs Correlation**: Click on trace IDs to jump to related logs
- **Logs-to-Metrics Correlation**: Navigate from log entries to relevant metrics
- **Service Map**: Visualize service dependencies through Tempo
- **Alerting Integration**: Ready for Grafana unified alerting

### Variable Templates
Each dashboard includes:
- **Interval** selector (1m, 5m, 15m, 1h)
- **Service** filter (where applicable)
- Dynamic label value queries from Mimir

## Metric Naming Conventions

### Standard Metrics (All Services)
```
up{job="service-name"}                                    # Service health
http_requests_total{job="service-name"}                   # HTTP request counter
http_request_duration_seconds_bucket{job="service-name"}  # Request duration histogram
process_cpu_seconds_total{job="service-name"}            # CPU usage
process_resident_memory_bytes{job="service-name"}        # Memory usage
```

### Service-Specific Metrics

#### API Gateway
```
api_gateway_rate_limit_hits_total
api_gateway_auth_failures_total
api_gateway_backend_requests_total{backend="service-name"}
api_gateway_active_connections
```

#### Airtable Gateway
```
airtable_gateway_api_calls_total{operation="list_records|get_record|create_record|update_record|delete_record"}
airtable_gateway_cache_hits_total{cache_type="records|schema"}
airtable_gateway_sync_operations_total{operation="full_sync|incremental_sync"}
airtable_gateway_rate_limit_remaining{base_id="..."}
```

#### LLM Orchestrator
```
llm_orchestrator_requests_total{model="gemini-2.5-flash"}
llm_orchestrator_cost_usd_total{model="...", operation="..."}
llm_orchestrator_input_tokens_total{model="..."}
llm_orchestrator_mcp_calls_total{tool="..."}
```

#### MCP Server
```
mcp_server_messages_total{message_type="initialize|tools/list|tools/call"}
mcp_server_tool_calls_total{tool="list_records|get_record|..."}
mcp_server_active_connections
mcp_server_errors_total{error_type="invalid_request|timeout"}
```

#### Platform Services
```
platform_services_total_users
platform_services_auth_success_total
platform_services_cqrs_events_published_total{event_type="..."}
platform_services_gdpr_data_export_requests_total
```

#### Automation Services
```
automation_services_workflow_executions_total{workflow_type="data_sync|file_processing"}
automation_services_file_uploads_total{file_type="pdf|csv|..."}
automation_services_webhook_requests_total{source="..."}
automation_services_scheduled_tasks_registered{schedule_type="..."}
```

## Chaos Engineering Metrics

The overview dashboard includes panels for chaos engineering impact:
```
chaos_engineering_experiments_total
circuit_breaker_trips_total
recovery_time_seconds
failover_events_total
```

## Alert Rule Integration

Each service dashboard is designed to work with Grafana's unified alerting system. Common alert conditions:

### Critical Alerts
- Service down (`up == 0`)
- High error rate (`error_rate > 5%`)
- High response time (`p95_latency > 2s`)
- Resource exhaustion (`cpu_usage > 90%` or `memory_usage > 90%`)

### Warning Alerts  
- Elevated error rate (`error_rate > 1%`)
- Increased response time (`p95_latency > 1s`)
- Cache hit rate degradation (`cache_hit_rate < 80%`)
- Queue depth buildup (`queue_depth > 100`)

## Usage Instructions

1. **Deploy LGTM Stack**: Ensure all components are running
2. **Configure Data Sources**: Verify Mimir, Loki, and Tempo connections
3. **Import Dashboards**: Use Grafana's provisioning or manual import
4. **Set Up Alerts**: Configure notification channels and alert rules
5. **Customize Variables**: Adjust time ranges and service filters as needed

## Performance Considerations

- Dashboards are optimized for 30-second refresh intervals
- Query intervals use rate calculations over 5-minute windows
- Heavy queries (P99 percentiles) are cached appropriately
- Variable queries are optimized to reduce cardinality

## Troubleshooting

### Common Issues
1. **Missing Metrics**: Check Prometheus scrape configuration
2. **No Data**: Verify service discovery and target endpoints
3. **Slow Queries**: Adjust time ranges or increase query intervals
4. **Memory Issues**: Monitor Mimir ingestion rates and retention policies

### Debug Queries
```promql
# Check if metrics are being scraped
up{job=~".*-gateway|.*-orchestrator|.*-server|.*-services"}

# Verify metric cardinality
{__name__=~".*_total"} | group by (__name__)

# Check for high-cardinality labels
topk(10, count by (__name__)({__name__=~".+"}))
```

## Contributing

When adding new metrics or panels:
1. Follow the established naming conventions
2. Include appropriate help text and descriptions
3. Use consistent color schemes and visualization types
4. Test with the LGTM stack before committing
5. Update this README with new metric definitions