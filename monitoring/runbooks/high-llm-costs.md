# High LLM Costs Runbook

## Alert: HighLLMCosts / DailyLLMCostsBudgetExceeded

**Severity:** Warning/Critical  
**Category:** Business Metrics  
**Expected Response Time:** < 15 minutes

## Overview

This runbook provides procedures for investigating and managing high LLM (Large Language Model) costs in the PyAirtable platform.

## Immediate Actions (First 15 minutes)

### 1. Acknowledge and Assess Impact
- [ ] Acknowledge the alert
- [ ] Check current cost rate vs. budget
- [ ] Identify if this is a cost spike or gradual increase
- [ ] Assess potential business impact

### 2. Quick Cost Analysis
```bash
# Check current hourly cost rate
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_cost_total[1h]))/100"

# Check daily cost accumulation
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(increase(pyairtable_llm_cost_total[24h]))/100"

# Check cost by service
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_cost_total[1h])) by (service)/100"

# Check cost by model
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_cost_total[1h])) by (model)/100"
```

### 3. Immediate Cost Controls
```bash
# Check if any emergency cost controls are in place
curl http://localhost:8080/api/v1/cost-controls/status

# Enable rate limiting if costs are critical
curl -X POST http://localhost:8080/api/v1/cost-controls/enable-rate-limiting

# Check current usage limits
curl http://localhost:8080/api/v1/cost-controls/limits
```

## Investigation Steps (15-30 minutes)

### 4. Usage Pattern Analysis

#### Token Usage Analysis
```bash
# Check token usage rate
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_tokens_total[1h]))"

# Token usage by model
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_tokens_total[1h])) by (model)"

# Token usage by service
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_tokens_total[1h])) by (service)"

# Check for unusual token patterns
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"token_usage\" | json | line_format \"{{.user_id}} {{.tokens}}\""
```

#### Request Pattern Analysis
```bash
# Check LLM request volume
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_requests_total[1h]))"

# Request volume by user
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_requests_total[1h])) by (user_id)"

# Request volume by tenant
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_requests_total[1h])) by (tenant_id)"

# Check for request spikes
curl -s "http://localhost:8080/prometheus/api/v1/query_range?query=sum(rate(pyairtable_llm_requests_total[5m]))&start=$(date -d '2 hours ago' -u +%s)&end=$(date -u +%s)&step=300"
```

### 5. Cost Driver Identification

#### Expensive Model Usage
```bash
# Identify most expensive models in use
curl -s "http://localhost:8080/prometheus/api/v1/query?query=topk(5, sum(rate(pyairtable_llm_cost_total[1h])) by (model))"

# Check model usage trends
curl -s "http://localhost:8080/prometheus/api/v1/query_range?query=sum(rate(pyairtable_llm_cost_total[1h])) by (model)&start=$(date -d '24 hours ago' -u +%s)&end=$(date -u +%s)&step=3600"

# Compare cost per token by model
curl -s "http://localhost:8080/prometheus/api/v1/query?query=(sum(rate(pyairtable_llm_cost_total[1h])) by (model)) / (sum(rate(pyairtable_llm_tokens_total[1h])) by (model))"
```

#### High-Usage Users/Tenants
```bash
# Top users by cost
curl -s "http://localhost:8080/prometheus/api/v1/query?query=topk(10, sum(rate(pyairtable_llm_cost_total[1h])) by (user_id))"

# Top tenants by cost
curl -s "http://localhost:8080/prometheus/api/v1/query?query=topk(5, sum(rate(pyairtable_llm_cost_total[1h])) by (tenant_id))"

# Check for abnormal usage patterns
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"high_usage_detected\" | json"
```

#### Service-Specific Analysis
```bash
# Cost by service
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_cost_total[1h])) by (service)/100"

# Check AI service logs for patterns
docker-compose -f docker-compose.production.yml logs --since=2h pyairtable-ai | grep -E "(cost|expensive|tokens)" | tail -20

# Check automation service for runaway workflows
docker-compose -f docker-compose.production.yml logs --since=2h pyairtable-automation | grep -E "(workflow|llm|cost)" | tail -20
```

