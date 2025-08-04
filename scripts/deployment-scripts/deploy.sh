#!/bin/bash

# PyAirtable Deployment Script
# Unified deployment script for all environments and strategies

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT=""
SERVICE=""
STRATEGY="rolling"
VERSION=""
DRY_RUN=false
VERBOSE=false
FORCE=false
ROLLBACK=false

# Logging functions
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
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $1${NC}"
    fi
}

# Help function
show_help() {
    cat << EOF
PyAirtable Deployment Script

Usage: $0 [OPTIONS]

Options:
    -e, --environment ENVIRONMENT   Target environment (dev, staging, prod)
    -s, --service SERVICE          Service to deploy (optional - deploys all if empty)
    -t, --strategy STRATEGY        Deployment strategy (rolling, blue-green, canary)
    -v, --version VERSION          Version/tag to deploy
    -d, --dry-run                  Show what would be deployed without executing
    -r, --rollback                 Rollback to previous version
    -f, --force                    Force deployment without confirmation
    --verbose                      Enable verbose output
    -h, --help                     Show this help message

Examples:
    $0 -e dev -s api-gateway -v v1.2.3
    $0 -e prod -t blue-green --verbose
    $0 -e staging --rollback
    $0 -e dev --dry-run

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -s|--service)
                SERVICE="$2"
                shift 2
                ;;
            -t|--strategy)
                STRATEGY="$2"
                shift 2
                ;;
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--rollback)
                ROLLBACK=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Validate arguments
