#!/bin/bash

# PyAirtable Production Deployment Validation Script
# Comprehensive validation and testing for production deployment

set -euo pipefail

# Configuration
PROJECT_NAME="pyairtable"
ENVIRONMENT="production"
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eks"
NAMESPACE="pyairtable-production"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Track test results
declare -A test_results
total_tests=0
passed_tests=0
failed_tests=0

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_info "Running test: $test_name"
    total_tests=$((total_tests + 1))
    
    if $test_function; then
        test_results["$test_name"]="PASS"
        passed_tests=$((passed_tests + 1))
        log_success "Test passed: $test_name"
    else
        test_results["$test_name"]="FAIL"
        failed_tests=$((failed_tests + 1))
        log_error "Test failed: $test_name"
    fi
}

# Infrastructure validation tests
test_cluster_accessibility() {
    kubectl cluster-info &> /dev/null
}

test_nodes_ready() {
    local not_ready_nodes=$(kubectl get nodes --no-headers | grep -v " Ready " | wc -l)
    [ "$not_ready_nodes" -eq 0 ]
}

test_system_pods_running() {
    local not_running_pods=$(kubectl get pods -n kube-system --no-headers | grep -v " Running " | grep -v " Completed " | wc -l)
    [ "$not_running_pods" -eq 0 ]
}

test_application_namespace_exists() {
    kubectl get namespace "$NAMESPACE" &> /dev/null
}

# Service deployment tests
test_all_deployments_ready() {
    local deployments=("api-gateway" "llm-orchestrator" "mcp-server" "airtable-gateway" "platform-services" "automation-services" "saga-orchestrator" "frontend")
    
    for deployment in "${deployments[@]}"; do
        local ready_replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired_replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [ "$ready_replicas" != "$desired_replicas" ] || [ "$ready_replicas" = "0" ]; then
            return 1
        fi
    done
    
    return 0
}

test_all_services_exist() {
    local services=("api-gateway" "llm-orchestrator" "mcp-server" "airtable-gateway" "platform-services" "automation-services" "saga-orchestrator" "frontend")
    
    for service in "${services[@]}"; do
        if ! kubectl get service "$service" -n "$NAMESPACE" &> /dev/null; then
            return 1
        fi
    done
    
    return 0
}

test_secrets_exist() {
    local secrets=("pyairtable-api-keys" "pyairtable-database" "pyairtable-redis" "pyairtable-app-config")
    
    for secret in "${secrets[@]}"; do
        if ! kubectl get secret "$secret" -n "$NAMESPACE" &> /dev/null; then
            return 1
        fi
    done
    
    return 0
}

# Health check tests
test_service_health_endpoints() {
    local services=(
        "api-gateway:8000:/health"
        "llm-orchestrator:8003:/health"
        "mcp-server:8001:/health"
        "airtable-gateway:8002:/health"
        "platform-services:8007:/health"
        "automation-services:8006:/health"
        "saga-orchestrator:8008:/health"
        "frontend:3000:/api/health"
    )
    
    for service_info in "${services[@]}"; do
        local service_name=$(echo "$service_info" | cut -d: -f1)
        local port=$(echo "$service_info" | cut -d: -f2)
        local health_path=$(echo "$service_info" | cut -d: -f3)
        
        # Use port-forward to test health endpoint
        local port_forward_pid
        kubectl port-forward -n "$NAMESPACE" "service/$service_name" "8080:$port" &> /dev/null &
        port_forward_pid=$!
        
        sleep 2  # Wait for port-forward to establish
        
        local health_check_result=1
        if curl -f "http://localhost:8080$health_path" &> /dev/null; then
            health_check_result=0
        fi
        
        kill $port_forward_pid &> /dev/null || true
        
        if [ $health_check_result -ne 0 ]; then
            return 1
        fi
    done
    
    return 0
}

