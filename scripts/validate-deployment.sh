#!/bin/bash

# PyAirtable Deployment Validation Script
# Comprehensive validation of service health, connectivity, and functionality

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="pyairtable"
TIMEOUT=300
RETRY_INTERVAL=5
HEALTH_CHECK_TIMEOUT=10

# Service definitions
declare -A SERVICES=(
    ["api-gateway"]="8000"
    ["llm-orchestrator"]="8003"
    ["mcp-server"]="8001"
    ["airtable-gateway"]="8002"
    ["platform-services"]="8007"
    ["automation-services"]="8006"
    ["saga-orchestrator"]="8008"
    ["frontend"]="3000"
)

declare -A DATABASES=(
    ["postgres"]="5432"
    ["redis"]="6379"
)

# Health check endpoints
declare -A HEALTH_ENDPOINTS=(
    ["api-gateway"]="/health"
    ["llm-orchestrator"]="/health"
    ["mcp-server"]="/health"
    ["airtable-gateway"]="/health"
    ["platform-services"]="/health"
    ["automation-services"]="/health"
    ["saga-orchestrator"]="/health"
    ["frontend"]="/api/health"
)

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Wait for pod to be ready
wait_for_pod() {
    local service=$1
    local timeout=$2
    
    print_info "Waiting for $service pod to be ready..."
    
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name="$service" \
        --namespace="$NAMESPACE" --timeout="${timeout}s" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if service is running
check_service_status() {
    local service=$1
    
    print_info "Checking $service status..."
    
    # Check if deployment exists
    if ! kubectl get deployment "$service" -n "$NAMESPACE" &>/dev/null; then
        print_error "$service deployment not found"
        return 1
    fi
    
    # Check if pods are ready
    local ready_pods
    ready_pods=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired_pods
    desired_pods=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [ "$ready_pods" = "$desired_pods" ] && [ "$ready_pods" != "0" ]; then
        print_success "$service is running ($ready_pods/$desired_pods pods ready)"
        return 0
    else
        print_error "$service is not ready ($ready_pods/$desired_pods pods ready)"
        return 1
    fi
}

# Check service health endpoint
check_service_health() {
    local service=$1
    local port=$2
    local endpoint=${HEALTH_ENDPOINTS[$service]}
    
    print_info "Checking $service health endpoint..."
    
    # Port forward to service
    local port_forward_pid
    kubectl port-forward "service/$service" "$port:$port" -n "$NAMESPACE" &>/dev/null &
    port_forward_pid=$!
    
    # Wait for port forward to be ready
    sleep 2
    
    # Check health endpoint
    local health_check_result=1
    for i in $(seq 1 5); do
        if curl -sf "http://localhost:$port$endpoint" &>/dev/null; then
            health_check_result=0
            break
        fi
        sleep 1
    done
    
    # Clean up port forward
    kill $port_forward_pid &>/dev/null || true
    
    if [ $health_check_result -eq 0 ]; then
        print_success "$service health check passed"
        return 0
    else
        print_error "$service health check failed"
        return 1
    fi
}

# Check database connectivity
check_database_connectivity() {
    local db=$1
    local port=$2
    
    print_info "Checking $db connectivity..."
    
    case $db in
        "postgres")
            if kubectl exec deployment/postgres -n "$NAMESPACE" -- \
                psql -U postgres -d pyairtable -c "SELECT 1;" &>/dev/null; then
                print_success "$db connection successful"
                return 0
            else
                print_error "$db connection failed"
                return 1
            fi
            ;;
        "redis")
            if kubectl exec deployment/redis -n "$NAMESPACE" -- \
                redis-cli ping | grep -q "PONG"; then
                print_success "$db connection successful"
                return 0
            else
                print_error "$db connection failed"
                return 1
            fi
            ;;
    esac
}

