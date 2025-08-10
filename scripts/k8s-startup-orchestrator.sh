#!/bin/bash

# PyAirtable Service Startup Orchestrator
# Manages service dependencies and startup ordering for reliable deployment

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="pyairtable"
MAX_WAIT_TIME=600
CHECK_INTERVAL=5
PARALLEL_LIMIT=3

# Service dependency tree (each service lists its dependencies)
declare -A SERVICE_DEPENDENCIES=(
    ["postgres"]=""
    ["redis"]=""
    ["airtable-gateway"]="postgres redis"
    ["mcp-server"]="airtable-gateway"
    ["llm-orchestrator"]="mcp-server redis"
    ["platform-services"]="postgres redis"
    ["automation-services"]="postgres redis mcp-server platform-services"
    ["saga-orchestrator"]="postgres redis platform-services automation-services airtable-gateway"
    ["api-gateway"]="llm-orchestrator mcp-server airtable-gateway platform-services automation-services saga-orchestrator"
    ["frontend"]="api-gateway"
)

# Service startup phases (services in same phase can start in parallel)
declare -a STARTUP_PHASES=(
    "postgres redis"
    "airtable-gateway platform-services"
    "mcp-server"
    "llm-orchestrator automation-services"
    "saga-orchestrator"
    "api-gateway"
    "frontend"
)

# Health check configurations
declare -A HEALTH_CHECKS=(
    ["postgres"]="pg_isready -U postgres -d pyairtable"
    ["redis"]="redis-cli ping"
    ["airtable-gateway"]="curl -sf http://localhost:8002/health"
    ["mcp-server"]="curl -sf http://localhost:8001/health"
    ["llm-orchestrator"]="curl -sf http://localhost:8003/health"
    ["platform-services"]="curl -sf http://localhost:8007/health"
    ["automation-services"]="curl -sf http://localhost:8006/health"
    ["saga-orchestrator"]="curl -sf http://localhost:8008/health"
    ["api-gateway"]="curl -sf http://localhost:8000/health"
    ["frontend"]="curl -sf http://localhost:3000/api/health"
)

# Service readiness timeouts (in seconds)
declare -A SERVICE_TIMEOUTS=(
    ["postgres"]="120"
    ["redis"]="60"
    ["airtable-gateway"]="90"
    ["mcp-server"]="60"
    ["llm-orchestrator"]="120"
    ["platform-services"]="90"
    ["automation-services"]="90"
    ["saga-orchestrator"]="90"
    ["api-gateway"]="60"
    ["frontend"]="120"
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

# Check if service is deployed
is_service_deployed() {
    local service=$1
    kubectl get deployment "$service" -n "$NAMESPACE" &>/dev/null
}

# Check if service is ready
is_service_ready() {
    local service=$1
    
    if ! is_service_deployed "$service"; then
        return 1
    fi
    
    local ready_replicas
    ready_replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired_replicas
    desired_replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    [ "$ready_replicas" = "$desired_replicas" ] && [ "$ready_replicas" != "0" ]
}

# Check service health endpoint
check_service_health() {
    local service=$1
    local health_check="${HEALTH_CHECKS[$service]:-}"
    
    if [ -z "$health_check" ]; then
        print_warning "No health check defined for $service, assuming healthy"
        return 0
    fi
    
    # For database services, run health check directly in pod
    if [[ "$service" == "postgres" || "$service" == "redis" ]]; then
        kubectl exec deployment/"$service" -n "$NAMESPACE" -- sh -c "$health_check" &>/dev/null
        return $?
    fi
    
    # For HTTP services, use port forwarding
    local port
    case $service in
        "airtable-gateway") port="8002" ;;
        "mcp-server") port="8001" ;;
        "llm-orchestrator") port="8003" ;;
        "platform-services") port="8007" ;;
        "automation-services") port="8006" ;;
        "saga-orchestrator") port="8008" ;;
        "api-gateway") port="8000" ;;
        "frontend") port="3000" ;;
        *) return 1 ;;
    esac
    
    # Start port forward in background
    kubectl port-forward "service/$service" "$port:$port" -n "$NAMESPACE" &>/dev/null &
    local port_forward_pid=$!
    
    # Wait for port forward to be ready
    sleep 2
    
    # Run health check
    local result=1
    for i in {1..3}; do
        if eval "$health_check" &>/dev/null; then
            result=0
            break
        fi
        sleep 1
    done
    
    # Clean up port forward
    kill $port_forward_pid &>/dev/null || true
    
    return $result
}