## Cost Control Measures (30-45 minutes)

### 6. Immediate Cost Reduction

#### Rate Limiting Implementation
```bash
# Enable per-user rate limiting
curl -X POST http://localhost:8080/api/v1/cost-controls/user-rate-limit \
  -H "Content-Type: application/json" \
  -d '{"requests_per_hour": 100, "tokens_per_hour": 10000}'

# Enable per-tenant rate limiting
curl -X POST http://localhost:8080/api/v1/cost-controls/tenant-rate-limit \
  -H "Content-Type: application/json" \
  -d '{"requests_per_hour": 1000, "tokens_per_hour": 100000}'

# Enable global rate limiting
curl -X POST http://localhost:8080/api/v1/cost-controls/global-rate-limit \
  -H "Content-Type: application/json" \
  -d '{"cost_per_hour": 50}'
```

#### Model Optimization
```bash
# Switch to cheaper models for non-critical tasks
curl -X POST http://localhost:8080/api/v1/ai/model-config \
  -H "Content-Type: application/json" \
  -d '{"default_model": "gpt-3.5-turbo", "fallback_model": "gpt-3.5-turbo-16k"}'

# Enable model cost optimization
curl -X POST http://localhost:8080/api/v1/ai/cost-optimization \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "max_cost_per_request": 0.10}'

# Implement request batching
curl -X POST http://localhost:8080/api/v1/ai/batching \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "max_batch_size": 10, "batch_timeout": 5}'
```

#### User/Tenant Restrictions
```bash
# Temporarily suspend high-usage users (if appropriate)
curl -X POST http://localhost:8080/api/v1/users/suspend \
  -H "Content-Type: application/json" \
  -d '{"user_ids": ["user1", "user2"], "reason": "cost_management", "duration": "1h"}'

# Apply temporary usage caps to high-usage tenants
curl -X POST http://localhost:8080/api/v1/tenants/usage-cap \
  -H "Content-Type: application/json" \
  -d '{"tenant_id": "tenant1", "daily_cost_limit": 100, "hourly_cost_limit": 10}'
```

### 7. Configuration Optimization

#### Prompt Optimization
```bash
# Check average prompt lengths
curl -s "http://localhost:8080/prometheus/api/v1/query?query=avg(pyairtable_llm_prompt_length)"

# Identify services with long prompts
curl -s "http://localhost:8080/prometheus/api/v1/query?query=avg(pyairtable_llm_prompt_length) by (service)"

# Enable prompt compression if available
curl -X POST http://localhost:8080/api/v1/ai/prompt-optimization \
  -H "Content-Type: application/json" \
  -d '{"compression_enabled": true, "max_prompt_length": 2000}'
```

#### Caching Implementation
```bash
# Enable response caching
curl -X POST http://localhost:8080/api/v1/ai/caching \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "ttl": 3600, "max_cache_size": "1GB"}'

# Check cache hit rate
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(pyairtable_llm_cache_hits_total[1h]) / rate(pyairtable_llm_requests_total[1h])"

# Warm up cache for common queries
curl -X POST http://localhost:8080/api/v1/ai/cache/warmup
```

## Business Impact Assessment

### 8. User Experience Impact
```bash
# Check if cost controls are affecting user experience
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(pyairtable_llm_requests_total{status=\"rate_limited\"}[1h])"

# Monitor queue lengths
curl -s "http://localhost:8080/prometheus/api/v1/query?query=pyairtable_llm_queue_length"

# Check user complaints or support tickets
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"rate_limit\" or \"queue\" or \"slow\""
```

### 9. Revenue Impact Analysis
```bash
# Check correlation between cost controls and user activity
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(pyairtable_active_users_total[1h])"

# Monitor feature usage changes
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(pyairtable_feature_usage_total[1h]) by (feature)"

# Check subscription cancellations or downgrades
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"subscription\" |= \"cancel\" or \"downgrade\""
```

## Communication

### 10. Stakeholder Notification

#### Internal Communication Template
```markdown
**LLM Cost Alert - [SEVERITY]**

Current Status: [INVESTIGATING/MITIGATING/RESOLVED]
Cost Rate: $[X]/hour (Budget: $[Y]/hour)
Daily Costs: $[X] (Budget: $[Y]/day)

Root Cause: [Brief description if identified]
Impact: [User/business impact description]
Actions Taken: [List of cost control measures]

Estimated Savings: $[X]/hour
Business Impact: [Description of any service limitations]

Next Update: [When next update will be provided]
```

#### Business Team Notification
- [ ] Notify finance team of budget impact
- [ ] Alert product team of any feature limitations
- [ ] Inform customer success team of potential user impact

## Long-term Cost Management

### 11. Budget Optimization

#### Cost Forecasting
```bash
# Generate cost trend analysis
curl -s "http://localhost:8080/prometheus/api/v1/query_range?query=sum(increase(pyairtable_llm_cost_total[1d]))/100&start=$(date -d '30 days ago' -u +%s)&end=$(date -u +%s)&step=86400" > /tmp/cost-trends.json

# Project monthly costs based on current usage
python3 -c "
import json, sys
with open('/tmp/cost-trends.json') as f:
    data = json.load(f)
    values = [float(v[1]) for v in data['data']['result'][0]['values']]
    avg_daily = sum(values[-7:]) / 7
    print(f'Projected monthly cost: \${avg_daily * 30:.2f}')
"
```

#### Cost Allocation
```bash
# Generate cost breakdown by business unit
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_cost_total[24h])) by (tenant_id, cost_center)/100"

# Create cost allocation report
./scripts/generate-cost-report.sh > /tmp/cost-allocation-$(date +%Y%m%d).csv
```

### 12. Prevention Measures

#### Enhanced Monitoring
```bash
# Implement predictive cost alerting
curl -X POST http://localhost:8080/api/v1/alerts/cost-prediction \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "prediction_window": "24h", "threshold_increase": 50}'

# Add business metric correlation
curl -X POST http://localhost:8080/api/v1/monitoring/business-correlation \
  -H "Content-Type: application/json" \
  -d '{"cost_per_user": true, "cost_per_workflow": true, "cost_efficiency": true}'
```

#### Automated Cost Controls
```bash
# Implement automatic rate limiting
curl -X POST http://localhost:8080/api/v1/cost-controls/auto-limit \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "daily_threshold": 400, "hourly_threshold": 40}'

# Enable cost-aware scaling
curl -X POST http://localhost:8080/api/v1/scaling/cost-aware \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "cost_per_instance": 0.10, "max_cost_per_hour": 50}'
```

## Verification and Recovery

### 13. Cost Reduction Verification
```bash
# Monitor cost reduction over time
watch 'curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_llm_cost_total[1h]))/100" | jq ".data.result[0].value[1]"'

# Check that user experience is maintained
curl -s "http://localhost:8080/prometheus/api/v1/query?query=histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{service=\"pyairtable-ai\"}[5m]))"

# Verify business metrics are not negatively impacted
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(pyairtable_workflow_executions_total{status=\"success\"}[1h])"
```

### 14. Gradual Control Relaxation
```bash
# Gradually increase limits as costs stabilize
curl -X POST http://localhost:8080/api/v1/cost-controls/gradual-increase \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "increase_rate": 10, "max_cost_per_hour": 45}'

# Monitor for cost re-escalation
curl -X POST http://localhost:8080/api/v1/alerts/cost-reescalation \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "threshold": 35, "lookback": "2h"}'
```

## Related Runbooks
- [Performance Degradation Runbook](performance-degradation.md)
- [Service Down Runbook](service-down.md)
- [Business Metrics Anomaly Runbook](business-metrics-anomaly.md)

## Key Metrics to Monitor
- Hourly and daily LLM costs
- Cost per request/token by model
- Usage patterns by user/tenant/service
- Cost efficiency metrics
- Business impact metrics
- User satisfaction metrics

---
**Last Updated:** [DATE]  
**Next Review:** [DATE + 1 month]