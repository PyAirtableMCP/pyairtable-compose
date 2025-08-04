#!/bin/bash

# Canary Validation Script for PyAirtable
# Validates canary deployments with comprehensive health checks

set -euo pipefail

# Configuration
ENVIRONMENT=${ENVIRONMENT:-"prod"}
SERVICE=${SERVICE:-""}
NAMESPACE="pyairtable-${ENVIRONMENT}"
VALIDATION_DURATION=${VALIDATION_DURATION:-300}  # 5 minutes
SUCCESS_THRESHOLD=${SUCCESS_THRESHOLD:-95}        # 95% success rate
MAX_LATENCY_MS=${MAX_LATENCY_MS:-500}            # 500ms max latency

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

debug() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $1${NC}"
}

# Health check function
health_check() {
    local endpoint=$1
    local expected_status=${2:-200}
    
    local response=$(curl -s -w "HTTPSTATUS:%{http_code};TIME:%{time_total}" -o /dev/null "$endpoint" || echo "HTTPSTATUS:000;TIME:999")
    local status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local time=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    local time_ms=$(echo "$time * 1000" | bc | cut -d. -f1)
    
    if [[ "$status" == "$expected_status" ]]; then
        echo "success:$time_ms"
    else
        echo "failed:$time_ms"
    fi
}

# Get service endpoints
get_service_endpoints() {
    local service_name=$1
    
    # Get canary endpoint
    local canary_endpoint=""
    local stable_endpoint=""
    
    # Check if we have Istio virtual service for canary routing
    if kubectl get virtualservice "${service_name}" -n "$NAMESPACE" &>/dev/null; then
        # Use Istio routing
        canary_endpoint="http://${service_name}-canary.${NAMESPACE}.svc.cluster.local:8000"
        stable_endpoint="http://${service_name}.${NAMESPACE}.svc.cluster.local:8000"
    else
        # Use direct service endpoints
        canary_endpoint="http://${service_name}-canary.${NAMESPACE}.svc.cluster.local:8000"
        stable_endpoint="http://${service_name}.${NAMESPACE}.svc.cluster.local:8000"
    fi
    
    echo "$canary_endpoint,$stable_endpoint"
}

# Performance test
run_performance_test() {
    local endpoint=$1
    local duration=$2
    local rps=${3:-10}  # requests per second
    
    log "Running performance test against $endpoint for ${duration}s at ${rps} RPS"
    
    # Create K6 test script
    cat > /tmp/k6-canary-test.js << EOF
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

export let errorRate = new Rate('errors');
export let responseTime = new Trend('response_time');

export let options = {
    duration: '${duration}s',
    rps: ${rps},
    thresholds: {
        errors: ['rate<0.05'], // 5% error rate threshold
        response_time: ['p(95)<${MAX_LATENCY_MS}'], // 95th percentile under ${MAX_LATENCY_MS}ms
        http_req_duration: ['p(99)<1000'], // 99th percentile under 1s
    },
};

export default function() {
    // Health check
    let healthResponse = http.get('${endpoint}/health');
    let healthCheck = check(healthResponse, {
        'health status is 200': (r) => r.status === 200,
        'health response time < 100ms': (r) => r.timings.duration < 100,
    });
    errorRate.add(!healthCheck);
    responseTime.add(healthResponse.timings.duration);
    
    // API endpoint test
    let apiResponse = http.get('${endpoint}/api/health');
    let apiCheck = check(apiResponse, {
        'api status is 200': (r) => r.status === 200,
        'api response time < 200ms': (r) => r.timings.duration < 200,
    });
    errorRate.add(!apiCheck);
    responseTime.add(apiResponse.timings.duration);
    
    // Simulate some think time
    sleep(0.1);
}
EOF

    # Run K6 test
    if command -v k6 &> /dev/null; then
        k6 run /tmp/k6-canary-test.js --out json=/tmp/k6-results.json
        local exit_code=$?
        
        # Parse results
        if [[ -f /tmp/k6-results.json ]]; then
            local error_rate=$(grep '"metric":"errors"' /tmp/k6-results.json | tail -1 | jq -r '.data.value // 0')
            local avg_response_time=$(grep '"metric":"response_time"' /tmp/k6-results.json | tail -1 | jq -r '.data.value // 0')
            local p95_response_time=$(grep '"metric":"http_req_duration","type":"Point"' /tmp/k6-results.json | jq -s 'sort_by(.data.value) | .[(.| length * 0.95 | floor)].data.value // 0')
            
            echo "error_rate:$error_rate,avg_response_time:$avg_response_time,p95_response_time:$p95_response_time,exit_code:$exit_code"
        else
            echo "error_rate:1,avg_response_time:999,p95_response_time:999,exit_code:1"
        fi
    else
        warn "K6 not available, falling back to simple curl tests"
        
        # Simple curl-based test
        local total_requests=0
        local failed_requests=0
        local total_time=0
        local start_time=$(date +%s)
        local end_time=$((start_time + duration))
        
        while [[ $(date +%s) -lt $end_time ]]; do
            local result=$(health_check "$endpoint/health")
            local status=$(echo "$result" | cut -d: -f1)
            local time_ms=$(echo "$result" | cut -d: -f2)
            
            total_requests=$((total_requests + 1))
            total_time=$((total_time + time_ms))
            
            if [[ "$status" != "success" ]]; then
                failed_requests=$((failed_requests + 1))
            fi
            
            sleep 0.1  # 10 RPS
        done
        
        local error_rate=$(echo "scale=4; $failed_requests / $total_requests" | bc)
        local avg_response_time=$(echo "scale=2; $total_time / $total_requests" | bc)
        
        echo "error_rate:$error_rate,avg_response_time:$avg_response_time,p95_response_time:$avg_response_time,exit_code:0"
    fi
    
    # Cleanup
    rm -f /tmp/k6-canary-test.js /tmp/k6-results.json
}