# Wait for service to be ready
wait_for_service() {
    local service=$1
    local timeout="${SERVICE_TIMEOUTS[$service]:-60}"
    local start_time=$(date +%s)
    
    print_info "Waiting for $service to be ready (timeout: ${timeout}s)..."
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            print_error "$service failed to become ready within ${timeout}s"
            return 1
        fi
        
        if is_service_ready "$service"; then
            print_info "$service pods are ready, checking health..."
            
            if check_service_health "$service"; then
                print_success "$service is ready and healthy"
                return 0
            else
                print_warning "$service pods ready but health check failed, retrying..."
            fi
        fi
        
        sleep $CHECK_INTERVAL
    done
}

# Check all dependencies are ready
check_dependencies() {
    local service=$1
    local dependencies="${SERVICE_DEPENDENCIES[$service]}"
    
    if [ -z "$dependencies" ]; then
        return 0
    fi
    
    print_info "Checking dependencies for $service: $dependencies"
    
    for dep in $dependencies; do
        if ! is_service_ready "$dep"; then
            print_warning "Dependency $dep is not ready for $service"
            return 1
        fi
        
        if ! check_service_health "$dep"; then
            print_warning "Dependency $dep is not healthy for $service"
            return 1
        fi
    done
    
    print_success "All dependencies ready for $service"
    return 0
}

# Start service if not already running
start_service() {
    local service=$1
    
    if is_service_ready "$service"; then
        print_info "$service is already running"
        return 0
    fi
    
    if ! is_service_deployed "$service"; then
        print_error "$service is not deployed"
        return 1
    fi
    
    print_info "Starting $service..."
    
    # Scale up the deployment
    kubectl scale deployment "$service" --replicas=1 -n "$NAMESPACE"
    
    # Wait for service to be ready
    if wait_for_service "$service"; then
        return 0
    else
        return 1
    fi
}

# Start services in a phase (parallel execution)
start_phase() {
    local phase_services=($1)
    local phase_number=$2
    
    print_header "Phase $phase_number: Starting ${phase_services[*]}"
    
    local pids=()
    local failed_services=()
    
    # Start all services in this phase in parallel
    for service in "${phase_services[@]}"; do
        (
            # Check dependencies first
            if check_dependencies "$service"; then
                start_service "$service"
            else
                print_error "Dependencies not met for $service"
                exit 1
            fi
        ) &
        pids+=($!)
    done
    
    # Wait for all services in this phase to complete
    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local service=${phase_services[$i]}
        
        if wait $pid; then
            print_success "Phase $phase_number: $service started successfully"
        else
            print_error "Phase $phase_number: $service failed to start"
            failed_services+=("$service")
        fi
    done
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        print_error "Phase $phase_number failed. Failed services: ${failed_services[*]}"
        return 1
    fi
    
    print_success "Phase $phase_number completed successfully"
    return 0
}