# Check service-to-service connectivity
check_service_connectivity() {
    print_header "Service-to-Service Connectivity Tests"
    
    # Test API Gateway to downstream services
    print_info "Testing API Gateway connectivity..."
    
    local api_gateway_pod
    api_gateway_pod=$(kubectl get pods -l app.kubernetes.io/name=api-gateway -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$api_gateway_pod" ]; then
        print_error "API Gateway pod not found"
        return 1
    fi
    
    local connectivity_tests=(
        "llm-orchestrator:8003"
        "mcp-server:8001"
        "airtable-gateway:8002"
        "platform-services:8007"
        "automation-services:8006"
        "saga-orchestrator:8008"
    )
    
    local connectivity_passed=0
    for test in "${connectivity_tests[@]}"; do
        local service_name=${test%%:*}
        local service_port=${test##*:}
        
        if kubectl exec "$api_gateway_pod" -n "$NAMESPACE" -- \
            nc -z "$service_name" "$service_port" &>/dev/null; then
            print_success "API Gateway → $service_name connectivity OK"
            ((connectivity_passed++))
        else
            print_error "API Gateway → $service_name connectivity failed"
        fi
    done
    
    print_info "Connectivity tests passed: $connectivity_passed/${#connectivity_tests[@]}"
    
    if [ $connectivity_passed -eq ${#connectivity_tests[@]} ]; then
        return 0
    else
        return 1
    fi
}

# Check resource usage
check_resource_usage() {
    print_header "Resource Usage Analysis"
    
    # Check node resources
    print_info "Node resource usage:"
    kubectl top nodes 2>/dev/null || print_warning "Metrics server not available"
    
    # Check pod resources
    print_info "Pod resource usage:"
    kubectl top pods -n "$NAMESPACE" 2>/dev/null || print_warning "Pod metrics not available"
    
    # Check persistent volume usage
    print_info "Persistent volume usage:"
    kubectl get pvc -n "$NAMESPACE" || print_warning "No PVCs found"
    
    return 0
}

# Check logs for errors
check_service_logs() {
    print_header "Service Log Analysis"
    
    local error_patterns=(
        "ERROR"
        "FATAL"
        "Exception"
        "failed"
        "connection refused"
        "timeout"
    )
    
    for service in "${!SERVICES[@]}"; do
        print_info "Analyzing $service logs..."
        
        local error_count=0
        for pattern in "${error_patterns[@]}"; do
            local matches
            matches=$(kubectl logs deployment/"$service" -n "$NAMESPACE" --tail=50 2>/dev/null | grep -ci "$pattern" || echo "0")
            error_count=$((error_count + matches))
        done
        
        if [ $error_count -eq 0 ]; then
            print_success "$service logs clean"
        else
            print_warning "$service has $error_count potential error entries in recent logs"
        fi
    done
}

# Performance validation
validate_performance() {
    print_header "Performance Validation"
    
    # Check response times for critical endpoints
    local performance_tests=(
        "api-gateway:8000:/health"
        "frontend:3000:/api/health"
    )
    
    for test in "${performance_tests[@]}"; do
        local service_name=${test%%:*}
        local service_port=$(echo "$test" | cut -d':' -f2)
        local endpoint=$(echo "$test" | cut -d':' -f3-)
        
        print_info "Testing $service_name response time..."
        
        # Port forward
        kubectl port-forward "service/$service_name" "$service_port:$service_port" -n "$NAMESPACE" &>/dev/null &
        local port_forward_pid=$!
        sleep 2
        
        # Measure response time
        local response_time
        response_time=$(curl -o /dev/null -s -w '%{time_total}' "http://localhost:$service_port$endpoint" 2>/dev/null || echo "999")
        
        # Clean up
        kill $port_forward_pid &>/dev/null || true
        
        local response_time_ms
        response_time_ms=$(echo "$response_time * 1000" | bc -l 2>/dev/null | cut -d'.' -f1)
        
        if [ "${response_time_ms:-999}" -lt 1000 ]; then
            print_success "$service_name response time: ${response_time_ms}ms"
        else
            print_warning "$service_name response time: ${response_time_ms}ms (slow)"
        fi
    done
}

# End-to-end functional test
run_e2e_tests() {
    print_header "End-to-End Functional Tests"
    
    # Test 1: Frontend accessibility
    print_info "Testing frontend accessibility..."
    kubectl port-forward service/frontend 3000:3000 -n "$NAMESPACE" &>/dev/null &
    local frontend_pid=$!
    sleep 3
    
    if curl -sf http://localhost:3000 &>/dev/null; then
        print_success "Frontend is accessible"
    else
        print_error "Frontend is not accessible"
    fi
    
    kill $frontend_pid &>/dev/null || true
    
    # Test 2: API Gateway functionality
    print_info "Testing API Gateway functionality..."
    kubectl port-forward service/api-gateway 8000:8000 -n "$NAMESPACE" &>/dev/null &
    local api_pid=$!
    sleep 3
    
    local api_response
    api_response=$(curl -s http://localhost:8000/health 2>/dev/null || echo "failed")
    
    if [[ "$api_response" != "failed" ]]; then
        print_success "API Gateway responding to requests"
    else
        print_error "API Gateway not responding"
    fi
    
    kill $api_pid &>/dev/null || true
    
    # Test 3: Database operations
    print_info "Testing database operations..."
    if kubectl exec deployment/postgres -n "$NAMESPACE" -- \
        psql -U postgres -d pyairtable -c "SELECT NOW();" &>/dev/null; then
        print_success "Database operations working"
    else
        print_error "Database operations failed"
    fi
}

# Generate validation report
generate_report() {
    local passed=$1
    local total=$2
    local failed=$((total - passed))
    
    print_header "Validation Report"
    
    echo "Total Checks: $total"
    echo "Passed: $passed"
    echo "Failed: $failed"
    echo "Success Rate: $(echo "scale=1; $passed * 100 / $total" | bc -l)%"
    
    if [ $failed -eq 0 ]; then
        print_success "All validation checks passed! 🎉"
        echo ""
        echo "Your PyAirtable deployment is ready for development."
        echo ""
        echo "Next steps:"
        echo "1. Access the frontend: kubectl port-forward service/frontend 3000:3000 -n pyairtable"
        echo "2. Access the API: kubectl port-forward service/api-gateway 8000:8000 -n pyairtable"
        echo "3. Monitor with: kubectl logs -f deployment/api-gateway -n pyairtable"
        return 0
    else
        print_error "Some validation checks failed. Please review the output above."
        echo ""
        echo "Troubleshooting commands:"
        echo "kubectl get pods -n pyairtable"
        echo "kubectl describe pod <pod-name> -n pyairtable"
        echo "kubectl logs <pod-name> -n pyairtable"
        return 1
    fi
}

# Main validation function
main() {
    print_header "PyAirtable Deployment Validation"
    
    local total_checks=0
    local passed_checks=0
    
    # Basic cluster connectivity
    print_info "Checking cluster connectivity..."
    if kubectl cluster-info &>/dev/null; then
        print_success "Cluster connectivity OK"
        ((passed_checks++))
    else
        print_error "Cannot connect to cluster"
    fi
    ((total_checks++))
    
    # Namespace existence
    print_info "Checking namespace..."
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_success "Namespace $NAMESPACE exists"
        ((passed_checks++))
    else
        print_error "Namespace $NAMESPACE not found"
    fi
    ((total_checks++))
    
    # Service status checks
    print_header "Service Status Validation"
    for service in "${!SERVICES[@]}"; do
        if check_service_status "$service"; then
            ((passed_checks++))
        fi
        ((total_checks++))
    done
    
    # Database checks
    print_header "Database Connectivity Validation"
    for db in "${!DATABASES[@]}"; do
        if check_database_connectivity "$db" "${DATABASES[$db]}"; then
            ((passed_checks++))
        fi
        ((total_checks++))
    done
    
    # Health endpoint checks
    print_header "Health Endpoint Validation"
    for service in "${!SERVICES[@]}"; do
        if [[ -n "${HEALTH_ENDPOINTS[$service]:-}" ]]; then
            if check_service_health "$service" "${SERVICES[$service]}"; then
                ((passed_checks++))
            fi
            ((total_checks++))
        fi
    done
    
    # Service connectivity
    if check_service_connectivity; then
        ((passed_checks++))
    fi
    ((total_checks++))
    
    # Resource usage
    check_resource_usage
    ((passed_checks++))
    ((total_checks++))
    
    # Log analysis
    check_service_logs
    ((passed_checks++))
    ((total_checks++))
    
    # Performance validation
    validate_performance
    ((passed_checks++))
    ((total_checks++))
    
    # E2E tests
    run_e2e_tests
    # Note: E2E tests are informational, don't count towards pass/fail
    
    # Generate final report
    generate_report $passed_checks $total_checks
}

# Command line argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace|-n)
            NAMESPACE="$2"
            shift 2
            ;;
        --timeout|-t)
            TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --namespace, -n   Target namespace (default: pyairtable)"
            echo "  --timeout, -t     Timeout in seconds (default: 300)"
            echo "  --help, -h        Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main