# Compare canary vs stable performance
compare_performance() {
    local canary_endpoint=$1
    local stable_endpoint=$2
    local test_duration=$3
    
    log "Comparing canary vs stable performance"
    
    # Test canary
    log "Testing canary endpoint..."
    local canary_results=$(run_performance_test "$canary_endpoint" "$test_duration" 5)
    local canary_error_rate=$(echo "$canary_results" | cut -d, -f1 | cut -d: -f2)
    local canary_response_time=$(echo "$canary_results" | cut -d, -f2 | cut -d: -f2)
    local canary_p95=$(echo "$canary_results" | cut -d, -f3 | cut -d: -f2)
    
    # Test stable
    log "Testing stable endpoint..."
    local stable_results=$(run_performance_test "$stable_endpoint" "$test_duration" 5)
    local stable_error_rate=$(echo "$stable_results" | cut -d, -f1 | cut -d: -f2)
    local stable_response_time=$(echo "$stable_results" | cut -d, -f2 | cut -d: -f2)
    local stable_p95=$(echo "$stable_results" | cut -d, -f3 | cut -d: -f2)
    
    log "Performance comparison results:"
    log "  Canary  - Error rate: ${canary_error_rate}, Avg response: ${canary_response_time}ms, P95: ${canary_p95}ms"
    log "  Stable  - Error rate: ${stable_error_rate}, Avg response: ${stable_response_time}ms, P95: ${stable_p95}ms"
    
    # Calculate performance degradation
    local error_rate_diff=$(echo "scale=4; $canary_error_rate - $stable_error_rate" | bc)
    local response_time_diff=$(echo "scale=2; $canary_response_time - $stable_response_time" | bc)
    local p95_diff=$(echo "scale=2; $canary_p95 - $stable_p95" | bc)
    
    # Validation thresholds
    local max_error_rate_increase=0.02    # 2% increase allowed
    local max_response_time_increase=50   # 50ms increase allowed
    local max_p95_increase=100           # 100ms P95 increase allowed
    
    local validation_passed=true
    
    # Check error rate
    if (( $(echo "$error_rate_diff > $max_error_rate_increase" | bc -l) )); then
        error "Canary error rate increased by ${error_rate_diff} (threshold: ${max_error_rate_increase})"
        validation_passed=false
    fi
    
    # Check response time
    if (( $(echo "$response_time_diff > $max_response_time_increase" | bc -l) )); then
        error "Canary response time increased by ${response_time_diff}ms (threshold: ${max_response_time_increase}ms)"
        validation_passed=false
    fi
    
    # Check P95
    if (( $(echo "$p95_diff > $max_p95_increase" | bc -l) )); then
        error "Canary P95 response time increased by ${p95_diff}ms (threshold: ${max_p95_increase}ms)"
        validation_passed=false
    fi
    
    if [[ "$validation_passed" == "true" ]]; then
        log "✅ Performance comparison PASSED"
        return 0
    else
        error "❌ Performance comparison FAILED"
        return 1
    fi
}

