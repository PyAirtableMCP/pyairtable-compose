#!/bin/bash
# Validate PyAirtable Istio Service Mesh Deployment
# Comprehensive validation and testing script

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-pyairtable}"
ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNINGS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((TESTS_WARNINGS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to test Istio installation
test_istio_installation() {
    log_info "Testing Istio installation..."
    
    # Check if istioctl is available
    if command_exists istioctl; then
        log_success "istioctl command is available"
    else
        log_error "istioctl command not found"
        return 1
    fi
    
    # Check Istio namespace
    if kubectl get namespace "$ISTIO_NAMESPACE" &>/dev/null; then
        log_success "Istio namespace '$ISTIO_NAMESPACE' exists"
    else
        log_error "Istio namespace '$ISTIO_NAMESPACE' not found"
        return 1
    fi
    
    # Check Istio control plane
    local istiod_status
    istiod_status=$(kubectl get deployment istiod -n "$ISTIO_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [[ "$istiod_status" -gt 0 ]]; then
        log_success "Istiod control plane is running ($istiod_status replicas)"
    else
        log_error "Istiod control plane is not running"
        return 1
    fi
    
    # Check ingress gateway
    local gateway_status
    gateway_status=$(kubectl get deployment istio-ingressgateway -n "$ISTIO_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [[ "$gateway_status" -gt 0 ]]; then
        log_success "Istio ingress gateway is running ($gateway_status replicas)"
    else
        log_warning "Istio ingress gateway is not running"
    fi
}

# Function to test namespace configuration
test_namespace_configuration() {
    log_info "Testing namespace configuration..."
    
    # Check if namespace exists
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_success "PyAirtable namespace '$NAMESPACE' exists"
    else
        log_error "PyAirtable namespace '$NAMESPACE' not found"
        return 1
    fi
    
    # Check sidecar injection
    local injection_label
    injection_label=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || echo "")
    
    if [[ "$injection_label" == "enabled" ]]; then
        log_success "Sidecar injection is enabled for namespace '$NAMESPACE'"
    else
        log_error "Sidecar injection is not enabled for namespace '$NAMESPACE'"
    fi
    
    # Check service accounts
    local sa_count
    sa_count=$(kubectl get serviceaccounts -n "$NAMESPACE" --no-headers | wc -l)
    
    if [[ $sa_count -gt 0 ]]; then
        log_success "$sa_count service accounts found in namespace"
    else
        log_warning "No service accounts found in namespace"
    fi
}

# Function to test security configuration
test_security_configuration() {
    log_info "Testing security configuration..."
    
    # Check PeerAuthentication
    local pa_count
    pa_count=$(kubectl get peerauthentications -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [[ $pa_count -gt 0 ]]; then
        log_success "$pa_count PeerAuthentication policies found"
        
        # Check for strict mTLS
        if kubectl get peerauthentications -n "$NAMESPACE" -o yaml | grep -q "mode: STRICT"; then
            log_success "Strict mTLS is configured"
        else
            log_warning "Strict mTLS may not be configured"
        fi
    else
        log_error "No PeerAuthentication policies found"
    fi
    
    # Check AuthorizationPolicies
    local ap_count
    ap_count=$(kubectl get authorizationpolicies -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [[ $ap_count -gt 0 ]]; then
        log_success "$ap_count AuthorizationPolicy policies found"
    else
        log_error "No AuthorizationPolicy policies found"
    fi
    
    # Check RequestAuthentication
    local ra_count
    ra_count=$(kubectl get requestauthentications -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [[ $ra_count -gt 0 ]]; then
        log_success "$ra_count RequestAuthentication policies found"
    else
        log_warning "No RequestAuthentication policies found"
    fi
}

# Function to test traffic management
test_traffic_management() {
    log_info "Testing traffic management configuration..."
    
    # Check Gateways
    local gw_count
    gw_count=$(kubectl get gateways -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [[ $gw_count -gt 0 ]]; then
        log_success "$gw_count Gateways found"
    else
        log_error "No Gateways found"
    fi
    
    # Check VirtualServices
    local vs_count
    vs_count=$(kubectl get virtualservices -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [[ $vs_count -gt 0 ]]; then
        log_success "$vs_count VirtualServices found"
    else
        log_error "No VirtualServices found"
    fi
    
    # Check DestinationRules
    local dr_count
    dr_count=$(kubectl get destinationrules -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [[ $dr_count -gt 0 ]]; then
        log_success "$dr_count DestinationRules found"
    else
        log_error "No DestinationRules found"
    fi
    
    # Check ServiceEntries
    local se_count
    se_count=$(kubectl get serviceentries -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [[ $se_count -gt 0 ]]; then
        log_success "$se_count ServiceEntries found"
    else
        log_warning "No ServiceEntries found"
    fi
}

# Function to test workload sidecars
test_workload_sidecars() {
    log_info "Testing workload sidecar injection..."
    
    # Get all pods in namespace
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")
    
    if [[ -z "$pods" ]]; then
        log_warning "No pods found in namespace '$NAMESPACE'"
        return 0
    fi
    
    local pod_count=0
    local sidecar_count=0
    
    while IFS= read -r pod; do
        [[ -z "$pod" ]] && continue
        ((pod_count++))
        
        # Check if pod has istio-proxy container
        if kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}' | grep -q "istio-proxy"; then
            log_success "Pod '$pod' has Istio sidecar"
            ((sidecar_count++))
        else
            log_warning "Pod '$pod' missing Istio sidecar"
        fi
    done <<< "$pods"
    
    if [[ $sidecar_count -eq $pod_count ]] && [[ $pod_count -gt 0 ]]; then
        log_success "All $pod_count pods have Istio sidecars"
    elif [[ $sidecar_count -gt 0 ]]; then
        log_warning "$sidecar_count/$pod_count pods have Istio sidecars"
    else
        log_error "No pods have Istio sidecars"
    fi
}

# Function to test mTLS connectivity
test_mtls_connectivity() {
    log_info "Testing mTLS connectivity..."
    
    if ! command_exists istioctl; then
        log_warning "istioctl not available, skipping mTLS tests"
        return 0
    fi
    
    # Check proxy status
    if istioctl proxy-status -n "$NAMESPACE" &>/dev/null; then
        log_success "Proxy status check passed"
    else
        log_error "Proxy status check failed"
    fi
    
    # Test mTLS configuration
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -l app --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -3)
    
    while IFS= read -r pod; do
        [[ -z "$pod" ]] && continue
        
        if istioctl authn tls-check "$pod" -n "$NAMESPACE" 2>/dev/null | grep -q "STRICT\|OK"; then
            log_success "mTLS check passed for pod '$pod'"
        else
            log_warning "mTLS check failed for pod '$pod'"
        fi
    done <<< "$pods"
}

# Function to test observability
test_observability() {
    log_info "Testing observability configuration..."
    
    # Check Telemetry resources
    local telemetry_count
    telemetry_count=$(kubectl get telemetry -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [[ $telemetry_count -gt 0 ]]; then
        log_success "$telemetry_count Telemetry configurations found"
    else
        log_warning "No Telemetry configurations found"
    fi
    
    # Check EnvoyFilters
    local ef_count
    ef_count=$(kubectl get envoyfilters -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [[ $ef_count -gt 0 ]]; then
        log_success "$ef_count EnvoyFilters found"
    else
        log_warning "No EnvoyFilters found"
    fi
    
    # Check WasmPlugins
    local wp_count
    wp_count=$(kubectl get wasmplugins -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [[ $wp_count -gt 0 ]]; then
        log_success "$wp_count WasmPlugins found"
    else
        log_warning "No WasmPlugins found"
    fi
    
    # Check ServiceMonitors (if Prometheus Operator is installed)
    if kubectl get crd servicemonitors.monitoring.coreos.com &>/dev/null; then
        local sm_count
        sm_count=$(kubectl get servicemonitors -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
        
        if [[ $sm_count -gt 0 ]]; then
            log_success "$sm_count ServiceMonitors found"
        else
            log_warning "No ServiceMonitors found"
        fi
    fi
}

# Function to test configuration analysis
test_configuration_analysis() {
    log_info "Running Istio configuration analysis..."
    
    if ! command_exists istioctl; then
        log_warning "istioctl not available, skipping analysis"
        return 0
    fi
    
    local analysis_output
    analysis_output=$(istioctl analyze -n "$NAMESPACE" --color=false 2>&1 || true)
    
    if echo "$analysis_output" | grep -q "No validation issues found"; then
        log_success "Configuration analysis passed - no issues found"
    elif echo "$analysis_output" | grep -q "Error"; then
        log_error "Configuration analysis found errors:"
        echo "$analysis_output" | grep "Error" | head -5
    elif echo "$analysis_output" | grep -q "Warning"; then
        log_warning "Configuration analysis found warnings:"
        echo "$analysis_output" | grep "Warning" | head -5
    else
        log_success "Configuration analysis completed"
    fi
}

# Function to test external connectivity
test_external_connectivity() {
    log_info "Testing external connectivity..."
    
    # Check if ingress gateway is accessible
    local gateway_ip
    gateway_ip=$(kubectl get service istio-ingressgateway -n "$ISTIO_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -n "$gateway_ip" ]]; then
        log_success "Ingress gateway has external IP: $gateway_ip"
        
        # Test connectivity (if curl is available)
        if command_exists curl; then
            if curl -s --max-time 10 "http://$gateway_ip/health" &>/dev/null; then
                log_success "External connectivity test passed"
            else
                log_warning "External connectivity test failed (service may not be ready)"
            fi
        fi
    else
        log_warning "Ingress gateway has no external IP (LoadBalancer pending or using NodePort/ClusterIP)"
        
        # Check if it's a NodePort service
        local node_port
        node_port=$(kubectl get service istio-ingressgateway -n "$ISTIO_NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null || echo "")
        
        if [[ -n "$node_port" ]]; then
            log_success "Ingress gateway available on NodePort: $node_port"
        fi
    fi
}

# Function to test service mesh performance
test_performance_metrics() {
    log_info "Testing performance and metrics..."
    
    # Check if Prometheus is accessible
    if kubectl get service prometheus -n "$NAMESPACE" &>/dev/null || kubectl get service prometheus -n monitoring &>/dev/null || kubectl get service prometheus -n "$ISTIO_NAMESPACE" &>/dev/null; then
        log_success "Prometheus service found"
    else
        log_warning "Prometheus service not found"
    fi
    
    # Check proxy resource usage
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -3)
    
    while IFS= read -r pod; do
        [[ -z "$pod" ]] && continue
        
        if kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[?(@.name=="istio-proxy")].resources}' | grep -q "limits\|requests"; then
            log_success "Pod '$pod' has istio-proxy resource limits configured"
        else
            log_warning "Pod '$pod' istio-proxy has no resource limits"
        fi
    done <<< "$pods"
}

# Function to run comprehensive tests
run_all_tests() {
    log_info "Starting comprehensive Istio mesh validation..."
    echo "=================================================="
    
    test_istio_installation
    test_namespace_configuration
    test_security_configuration
    test_traffic_management
    test_workload_sidecars
    test_mtls_connectivity
    test_observability
    test_configuration_analysis
    test_external_connectivity
    test_performance_metrics
    
    echo ""
    echo "=================================================="
    log_info "Validation Summary:"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "Warnings: $TESTS_WARNINGS"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "🎉 All critical tests passed! Your Istio mesh is properly configured."
        if [[ $TESTS_WARNINGS -gt 0 ]]; then
            log_warning "⚠️  Some warnings were found. Review them for optimal configuration."
        fi
    else
        log_error "❌ $TESTS_FAILED critical tests failed. Review the errors above."
        exit 1
    fi
}

# Function to run quick health check
quick_health_check() {
    log_info "Running quick health check..."
    
    # Basic Istio check
    if kubectl get deployment istiod -n "$ISTIO_NAMESPACE" &>/dev/null; then
        log_success "Istio control plane is installed"
    else
        log_error "Istio control plane not found"
        exit 1
    fi
    
    # Basic namespace check
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_success "PyAirtable namespace exists"
    else
        log_error "PyAirtable namespace not found"
        exit 1
    fi
    
    # Quick proxy status
    if command_exists istioctl && istioctl proxy-status &>/dev/null; then
        log_success "Proxy status is healthy"
    else
        log_warning "Unable to verify proxy status"
    fi
    
    log_success "Quick health check completed"
}

# Main function
main() {
    case "${1:-all}" in
        "quick")
            quick_health_check
            ;;
        "security")
            test_security_configuration
            ;;
        "traffic")
            test_traffic_management
            ;;
        "observability")
            test_observability
            ;;
        "connectivity")
            test_external_connectivity
            ;;
        "all"|*)
            run_all_tests
            ;;
    esac
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi