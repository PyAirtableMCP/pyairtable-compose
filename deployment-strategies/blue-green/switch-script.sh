#!/bin/bash

# Blue-Green Deployment Switch Script
# Provides safe switching between blue and green deployments with health checks and rollback

set -euo pipefail

# Configuration
NAMESPACE="pyairtable-prod"
APP_NAME="api-gateway"
HEALTH_CHECK_PATH="/health"
HEALTH_CHECK_TIMEOUT=30
READINESS_TIMEOUT=300
ROLLBACK_ENABLED=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Function to get current active color
get_active_color() {
    kubectl get service ${APP_NAME}-active -n ${NAMESPACE} -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "unknown"
}

# Function to get inactive color
get_inactive_color() {
    local active_color=$(get_active_color)
    if [[ "$active_color" == "blue" ]]; then
        echo "green"
    elif [[ "$active_color" == "green" ]]; then
        echo "blue"
    else
        error "Unable to determine inactive color. Active color: $active_color"
        exit 1
    fi
}

# Function to check if deployment is ready
check_deployment_ready() {
    local color=$1
    local deployment_name="${APP_NAME}-${color}"
    
    log "Checking if ${deployment_name} is ready..."
    
    # Check if deployment exists and has desired replicas
    local desired_replicas=$(kubectl get deployment ${deployment_name} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    local ready_replicas=$(kubectl get deployment ${deployment_name} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [[ "$desired_replicas" -eq 0 ]]; then
        warn "Deployment ${deployment_name} has 0 desired replicas"
        return 1
    fi
    
    if [[ "$ready_replicas" -eq "$desired_replicas" ]]; then
        log "Deployment ${deployment_name} is ready (${ready_replicas}/${desired_replicas})"
        return 0
    else
        warn "Deployment ${deployment_name} is not ready (${ready_replicas}/${desired_replicas})"
        return 1
    fi
}

# Function to wait for deployment readiness
wait_for_deployment() {
    local color=$1
    local timeout=${READINESS_TIMEOUT}
    local deployment_name="${APP_NAME}-${color}"
    
    log "Waiting for ${deployment_name} to be ready (timeout: ${timeout}s)..."
    
    if kubectl wait --for=condition=available --timeout=${timeout}s deployment/${deployment_name} -n ${NAMESPACE}; then
        log "Deployment ${deployment_name} is available"
        return 0
    else
        error "Deployment ${deployment_name} failed to become available within ${timeout}s"
        return 1
    fi
}

# Function to perform health check
health_check() {
    local color=$1
    local service_name="${APP_NAME}-${color}"
    
    log "Performing health check for ${service_name}..."
    
    # Port forward to the service
    local local_port=$(shuf -i 8000-9000 -n 1)
    kubectl port-forward service/${service_name} ${local_port}:8000 -n ${NAMESPACE} &
    local port_forward_pid=$!
    
    # Wait a moment for port forward to establish
    sleep 2
    
    # Perform health check
    local health_status=1
    for i in {1..10}; do
        if curl -f -s --max-time ${HEALTH_CHECK_TIMEOUT} "http://localhost:${local_port}${HEALTH_CHECK_PATH}" > /dev/null; then
            log "Health check passed for ${service_name} (attempt $i)"
            health_status=0
            break
        else
            warn "Health check failed for ${service_name} (attempt $i)"
            sleep 3
        fi
    done
    
    # Clean up port forward
    kill ${port_forward_pid} 2>/dev/null || true
    
    return ${health_status}
}

# Function to scale deployment
scale_deployment() {
    local color=$1
    local replicas=$2
    local deployment_name="${APP_NAME}-${color}"
    
    log "Scaling ${deployment_name} to ${replicas} replicas..."
    kubectl scale deployment ${deployment_name} --replicas=${replicas} -n ${NAMESPACE}
    
    if [[ $replicas -gt 0 ]]; then
        wait_for_deployment ${color}
    fi
}

# Function to switch traffic
switch_traffic() {
    local new_color=$1
    local service_name="${APP_NAME}-active"
    
    log "Switching traffic to ${new_color}..."
    kubectl patch service ${service_name} -n ${NAMESPACE} -p '{"spec":{"selector":{"version":"'${new_color}'"}}}'
    
    # Update ConfigMap
    kubectl patch configmap blue-green-config -n ${NAMESPACE} -p '{"data":{"active_color":"'${new_color}'"}}'
    
    log "Traffic switched to ${new_color}"
}

# Function to perform smoke test
smoke_test() {
    local color=$1
    
    log "Performing smoke test for ${color} deployment..."
    
    # Get the external IP/hostname
    local external_endpoint=$(kubectl get service ${APP_NAME}-active -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                            kubectl get service ${APP_NAME}-active -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || \
                            echo "localhost")
    
    if [[ "$external_endpoint" == "localhost" ]]; then
        warn "Could not determine external endpoint, using port-forward for smoke test"
        # Port forward to the active service
        local local_port=$(shuf -i 8000-9000 -n 1)
        kubectl port-forward service/${APP_NAME}-active ${local_port}:8000 -n ${NAMESPACE} &
        local port_forward_pid=$!
        sleep 2
        external_endpoint="localhost:${local_port}"
    fi
    
    # Perform basic smoke tests
    local tests_passed=0
    local total_tests=3
    
    # Test 1: Health check
    if curl -f -s --max-time 10 "http://${external_endpoint}${HEALTH_CHECK_PATH}" > /dev/null; then
        log "✓ Health check passed"
        ((tests_passed++))
    else
        error "✗ Health check failed"
    fi
    
    # Test 2: API endpoint test
    if curl -f -s --max-time 10 "http://${external_endpoint}/api/health" > /dev/null; then
        log "✓ API endpoint test passed"
        ((tests_passed++))
    else
        warn "✗ API endpoint test failed"
    fi
    
    # Test 3: Response time test
    local response_time=$(curl -o /dev/null -s -w '%{time_total}' --max-time 10 "http://${external_endpoint}${HEALTH_CHECK_PATH}" || echo "999")
    if (( $(echo "$response_time < 1.0" | bc -l) )); then
        log "✓ Response time test passed (${response_time}s)"
        ((tests_passed++))
    else
        warn "✗ Response time test failed (${response_time}s)"
    fi
    
    # Clean up port forward if used
    [[ -n "${port_forward_pid:-}" ]] && kill ${port_forward_pid} 2>/dev/null || true
    
    if [[ $tests_passed -eq $total_tests ]]; then
        log "All smoke tests passed (${tests_passed}/${total_tests})"
        return 0
    else
        error "Some smoke tests failed (${tests_passed}/${total_tests})"
        return 1
    fi
}

# Function to rollback
rollback() {
    local current_color=$(get_active_color)
    local previous_color=$(get_inactive_color)
    
    warn "Initiating rollback from ${current_color} to ${previous_color}..."
    
    # Switch traffic back
    switch_traffic ${previous_color}
    
    # Scale down the failed deployment
    scale_deployment ${current_color} 0
    
    log "Rollback completed successfully"
}

# Function to deploy new version
deploy() {
    local target_color=$1
    local image_tag=${2:-"latest"}
    local current_color=$(get_active_color)
    
    if [[ "$target_color" == "$current_color" ]]; then
        error "Target color ($target_color) is the same as current active color ($current_color)"
        exit 1
    fi
    
    log "Starting blue-green deployment..."
    log "Current active: ${current_color}"
    log "Target color: ${target_color}"
    log "Image tag: ${image_tag}"
    
    # Step 1: Update the inactive deployment with new image
    local deployment_name="${APP_NAME}-${target_color}"
    log "Updating ${deployment_name} with image tag: ${image_tag}"
    kubectl set image deployment/${deployment_name} ${APP_NAME}=ghcr.io/reg-kris/pyairtable-compose/${APP_NAME}:${image_tag} -n ${NAMESPACE}
    
    # Step 2: Scale up the target deployment
    local current_replicas=$(kubectl get deployment ${APP_NAME}-${current_color} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}')
    scale_deployment ${target_color} ${current_replicas}
    
    # Step 3: Health check
    if ! health_check ${target_color}; then
        error "Health check failed for ${target_color} deployment"
        if [[ "$ROLLBACK_ENABLED" == "true" ]]; then
            scale_deployment ${target_color} 0
        fi
        exit 1
    fi
    
    # Step 4: Switch traffic
    switch_traffic ${target_color}
    
    # Step 5: Smoke test
    if ! smoke_test ${target_color}; then
        error "Smoke test failed for ${target_color} deployment"
        if [[ "$ROLLBACK_ENABLED" == "true" ]]; then
            rollback
        fi
        exit 1
    fi
    
    # Step 6: Scale down the previous deployment
    log "Scaling down previous deployment (${current_color})..."
    scale_deployment ${current_color} 0
    
    log "Blue-green deployment completed successfully!"
    log "New active color: ${target_color}"
}

# Function to show status
show_status() {
    local active_color=$(get_active_color)
    local inactive_color=$(get_inactive_color)
    
    echo -e "\n${BLUE}=== Blue-Green Deployment Status ===${NC}"
    echo -e "Active color: ${GREEN}${active_color}${NC}"
    echo -e "Inactive color: ${YELLOW}${inactive_color}${NC}"
    echo ""
    
    # Show deployment status
    echo -e "${BLUE}=== Deployment Status ===${NC}"
    kubectl get deployments -l app=${APP_NAME} -n ${NAMESPACE} -o wide
    echo ""
    
    # Show service status
    echo -e "${BLUE}=== Service Status ===${NC}"
    kubectl get services -l app=${APP_NAME} -n ${NAMESPACE} -o wide
    echo ""
    
    # Show pod status
    echo -e "${BLUE}=== Pod Status ===${NC}"
    kubectl get pods -l app=${APP_NAME} -n ${NAMESPACE} -o wide
}

# Main script logic
case "${1:-help}" in
    "deploy")
        if [[ $# -lt 2 ]]; then
            error "Usage: $0 deploy <color> [image_tag]"
            exit 1
        fi
        deploy "$2" "${3:-latest}"
        ;;
    "switch")
        if [[ $# -lt 2 ]]; then
            error "Usage: $0 switch <color>"
            exit 1
        fi
        switch_traffic "$2"
        ;;
    "rollback")
        rollback
        ;;
    "status")
        show_status
        ;;
    "test")
        if [[ $# -lt 2 ]]; then
            error "Usage: $0 test <color>"
            exit 1
        fi
        smoke_test "$2"
        ;;
    "scale")
        if [[ $# -lt 3 ]]; then
            error "Usage: $0 scale <color> <replicas>"
            exit 1
        fi
        scale_deployment "$2" "$3"
        ;;
    "help"|*)
        echo "Blue-Green Deployment Script"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  deploy <color> [image_tag]  - Deploy new version to specified color"
        echo "  switch <color>             - Switch traffic to specified color"
        echo "  rollback                   - Rollback to previous deployment"
        echo "  status                     - Show current deployment status"
        echo "  test <color>              - Run smoke tests for specified color"
        echo "  scale <color> <replicas>  - Scale deployment to specified replicas"
        echo "  help                      - Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 deploy green v1.2.3     # Deploy version v1.2.3 to green"
        echo "  $0 switch blue             # Switch traffic to blue deployment"
        echo "  $0 rollback                # Rollback to previous version"
        echo "  $0 status                  # Show current status"
        ;;
esac