validate_args() {
    if [[ -z "$ENVIRONMENT" ]]; then
        error "Environment is required. Use -e or --environment"
        exit 1
    fi

    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        error "Environment must be one of: dev, staging, prod"
        exit 1
    fi

    if [[ ! "$STRATEGY" =~ ^(rolling|blue-green|canary)$ ]]; then
        error "Strategy must be one of: rolling, blue-green, canary"
        exit 1
    fi

    # Production requires explicit strategy
    if [[ "$ENVIRONMENT" == "prod" && "$STRATEGY" == "rolling" && "$FORCE" != "true" ]]; then
        error "Production deployments require explicit strategy (blue-green or canary)"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    debug "Checking prerequisites..."

    # Check required tools
    local tools=("kubectl" "helm" "argocd" "aws" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed"
            exit 1
        fi
    done

    # Check kubectl context
    local current_context=$(kubectl config current-context)
    local expected_context="pyairtable-${ENVIRONMENT}"
    
    if [[ "$current_context" != "$expected_context" ]]; then
        warn "Current kubectl context is '$current_context', expected '$expected_context'"
        if [[ "$FORCE" != "true" ]]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Check ArgoCD connectivity
    if ! argocd version --client &> /dev/null; then
        error "Cannot connect to ArgoCD"
        exit 1
    fi

    log "Prerequisites check passed"
}

# Get current deployment info
get_current_deployment() {
    debug "Getting current deployment information..."

    local namespace="pyairtable-${ENVIRONMENT}"
    
    if [[ -n "$SERVICE" ]]; then
        # Single service deployment info
        local deployment=$(kubectl get deployment "$SERVICE" -n "$namespace" -o json 2>/dev/null || echo "{}")
        if [[ "$deployment" != "{}" ]]; then
            local current_image=$(echo "$deployment" | jq -r '.spec.template.spec.containers[0].image // "none"')
            local current_replicas=$(echo "$deployment" | jq -r '.spec.replicas // 0')
            local ready_replicas=$(echo "$deployment" | jq -r '.status.readyReplicas // 0')
            
            log "Current deployment for $SERVICE:"
            log "  Image: $current_image"
            log "  Replicas: $ready_replicas/$current_replicas"
        else
            log "Service $SERVICE not found in $ENVIRONMENT"
        fi
    else
        # All services deployment info
        local deployments=$(kubectl get deployments -n "$namespace" -o json)
        local total_deployments=$(echo "$deployments" | jq '.items | length')
        local ready_deployments=$(echo "$deployments" | jq '[.items[] | select(.status.readyReplicas == .spec.replicas)] | length')
        
        log "Current deployment status in $ENVIRONMENT:"
        log "  Ready deployments: $ready_deployments/$total_deployments"
    fi
}

# Validate deployment target
validate_deployment() {
    debug "Validating deployment target..."

    local namespace="pyairtable-${ENVIRONMENT}"

    # Check namespace exists
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        error "Namespace $namespace does not exist"
        exit 1
    fi

    # Check ArgoCD application exists
    local argocd_app="pyairtable-${ENVIRONMENT}"
    if ! argocd app get "$argocd_app" &> /dev/null; then
        error "ArgoCD application $argocd_app does not exist"
        exit 1
    fi

    # Check if service exists (if specified)
    if [[ -n "$SERVICE" ]]; then
        if ! kubectl get deployment "$SERVICE" -n "$namespace" &> /dev/null; then
            error "Service $SERVICE does not exist in $namespace"
            exit 1
        fi
    fi

    log "Deployment target validation passed"
}

# Execute rolling deployment
deploy_rolling() {
    log "Executing rolling deployment..."

    local namespace="pyairtable-${ENVIRONMENT}"
    local argocd_app="pyairtable-${ENVIRONMENT}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would execute rolling deployment for $argocd_app"
        return 0
    fi

    # Update image tag if specified
    if [[ -n "$VERSION" && -n "$SERVICE" ]]; then
        log "Updating $SERVICE to version $VERSION"
        kubectl set image deployment/"$SERVICE" "$SERVICE"="ghcr.io/reg-kris/pyairtable-compose/$SERVICE:$VERSION" -n "$namespace"
    fi

    # Sync ArgoCD application
    log "Syncing ArgoCD application: $argocd_app"
    argocd app sync "$argocd_app" --timeout 600

    # Wait for rollout completion
    if [[ -n "$SERVICE" ]]; then
        log "Waiting for $SERVICE rollout to complete..."
        kubectl rollout status deployment/"$SERVICE" -n "$namespace" --timeout=600s
    else
        log "Waiting for all deployments to be ready..."
        kubectl wait --for=condition=Available deployment --all -n "$namespace" --timeout=600s
    fi

    log "Rolling deployment completed successfully"
}

# Execute blue-green deployment
deploy_blue_green() {
    log "Executing blue-green deployment..."

    if [[ -z "$SERVICE" ]]; then
        error "Blue-green deployment requires a specific service"
        exit 1
    fi

    local script_path="${PROJECT_ROOT}/deployment-strategies/blue-green/switch-script.sh"
    
    if [[ ! -f "$script_path" ]]; then
        error "Blue-green deployment script not found at $script_path"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would execute blue-green deployment for $SERVICE"
        return 0
    fi

    # Determine target color
    local current_color=$(kubectl get service "${SERVICE}-active" -n "pyairtable-${ENVIRONMENT}" -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "blue")
    local target_color="green"
    if [[ "$current_color" == "green" ]]; then
        target_color="blue"
    fi

    log "Current active color: $current_color"
    log "Target color: $target_color"

    # Execute blue-green deployment
    cd "$(dirname "$script_path")"
    ./switch-script.sh deploy "$target_color" "${VERSION:-latest}"
}

# Execute canary deployment
deploy_canary() {
    log "Executing canary deployment..."

    if [[ -z "$SERVICE" ]]; then
        error "Canary deployment requires a specific service"
        exit 1
    fi

    local namespace="pyairtable-${ENVIRONMENT}"
    local canary_name="${SERVICE}-canary"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would execute canary deployment for $SERVICE"
        return 0
    fi

    # Check if Flagger canary exists
    if ! kubectl get canary "$SERVICE" -n "$namespace" &> /dev/null; then
        error "Flagger canary configuration not found for $SERVICE"
        exit 1
    fi

    # Update deployment to trigger canary
    if [[ -n "$VERSION" ]]; then
        log "Updating $SERVICE to version $VERSION to trigger canary"
        kubectl set image deployment/"$SERVICE" "$SERVICE"="ghcr.io/reg-kris/pyairtable-compose/$SERVICE:$VERSION" -n "$namespace"
    else
        error "Version is required for canary deployment"
        exit 1
    fi

    # Monitor canary progress
    log "Monitoring canary deployment progress..."
    local timeout=1800  # 30 minutes
    local elapsed=0
    local interval=30

    while [[ $elapsed -lt $timeout ]]; do
        local canary_status=$(kubectl get canary "$SERVICE" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        local canary_weight=$(kubectl get canary "$SERVICE" -n "$namespace" -o jsonpath='{.status.canaryWeight}' 2>/dev/null || echo "0")
        
        log "Canary status: $canary_status, Traffic weight: $canary_weight%"
        
        case "$canary_status" in
            "Succeeded")
                log "Canary deployment completed successfully"
                return 0
                ;;
            "Failed")
                error "Canary deployment failed"
                return 1
                ;;
            "Progressing")
                log "Canary deployment in progress..."
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    error "Canary deployment timed out after $timeout seconds"
    return 1
}