# Auto-scaling tests
test_hpa_configured() {
    local deployments=("api-gateway" "llm-orchestrator" "mcp-server" "airtable-gateway" "platform-services" "automation-services" "saga-orchestrator" "frontend")
    
    for deployment in "${deployments[@]}"; do
        if ! kubectl get hpa "${deployment}-hpa" -n "$NAMESPACE" &> /dev/null; then
            return 1
        fi
    done
    
    return 0
}

test_pdb_configured() {
    local pdbs=("api-gateway-pdb" "frontend-pdb" "llm-orchestrator-pdb" "platform-services-pdb")
    
    for pdb in "${pdbs[@]}"; do
        if ! kubectl get pdb "$pdb" -n "$NAMESPACE" &> /dev/null; then
            return 1
        fi
    done
    
    return 0
}

# Storage tests
test_persistent_volumes() {
    local pvcs=("prometheus-pvc" "grafana-pvc" "loki-pvc")
    
    for pvc in "${pvcs[@]}"; do
        local status=$(kubectl get pvc "$pvc" -n monitoring -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        if [ "$status" != "Bound" ]; then
            return 1
        fi
    done
    
    return 0
}

# Monitoring tests
test_monitoring_stack() {
    local monitoring_pods=("prometheus" "grafana" "loki")
    
    for pod in "${monitoring_pods[@]}"; do
        local ready_pods=$(kubectl get pods -n monitoring -l "app=$pod" --no-headers | grep " Running " | wc -l)
        if [ "$ready_pods" -eq 0 ]; then
            return 1
        fi
    done
    
    return 0
}

test_prometheus_targets() {
    # Port-forward to Prometheus
    kubectl port-forward -n monitoring service/prometheus 9090:9090 &> /dev/null &
    local port_forward_pid=$!
    
    sleep 3
    
    # Check if Prometheus can reach its targets
    local targets_up=$(curl -s "http://localhost:9090/api/v1/query?query=up" | jq -r '.data.result | length' 2>/dev/null || echo "0")
    
    kill $port_forward_pid &> /dev/null || true
    
    [ "$targets_up" -gt 0 ]
}

# Security tests
test_network_policies() {
    kubectl get networkpolicy -n "$NAMESPACE" &> /dev/null
}

test_security_contexts() {
    local deployments=("api-gateway" "llm-orchestrator" "mcp-server" "airtable-gateway" "platform-services" "automation-services" "saga-orchestrator" "frontend")
    
    for deployment in "${deployments[@]}"; do
        local runs_as_root=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}' 2>/dev/null || echo "false")
        if [ "$runs_as_root" != "true" ]; then
            return 1
        fi
    done
    
    return 0
}

# Performance tests
test_resource_limits() {
    local deployments=("api-gateway" "llm-orchestrator" "mcp-server" "airtable-gateway" "platform-services" "automation-services" "saga-orchestrator" "frontend")
    
    for deployment in "${deployments[@]}"; do
        local has_limits=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}' 2>/dev/null || echo "{}")
        if [ "$has_limits" = "{}" ]; then
            return 1
        fi
    done
    
    return 0
}

test_load_balancer_endpoints() {
    local ingresses=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[*].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    [ -n "$ingresses" ]
}

