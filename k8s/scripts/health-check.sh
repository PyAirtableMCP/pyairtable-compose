#!/bin/bash

# PyAirtable Health Check Script for Kubernetes
# Validates service health and connectivity

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${1:-pyairtable}"
TIMEOUT="${TIMEOUT:-30}"

echo -e "${BLUE}🏥 Starting PyAirtable Health Check${NC}"
echo -e "${BLUE}🎯 Namespace: ${NAMESPACE}${NC}"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check pod status
check_pod_status() {
    echo -e "${BLUE}🔍 Checking pod status${NC}"
    
    local unhealthy_pods=()
    local pods=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pods; do
        local status=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        local ready=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        
        if [ "$status" != "Running" ] || [ "$ready" != "True" ]; then
            unhealthy_pods+=("$pod")
        fi
    done
    
    if [ ${#unhealthy_pods[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All pods are healthy${NC}"
        return 0
    else
        echo -e "${RED}❌ Unhealthy pods found:${NC}"
        for pod in "${unhealthy_pods[@]}"; do
            echo -e "${RED}  - $pod${NC}"
            kubectl describe pod "$pod" -n "$NAMESPACE" | tail -10
        done
        return 1
    fi
}

# Function to check service endpoints
check_service_endpoints() {
    echo -e "${BLUE}🌐 Checking service endpoints${NC}"
    
    local services=$(kubectl get services -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    local failed_services=()
    
    for service in $services; do
        local endpoints=$(kubectl get endpoints "$service" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
        
        if [ -z "$endpoints" ]; then
            failed_services+=("$service")
        else
            echo -e "${GREEN}✅ $service: ${endpoints}${NC}"
        fi
    done
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All services have endpoints${NC}"
        return 0
    else
        echo -e "${RED}❌ Services without endpoints:${NC}"
        for service in "${failed_services[@]}"; do
            echo -e "${RED}  - $service${NC}"
        done
        return 1
    fi
}

# Function to check HTTP health endpoints
check_http_health() {
    echo -e "${BLUE}🏥 Checking HTTP health endpoints${NC}"
    
    # Define services and their health endpoints
    declare -A health_endpoints=(
        ["api-gateway"]="/health"
        ["platform-services"]="/health"
        ["automation-services"]="/health"
        ["llm-orchestrator"]="/health"
        ["mcp-server"]="/health"
        ["airtable-gateway"]="/health"
        ["frontend"]="/"
    )
    
    local failed_health_checks=()
    
    for service in "${!health_endpoints[@]}"; do
        local endpoint="${health_endpoints[$service]}"
        
        echo -e "${YELLOW}🔍 Checking $service health endpoint${NC}"
        
        # Port forward to the service temporarily
        kubectl port-forward -n "$NAMESPACE" "service/$service" 8080:80 >/dev/null 2>&1 &
        local pf_pid=$!
        
        # Wait a moment for port forward to establish
        sleep 2
        
        # Check health endpoint
        if command_exists curl; then
            if curl -f -s --max-time "$TIMEOUT" "http://localhost:8080$endpoint" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ $service health check passed${NC}"
            else
                failed_health_checks+=("$service")
                echo -e "${RED}❌ $service health check failed${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  curl not available, skipping HTTP health check for $service${NC}"
        fi
        
        # Clean up port forward
        kill $pf_pid 2>/dev/null || true
        sleep 1
    done
    
    if [ ${#failed_health_checks[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All HTTP health checks passed${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed HTTP health checks:${NC}"
        for service in "${failed_health_checks[@]}"; do
            echo -e "${RED}  - $service${NC}"
        done
        return 1
    fi
}

# Function to check database connectivity
check_database_connectivity() {
    echo -e "${BLUE}🗄️  Checking database connectivity${NC}"
    
    # Check PostgreSQL
    echo -e "${YELLOW}🔍 Checking PostgreSQL connectivity${NC}"
    kubectl port-forward -n "$NAMESPACE" service/postgresql-dev 5432:5432 >/dev/null 2>&1 &
    local pg_pid=$!
    sleep 2
    
    if command_exists psql; then
        if PGPASSWORD="dev-postgres-password" psql -h localhost -U postgres -d pyairtable -c "SELECT 1;" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ PostgreSQL connectivity check passed${NC}"
        else
            echo -e "${RED}❌ PostgreSQL connectivity check failed${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  psql not available, skipping PostgreSQL connectivity check${NC}"
    fi
    
    kill $pg_pid 2>/dev/null || true
    
    # Check Redis
    echo -e "${YELLOW}🔍 Checking Redis connectivity${NC}"
    kubectl port-forward -n "$NAMESPACE" service/redis-dev 6379:6379 >/dev/null 2>&1 &
    local redis_pid=$!
    sleep 2
    
    if command_exists redis-cli; then
        if redis-cli -h localhost -p 6379 -a "dev-redis-password" ping | grep -q "PONG"; then
            echo -e "${GREEN}✅ Redis connectivity check passed${NC}"
        else
            echo -e "${RED}❌ Redis connectivity check failed${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  redis-cli not available, skipping Redis connectivity check${NC}"
    fi
    
    kill $redis_pid 2>/dev/null || true
}

# Function to check resource usage
check_resource_usage() {
    echo -e "${BLUE}📊 Checking resource usage${NC}"
    
    # Check pod resource usage
    if command_exists kubectl && kubectl top pods -n "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "${YELLOW}Pod Resource Usage:${NC}"
        kubectl top pods -n "$NAMESPACE" | head -10
    else
        echo -e "${YELLOW}⚠️  Metrics server not available, skipping resource usage check${NC}"
    fi
    
    # Check node capacity
    echo -e "${YELLOW}Node Resource Capacity:${NC}"
    kubectl describe nodes | grep -A 5 "Capacity:\|Allocatable:" | head -20
}

# Function to check persistent volumes
check_persistent_volumes() {
    echo -e "${BLUE}💾 Checking persistent volumes${NC}"
    
    local pvcs=$(kubectl get pvc -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$pvcs" ]; then
        echo -e "${YELLOW}⚠️  No persistent volume claims found${NC}"
        return 0
    fi
    
    local failed_pvcs=()
    
    for pvc in $pvcs; do
        local status=$(kubectl get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        
        if [ "$status" != "Bound" ]; then
            failed_pvcs+=("$pvc")
        else
            echo -e "${GREEN}✅ PVC $pvc is bound${NC}"
        fi
    done
    
    if [ ${#failed_pvcs[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All persistent volumes are healthy${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed persistent volume claims:${NC}"
        for pvc in "${failed_pvcs[@]}"; do
            echo -e "${RED}  - $pvc${NC}"
        done
        return 1
    fi
}

# Function to run connectivity tests
run_connectivity_tests() {
    echo -e "${BLUE}🔗 Running service connectivity tests${NC}"
    
    # Create a temporary test pod
    kubectl run health-test-pod \
        --image=curlimages/curl:latest \
        --restart=Never \
        --rm -i --tty \
        --namespace="$NAMESPACE" \
        --timeout="$TIMEOUT"s \
        --command -- /bin/sh -c "
        echo 'Testing internal service connectivity...'
        
        # Test API Gateway
        if curl -f -s --max-time 10 http://api-gateway.$NAMESPACE.svc.cluster.local/health; then
            echo '✅ API Gateway connectivity: OK'
        else
            echo '❌ API Gateway connectivity: FAILED'
        fi
        
        # Test Platform Services
        if curl -f -s --max-time 10 http://platform-services.$NAMESPACE.svc.cluster.local/health; then
            echo '✅ Platform Services connectivity: OK'
        else
            echo '❌ Platform Services connectivity: FAILED'
        fi
        
        # Test Automation Services
        if curl -f -s --max-time 10 http://automation-services.$NAMESPACE.svc.cluster.local/health; then
            echo '✅ Automation Services connectivity: OK'
        else
            echo '❌ Automation Services connectivity: FAILED'
        fi
        
        # Test PostgreSQL
        if nc -z postgresql-dev.$NAMESPACE.svc.cluster.local 5432; then
            echo '✅ PostgreSQL connectivity: OK'
        else
            echo '❌ PostgreSQL connectivity: FAILED'
        fi
        
        # Test Redis
        if nc -z redis-dev.$NAMESPACE.svc.cluster.local 6379; then
            echo '✅ Redis connectivity: OK'
        else
            echo '❌ Redis connectivity: FAILED'
        fi
        " 2>/dev/null || echo -e "${RED}❌ Connectivity test pod failed${NC}"
}

# Function to generate health report
generate_health_report() {
    echo -e "${BLUE}📋 Generating health report${NC}"
    
    local report_file="/tmp/pyairtable-health-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "PyAirtable Health Report - $(date)"
        echo "========================================"
        echo ""
        echo "Namespace: $NAMESPACE"
        echo ""
        echo "Pod Status:"
        kubectl get pods -n "$NAMESPACE" -o wide
        echo ""
        echo "Service Status:"
        kubectl get services -n "$NAMESPACE" -o wide
        echo ""
        echo "Persistent Volume Claims:"
        kubectl get pvc -n "$NAMESPACE" 2>/dev/null || echo "No PVCs found"
        echo ""
        echo "Recent Events:"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20
        echo ""
        echo "Resource Usage:"
        kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "Metrics not available"
    } > "$report_file"
    
    echo -e "${GREEN}✅ Health report generated: $report_file${NC}"
}

# Main health check function
main() {
    local exit_code=0
    
    echo -e "${BLUE}Starting comprehensive health check...${NC}"
    echo ""
    
    # Check basic pod status
    if ! check_pod_status; then
        exit_code=1
    fi
    echo ""
    
    # Check service endpoints
    if ! check_service_endpoints; then
        exit_code=1
    fi
    echo ""
    
    # Check persistent volumes
    if ! check_persistent_volumes; then
        exit_code=1
    fi
    echo ""
    
    # Check resource usage
    check_resource_usage
    echo ""
    
    # Check database connectivity
    check_database_connectivity
    echo ""
    
    # Check HTTP health endpoints (optional)
    read -p "Run HTTP health endpoint checks? (may require port forwarding) (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if ! check_http_health; then
            exit_code=1
        fi
        echo ""
    fi
    
    # Run connectivity tests (optional)
    read -p "Run internal connectivity tests? (creates temporary pod) (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_connectivity_tests
        echo ""
    fi
    
    # Generate health report
    generate_health_report
    
    # Summary
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}🎉 All health checks passed!${NC}"
    else
        echo -e "${RED}❌ Some health checks failed. Please review the output above.${NC}"
        echo -e "${YELLOW}💡 Troubleshooting tips:${NC}"
        echo -e "  - Check pod logs: kubectl logs <pod-name> -n $NAMESPACE"
        echo -e "  - Describe failing pods: kubectl describe pod <pod-name> -n $NAMESPACE"
        echo -e "  - Check events: kubectl get events -n $NAMESPACE"
        echo -e "  - Verify resource limits: kubectl describe pods -n $NAMESPACE"
    fi
    
    return $exit_code
}

# Handle script arguments
case "${1:-}" in
    --help)
        echo "Usage: $0 [NAMESPACE] [OPTIONS]"
        echo "Options:"
        echo "  NAMESPACE          Target Kubernetes namespace (default: pyairtable)"
        echo "  --timeout SECONDS  Timeout for health checks (default: 30)"
        echo "  --help            Show this help message"
        exit 0
        ;;
esac

# Execute main function
main "$@"