# Perform pre-startup checks
pre_startup_checks() {
    print_header "Pre-Startup Checks"
    
    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    # Check namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_error "Namespace $NAMESPACE does not exist"
        return 1
    fi
    
    # Check that all required deployments exist
    local missing_deployments=()
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        if ! is_service_deployed "$service"; then
            missing_deployments+=("$service")
        fi
    done
    
    if [ ${#missing_deployments[@]} -gt 0 ]; then
        print_error "Missing deployments: ${missing_deployments[*]}"
        print_info "Deploy services first with: helm install or kubectl apply"
        return 1
    fi
    
    print_success "Pre-startup checks passed"
    return 0
}

# Perform post-startup validation
post_startup_validation() {
    print_header "Post-Startup Validation"
    
    local failed_services=()
    
    # Check all services are ready and healthy
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        if is_service_ready "$service" && check_service_health "$service"; then
            print_success "$service is running and healthy"
        else
            print_error "$service is not ready or healthy"
            failed_services+=("$service")
        fi
    done
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        print_error "Validation failed for services: ${failed_services[*]}"
        return 1
    fi
    
    print_success "All services are ready and healthy"
    return 0
}

# Generate startup report
generate_startup_report() {
    local start_time=$1
    local success=$2
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_header "Startup Report"
    
    echo "Start Time: $(date -d @$start_time 2>/dev/null || date -r $start_time)"
    echo "End Time: $(date -d @$end_time 2>/dev/null || date -r $end_time)"
    echo "Duration: ${duration} seconds"
    echo "Result: $([ $success -eq 0 ] && echo "SUCCESS" || echo "FAILED")"
    echo ""
    
    # Service status summary
    echo "Service Status Summary:"
    echo "======================"
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        local status="❌ FAILED"
        if is_service_ready "$service"; then
            if check_service_health "$service"; then
                status="✅ HEALTHY"
            else
                status="⚠️  RUNNING (UNHEALTHY)"
            fi
        fi
        echo "$service: $status"
    done
    
    echo ""
    if [ $success -eq 0 ]; then
        echo "🎉 Startup completed successfully!"
        echo ""
        echo "Next steps:"
        echo "1. Access the frontend: kubectl port-forward service/frontend 3000:3000 -n $NAMESPACE"
        echo "2. Access the API: kubectl port-forward service/api-gateway 8000:8000 -n $NAMESPACE"
        echo "3. Monitor services: kubectl get pods -n $NAMESPACE"
    else
        echo "❌ Startup failed. Check the errors above and troubleshoot."
        echo ""
        echo "Troubleshooting commands:"
        echo "kubectl get pods -n $NAMESPACE"
        echo "kubectl describe pod <pod-name> -n $NAMESPACE"
        echo "kubectl logs <pod-name> -n $NAMESPACE"
    fi
}

# Emergency shutdown function
emergency_shutdown() {
    print_header "Emergency Shutdown"
    print_warning "Shutting down all services due to startup failure..."
    
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        kubectl scale deployment "$service" --replicas=0 -n "$NAMESPACE" &>/dev/null || true
    done
    
    print_info "All services scaled down"
}

# Main startup orchestration
main() {
    local start_time=$(date +%s)
    local success=0
    
    print_header "PyAirtable Service Startup Orchestrator"
    
    # Parse command line arguments
    local force_restart=false
    local emergency_stop=false
    local validate_only=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force-restart)
                force_restart=true
                shift
                ;;
            --emergency-stop)
                emergency_stop=true
                shift
                ;;
            --validate-only)
                validate_only=true
                shift
                ;;
            --namespace|-n)
                NAMESPACE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force-restart    Restart all services regardless of current state"
                echo "  --emergency-stop   Stop all services immediately"
                echo "  --validate-only    Only validate current deployment"
                echo "  --namespace, -n    Target namespace (default: pyairtable)"
                echo "  --help, -h         Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    # Handle special modes
    if [ "$emergency_stop" = true ]; then
        emergency_shutdown
        exit 0
    fi
    
    if [ "$validate_only" = true ]; then
        if post_startup_validation; then
            exit 0
        else
            exit 1
        fi
    fi
    
    # Force restart if requested
    if [ "$force_restart" = true ]; then
        print_info "Force restart requested, scaling down all services..."
        for service in "${!SERVICE_DEPENDENCIES[@]}"; do
            kubectl scale deployment "$service" --replicas=0 -n "$NAMESPACE" &>/dev/null || true
        done
        print_info "Waiting for services to scale down..."
        sleep 10
    fi
    
    # Pre-startup checks
    if ! pre_startup_checks; then
        success=1
        generate_startup_report $start_time $success
        exit $success
    fi
    
    # Execute startup phases
    local phase_number=1
    for phase in "${STARTUP_PHASES[@]}"; do
        if ! start_phase "$phase" $phase_number; then
            success=1
            emergency_shutdown
            break
        fi
        ((phase_number++))
        
        # Brief pause between phases
        sleep 5
    done
    
    # Post-startup validation
    if [ $success -eq 0 ]; then
        if ! post_startup_validation; then
            success=1
        fi
    fi
    
    # Generate report
    generate_startup_report $start_time $success
    
    exit $success
}

# Signal handlers
trap 'print_error "Interrupted by user"; emergency_shutdown; exit 130' INT TERM

# Execute main function
main "$@"