# Execute rollback
execute_rollback() {
    log "Executing rollback..."

    local namespace="pyairtable-${ENVIRONMENT}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would execute rollback in $ENVIRONMENT"
        return 0
    fi

    if [[ -n "$SERVICE" ]]; then
        # Service-specific rollback
        log "Rolling back $SERVICE..."
        
        # Check deployment strategy and rollback accordingly
        if kubectl get service "${SERVICE}-active" -n "$namespace" &> /dev/null; then
            # Blue-green rollback
            local script_path="${PROJECT_ROOT}/deployment-strategies/blue-green/switch-script.sh"
            cd "$(dirname "$script_path")"
            ./switch-script.sh rollback
        elif kubectl get canary "$SERVICE" -n "$namespace" &> /dev/null; then
            # Canary rollback - pause and reset
            kubectl patch canary "$SERVICE" -n "$namespace" -p '{"spec":{"analysis":{"threshold":10000}}}'
        else
            # Standard Kubernetes rollback
            kubectl rollout undo deployment/"$SERVICE" -n "$namespace"
            kubectl rollout status deployment/"$SERVICE" -n "$namespace" --timeout=300s
        fi
    else
        # Full environment rollback using Helm
        log "Rolling back entire environment..."
        helm rollback "pyairtable-${ENVIRONMENT}" -n "$namespace"
        kubectl wait --for=condition=Available deployment --all -n "$namespace" --timeout=600s
    fi

    log "Rollback completed successfully"
}

# Health check after deployment
health_check() {
    log "Performing post-deployment health check..."

    local namespace="pyairtable-${ENVIRONMENT}"
    local health_check_url=""
    
    case "$ENVIRONMENT" in
        "dev")
            health_check_url="https://dev.pyairtable.com/health"
            ;;
        "staging")
            health_check_url="https://staging.pyairtable.com/health"
            ;;
        "prod")
            health_check_url="https://pyairtable.com/health"
            ;;
    esac

    # Check pod readiness
    log "Checking pod readiness..."
    if [[ -n "$SERVICE" ]]; then
        kubectl wait --for=condition=Ready pod -l app="$SERVICE" -n "$namespace" --timeout=300s
    else
        kubectl wait --for=condition=Ready pod --all -n "$namespace" --timeout=300s
    fi

    # Check external health endpoint
    if [[ -n "$health_check_url" ]]; then
        log "Checking external health endpoint: $health_check_url"
        local max_attempts=10
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if curl -f -s --max-time 10 "$health_check_url" > /dev/null; then
                log "Health check passed (attempt $attempt)"
                break
            else
                if [[ $attempt -eq $max_attempts ]]; then
                    error "Health check failed after $max_attempts attempts"
                    return 1
                fi
                warn "Health check failed (attempt $attempt), retrying in 10 seconds..."
                sleep 10
                ((attempt++))
            fi
        done
    fi

    # Run smoke tests
    local smoke_test_script="${PROJECT_ROOT}/scripts/smoke-test.sh"
    if [[ -f "$smoke_test_script" ]]; then
        log "Running smoke tests..."
        if ! "$smoke_test_script" "$ENVIRONMENT"; then
            error "Smoke tests failed"
            return 1
        fi
    fi

    log "Health check completed successfully"
}

# Send deployment notification
send_notification() {
    local status=$1
    local deployment_info=$2

    debug "Sending deployment notification..."

    # Slack notification (if webhook is configured)
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        local color="good"
        local emoji="✅"
        
        if [[ "$status" != "success" ]]; then
            color="danger"
            emoji="❌"
        fi

        local payload=$(cat <<EOF
{
    "text": "${emoji} Deployment ${status}",
    "attachments": [{
        "color": "${color}",
        "fields": [
            {"title": "Environment", "value": "${ENVIRONMENT}", "short": true},
            {"title": "Service", "value": "${SERVICE:-"All services"}", "short": true},
            {"title": "Strategy", "value": "${STRATEGY}", "short": true},
            {"title": "Version", "value": "${VERSION:-"latest"}", "short": true},
            {"title": "Info", "value": "${deployment_info}", "short": false}
        ],
        "footer": "PyAirtable Deployment",
        "ts": $(date +%s)
    }]
}
EOF
        )

        curl -X POST -H 'Content-type: application/json' \
            --data "$payload" \
            "$SLACK_WEBHOOK_URL" &> /dev/null || true
    fi
}

# Main deployment function
main() {
    log "Starting PyAirtable deployment..."
    
    parse_args "$@"
    validate_args
    check_prerequisites
    get_current_deployment
    validate_deployment

    # Confirmation prompt for production
    if [[ "$ENVIRONMENT" == "prod" && "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
        warn "You are about to deploy to PRODUCTION"
        echo "Environment: $ENVIRONMENT"
        echo "Service: ${SERVICE:-"All services"}"
        echo "Strategy: $STRATEGY"
        echo "Version: ${VERSION:-"latest"}"
        echo
        read -p "Are you sure you want to continue? (yes/NO): " -r
        if [[ ! "$REPLY" == "yes" ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi

    local deployment_start=$(date +%s)
    local deployment_status="success"
    local deployment_info=""

    try {
        if [[ "$ROLLBACK" == "true" ]]; then
            execute_rollback
            deployment_info="Rollback completed"
        else
            case "$STRATEGY" in
                "rolling")
                    deploy_rolling
                    ;;
                "blue-green")
                    deploy_blue_green
                    ;;
                "canary")
                    deploy_canary
                    ;;
            esac
            
            if [[ "$DRY_RUN" != "true" ]]; then
                health_check
                deployment_info="Deployment completed successfully"
            else
                deployment_info="Dry run completed"
            fi
        fi
    } catch {
        deployment_status="failed"
        deployment_info="Deployment failed: $1"
        error "$deployment_info"
    }

    local deployment_end=$(date +%s)
    local deployment_duration=$((deployment_end - deployment_start))

    # Send notification
    send_notification "$deployment_status" "$deployment_info"

    if [[ "$deployment_status" == "success" ]]; then
        log "Deployment completed successfully in ${deployment_duration}s"
        exit 0
    else
        error "Deployment failed after ${deployment_duration}s"
        exit 1
    fi
}

# Error handling functions
try() {
    "$@"
}

catch() {
    case $? in
        0) ;;  # Success
        *) "$@" "$?" ;;  # Error
    esac
}

# Run main function
main "$@"