# Check business metrics
check_business_metrics() {
    local service_name=$1
    
    log "Checking business metrics for $service_name"
    
    # Query Prometheus for business metrics
    local prometheus_url="http://prometheus.monitoring.svc.cluster.local:9090"
    
    # Check conversion rate (example business metric)
    local conversion_query="rate(business_conversions_total{service=\"$service_name\",version=\"canary\"}[5m]) / rate(business_events_total{service=\"$service_name\",version=\"canary\"}[5m])"
    local stable_conversion_query="rate(business_conversions_total{service=\"$service_name\",version=\"stable\"}[5m]) / rate(business_events_total{service=\"$service_name\",version=\"stable\"}[5m])"
    
    # Execute queries (if Prometheus is available)
    if curl -s "$prometheus_url/api/v1/query" &>/dev/null; then
        local canary_conversion=$(curl -s "$prometheus_url/api/v1/query" --data-urlencode "query=$conversion_query" | jq -r '.data.result[0].value[1] // "0"')
        local stable_conversion=$(curl -s "$prometheus_url/api/v1/query" --data-urlencode "query=$stable_conversion_query" | jq -r '.data.result[0].value[1] // "0"')
        
        log "Business metrics:"
        log "  Canary conversion rate: ${canary_conversion}"
        log "  Stable conversion rate: ${stable_conversion}"
        
        # Check if canary conversion rate is significantly lower
        local conversion_diff=$(echo "scale=4; $stable_conversion - $canary_conversion" | bc)
        if (( $(echo "$conversion_diff > 0.05" | bc -l) )); then  # 5% drop threshold
            warn "Canary conversion rate is ${conversion_diff} lower than stable"
            return 1
        fi
    else
        warn "Prometheus not accessible, skipping business metrics check"
    fi
    
    return 0
}

# Check error logs
check_error_logs() {
    local service_name=$1
    local time_window="5m"
    
    log "Checking error logs for $service_name"
    
    # Get error logs from canary pods
    local canary_pods=$(kubectl get pods -n "$NAMESPACE" -l app="$service_name",version=canary -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$canary_pods" ]]; then
        warn "No canary pods found for $service_name"
        return 0
    fi
    
    local error_count=0
    
    for pod in $canary_pods; do
        # Count ERROR level logs in the last 5 minutes
        local pod_errors=$(kubectl logs "$pod" -n "$NAMESPACE" --since="$time_window" 2>/dev/null | grep -c "ERROR\|FATAL\|CRITICAL" || echo "0")
        error_count=$((error_count + pod_errors))
    done
    
    log "Found $error_count error log entries in canary pods"
    
    # Threshold: more than 10 errors per 5 minutes is concerning
    if [[ $error_count -gt 10 ]]; then
        error "High error count detected in canary logs: $error_count"
        
        # Show sample error logs
        log "Sample error logs:"
        for pod in $canary_pods; do
            kubectl logs "$pod" -n "$NAMESPACE" --since="$time_window" 2>/dev/null | grep "ERROR\|FATAL\|CRITICAL" | head -3
        done
        
        return 1
    fi
    
    return 0
}

# Validate canary deployment
validate_canary() {
    local service_name=${1:-$SERVICE}
    
    if [[ -z "$service_name" ]]; then
        error "Service name is required"
        return 1
    fi
    
    log "Starting canary validation for $service_name in $ENVIRONMENT"
    
    # Check if canary is actually running
    local canary_pods=$(kubectl get pods -n "$NAMESPACE" -l app="$service_name",version=canary --field-selector=status.phase=Running -o name | wc -l)
    if [[ $canary_pods -eq 0 ]]; then
        error "No running canary pods found for $service_name"
        return 1
    fi
    
    log "Found $canary_pods running canary pods"
    
    # Get service endpoints
    local endpoints=$(get_service_endpoints "$service_name")
    local canary_endpoint=$(echo "$endpoints" | cut -d, -f1)
    local stable_endpoint=$(echo "$endpoints" | cut -d, -f2)
    
    log "Canary endpoint: $canary_endpoint"
    log "Stable endpoint: $stable_endpoint"
    
    # Validation steps
    local validation_passed=true
    
    # 1. Basic health check
    log "Step 1: Basic health check"
    local health_result=$(health_check "$canary_endpoint/health")
    if [[ "$health_result" =~ ^success: ]]; then
        log "✅ Health check passed"
    else
        error "❌ Health check failed"
        validation_passed=false
    fi
    
    # 2. Performance comparison
    log "Step 2: Performance comparison"
    if ! compare_performance "$canary_endpoint" "$stable_endpoint" 60; then
        validation_passed=false
    fi
    
    # 3. Business metrics check
    log "Step 3: Business metrics check"
    if ! check_business_metrics "$service_name"; then
        warn "Business metrics check failed, but continuing..."
        # Don't fail validation for business metrics (warning only)
    fi
    
    # 4. Error logs check
    log "Step 4: Error logs check"
    if ! check_error_logs "$service_name"; then
        validation_passed=false
    fi
    
    # 5. Extended monitoring (if validation is passing so far)
    if [[ "$validation_passed" == "true" && $VALIDATION_DURATION -gt 60 ]]; then
        log "Step 5: Extended monitoring for $((VALIDATION_DURATION - 60)) seconds"
        
        local extended_duration=$((VALIDATION_DURATION - 60))
        local check_interval=30
        local checks=$((extended_duration / check_interval))
        
        for ((i=1; i<=checks; i++)); do
            log "Extended check $i/$checks"
            
            # Quick health check
            local health_result=$(health_check "$canary_endpoint/health")
            if [[ ! "$health_result" =~ ^success: ]]; then
                error "Health check failed during extended monitoring"
                validation_passed=false
                break
            fi
            
            # Check for new errors
            local recent_errors=$(kubectl logs -l app="$service_name",version=canary -n "$NAMESPACE" --since="${check_interval}s" 2>/dev/null | grep -c "ERROR\|FATAL\|CRITICAL" || echo "0")
            if [[ $recent_errors -gt 2 ]]; then
                error "New errors detected during extended monitoring: $recent_errors"
                validation_passed=false
                break
            fi
            
            sleep $check_interval
        done
    fi
    
    # Final result
    if [[ "$validation_passed" == "true" ]]; then
        log "🎉 Canary validation PASSED for $service_name"
        
        # Send success notification
        curl -X POST "${SLACK_WEBHOOK_URL:-}" \
            -H "Content-Type: application/json" \
            -d "{
                \"text\": \"✅ Canary validation passed for $service_name in $ENVIRONMENT\",
                \"attachments\": [{
                    \"color\": \"good\",
                    \"fields\": [
                        {\"title\": \"Service\", \"value\": \"$service_name\", \"short\": true},
                        {\"title\": \"Environment\", \"value\": \"$ENVIRONMENT\", \"short\": true},
                        {\"title\": \"Duration\", \"value\": \"${VALIDATION_DURATION}s\", \"short\": true}
                    ]
                }]
            }" 2>/dev/null || true
        
        return 0
    else
        error "💥 Canary validation FAILED for $service_name"
        
        # Send failure notification
        curl -X POST "${SLACK_WEBHOOK_URL:-}" \
            -H "Content-Type: application/json" \
            -d "{
                \"text\": \"❌ Canary validation failed for $service_name in $ENVIRONMENT\",
                \"attachments\": [{
                    \"color\": \"danger\",
                    \"fields\": [
                        {\"title\": \"Service\", \"value\": \"$service_name\", \"short\": true},
                        {\"title\": \"Environment\", \"value\": \"$ENVIRONMENT\", \"short\": true},
                        {\"title\": \"Action\", \"value\": \"Automatic rollback recommended\", \"short\": false}
                    ]
                }]
            }" 2>/dev/null || true
        
        return 1
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [SERVICE_NAME]"
    echo ""
    echo "Environment variables:"
    echo "  ENVIRONMENT         - Target environment (default: prod)"
    echo "  VALIDATION_DURATION - Validation duration in seconds (default: 300)"
    echo "  SUCCESS_THRESHOLD   - Success rate threshold percentage (default: 95)"
    echo "  MAX_LATENCY_MS      - Maximum acceptable latency in ms (default: 500)"
    echo "  SLACK_WEBHOOK_URL   - Slack webhook for notifications"
    echo ""
    echo "Examples:"
    echo "  $0 api-gateway"
    echo "  ENVIRONMENT=staging $0 user-service"
    echo "  VALIDATION_DURATION=600 $0 api-gateway"
}

# Main execution
main() {
    if [[ $# -eq 0 && -z "$SERVICE" ]]; then
        show_usage
        exit 1
    fi
    
    local service_name=${1:-$SERVICE}
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is required but not installed"
        exit 1
    fi
    
    if ! command -v bc &> /dev/null; then
        error "bc is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        error "jq is required but not installed"
        exit 1
    fi
    
    # Validate canary
    if validate_canary "$service_name"; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"