# Integration tests
test_service_communication() {
    # Test that API Gateway can reach other services
    local api_gateway_pod=$(kubectl get pods -n "$NAMESPACE" -l app=api-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$api_gateway_pod" ]; then
        local services=("mcp-server:8001" "llm-orchestrator:8003" "airtable-gateway:8002")
        
        for service_info in "${services[@]}"; do
            local service_name=$(echo "$service_info" | cut -d: -f1)
            local port=$(echo "$service_info" | cut -d: -f2)
            
            if ! kubectl exec -n "$NAMESPACE" "$api_gateway_pod" -- curl -f "http://$service_name:$port/health" &> /dev/null; then
                return 1
            fi
        done
    else
        return 1
    fi
    
    return 0
}

# Generate test report
generate_report() {
    log_info "Generating validation report..."
    
    echo ""
    echo "======================================"
    echo "  PYAIRTABLE DEPLOYMENT VALIDATION"
    echo "======================================"
    echo ""
    echo "Test Summary:"
    echo "  Total tests: $total_tests"
    echo "  Passed: $passed_tests"
    echo "  Failed: $failed_tests"
    echo "  Success rate: $(( (passed_tests * 100) / total_tests ))%"
    echo ""
    
    echo "Detailed Results:"
    echo "=================="
    
    for test_name in "${!test_results[@]}"; do
        local result="${test_results[$test_name]}"
        if [ "$result" = "PASS" ]; then
            echo -e "  ${GREEN}✓${NC} $test_name"
        else
            echo -e "  ${RED}✗${NC} $test_name"
        fi
    done
    
    echo ""
    
    if [ $failed_tests -eq 0 ]; then
        log_success "All validation tests passed! Deployment is healthy."
        return 0
    else
        log_error "$failed_tests tests failed. Please investigate the issues above."
        return 1
    fi
}

# Additional information
show_deployment_info() {
    echo ""
    echo "Deployment Information:"
    echo "======================"
    
    echo ""
    echo "Cluster Nodes:"
    kubectl get nodes -o wide
    
    echo ""
    echo "Application Pods:"
    kubectl get pods -n "$NAMESPACE" -o wide
    
    echo ""
    echo "Services:"
    kubectl get services -n "$NAMESPACE"
    
    echo ""
    echo "Ingresses:"
    kubectl get ingress -n "$NAMESPACE"
    
    echo ""
    echo "HPA Status:"
    kubectl get hpa -n "$NAMESPACE"
    
    echo ""
    echo "Persistent Volumes:"
    kubectl get pv
    
    echo ""
    echo "Resource Usage:"
    kubectl top nodes 2>/dev/null || echo "Metrics server not available"
    kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "Pod metrics not available"
}

# Main validation function
main() {
    log_info "Starting PyAirtable production deployment validation..."
    
    # Check if kubectl is configured
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubectl configuration."
        exit 1
    fi
    
    log_info "Connected to cluster: $(kubectl config current-context)"
    
    # Run all validation tests
    echo ""
    log_info "Running infrastructure validation tests..."
    run_test "Cluster accessibility" test_cluster_accessibility
    run_test "Nodes ready" test_nodes_ready
    run_test "System pods running" test_system_pods_running
    run_test "Application namespace exists" test_application_namespace_exists
    
    echo ""
    log_info "Running service deployment tests..."
    run_test "All deployments ready" test_all_deployments_ready
    run_test "All services exist" test_all_services_exist
    run_test "Secrets exist" test_secrets_exist
    
    echo ""
    log_info "Running health check tests..."
    run_test "Service health endpoints" test_service_health_endpoints
    
    echo ""
    log_info "Running auto-scaling tests..."
    run_test "HPA configured" test_hpa_configured
    run_test "PDB configured" test_pdb_configured
    
    echo ""
    log_info "Running storage tests..."
    run_test "Persistent volumes" test_persistent_volumes
    
    echo ""
    log_info "Running monitoring tests..."
    run_test "Monitoring stack" test_monitoring_stack
    run_test "Prometheus targets" test_prometheus_targets
    
    echo ""
    log_info "Running security tests..."
    run_test "Network policies" test_network_policies
    run_test "Security contexts" test_security_contexts
    
    echo ""
    log_info "Running performance tests..."
    run_test "Resource limits" test_resource_limits
    run_test "Load balancer endpoints" test_load_balancer_endpoints
    
    echo ""
    log_info "Running integration tests..."
    run_test "Service communication" test_service_communication
    
    # Generate and display report
    echo ""
    local exit_code=0
    if ! generate_report; then
        exit_code=1
    fi
    
    # Show additional deployment information
    show_deployment_info
    
    exit $exit_code
}

# Run main function
main "$@"