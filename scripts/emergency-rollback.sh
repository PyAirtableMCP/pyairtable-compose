#!/bin/bash
# Emergency Rollback Script for PyAirtable Platform
# Provides rapid rollback capabilities for production incidents

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-pyairtable}"
ROLLBACK_TIMEOUT="${ROLLBACK_TIMEOUT:-300}"
INCIDENT_ID="${INCIDENT_ID:-$(date +%Y%m%d-%H%M%S)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Service definitions
SERVICES=(
    "platform-services"
    "automation-services"
    "api-gateway"
    "llm-orchestrator"
    "mcp-server"
    "airtable-gateway"
    "frontend"
)

# Emergency notification
send_emergency_notification() {
    local message="$1"
    
    # Slack notification
    if [ -n "${SLACK_EMERGENCY_WEBHOOK:-}" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{
                \"text\": \"🚨 EMERGENCY ROLLBACK\",
                \"attachments\": [{
                    \"color\": \"danger\",
                    \"title\": \"PyAirtable Emergency Rollback\",
                    \"text\": \"$message\",
                    \"fields\": [{
                        \"title\": \"Incident ID\",
                        \"value\": \"$INCIDENT_ID\",
                        \"short\": true
                    }, {
                        \"title\": \"Namespace\",
                        \"value\": \"$NAMESPACE\",
                        \"short\": true
                    }, {
                        \"title\": \"Time\",
                        \"value\": \"$(date -u)\",
                        \"short\": false
                    }]
                }]
            }" \
            "$SLACK_EMERGENCY_WEBHOOK" || true
    fi
    
    # PagerDuty incident
    if [ -n "${PAGERDUTY_INTEGRATION_KEY:-}" ]; then
        curl -X POST \
            -H "Content-Type: application/json" \
            -d "{
                \"routing_key\": \"$PAGERDUTY_INTEGRATION_KEY\",
                \"event_action\": \"trigger\",
                \"dedup_key\": \"$INCIDENT_ID\",
                \"payload\": {
                    \"summary\": \"PyAirtable Emergency Rollback: $message\",
                    \"source\": \"pyairtable-platform\",
                    \"severity\": \"critical\",
                    \"component\": \"deployment\",
                    \"group\": \"platform\",
                    \"class\": \"rollback\"
                }
            }" \
            "https://events.pagerduty.com/v2/enqueue" || true
    fi
}

# Immediate traffic switch
immediate_traffic_switch() {
    log_error "🚨 EMERGENCY: Switching traffic to previous stable version"
    
    send_emergency_notification "Emergency traffic switch initiated - switching all services to blue (previous) version"
    
    for service in "${SERVICES[@]}"; do
        log_info "Emergency traffic switch for $service..."
        
        # Switch service selector to blue (previous version)
        kubectl patch service "$service" -n "$NAMESPACE" \
            -p '{"spec":{"selector":{"version":"blue"}}}' || {
            log_error "Failed to switch traffic for $service"
            continue
        }
        
        log_success "✓ Traffic switched for $service"
    done
    
    log_success "Emergency traffic switch completed"
}

# Full deployment rollback
full_deployment_rollback() {
    local target_revision="${1:-}"
    
    log_error "🔄 EMERGENCY: Rolling back all deployments"
    
    send_emergency_notification "Full deployment rollback initiated - rolling back to revision ${target_revision:-previous}"
    
    for service in "${SERVICES[@]}"; do
        if kubectl get deployment "$service" -n "$NAMESPACE" >/dev/null 2>&1; then
            log_info "Rolling back $service deployment..."
            
            # Get current revision for logging
            current_revision=$(kubectl rollout history deployment "$service" -n "$NAMESPACE" | tail -1 | awk '{print $1}')
            log_info "Current revision for $service: $current_revision"
            
            # Perform rollback
            if [ -n "$target_revision" ]; then
                kubectl rollout undo deployment "$service" -n "$NAMESPACE" --to-revision="$target_revision"
            else
                kubectl rollout undo deployment "$service" -n "$NAMESPACE"
            fi
            
            # Wait for rollback to complete with timeout
            if kubectl rollout status deployment "$service" -n "$NAMESPACE" --timeout="${ROLLBACK_TIMEOUT}s"; then
                log_success "✓ $service rollback completed"
            else
                log_error "✗ $service rollback timed out or failed"
                
                # Force pod deletion to trigger recreation
                kubectl delete pods -l app="$service" -n "$NAMESPACE" --force --grace-period=0 || true
            fi
        else
            log_warning "Deployment $service not found, skipping..."
        fi
    done
    
    log_success "Full deployment rollback completed"
}

# Database rollback
database_rollback() {
    log_warning "🗄️ DATABASE ROLLBACK REQUESTED"
    
    read -p "Are you sure you want to rollback the database? This action cannot be undone. (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Database rollback cancelled by user"
        return 0
    fi
    
    send_emergency_notification "Database rollback initiated - THIS IS A DESTRUCTIVE OPERATION"
    
    # Get PostgreSQL pod
    postgres_pod=$(kubectl get pods -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$postgres_pod" ]; then
        log_error "PostgreSQL pod not found"
        return 1
    fi
    
    # Check for recent migration log
    log_info "Checking for recent database migrations..."
    
    rollback_sql=$(kubectl exec "$postgres_pod" -n "$NAMESPACE" -- psql -U postgres -d pyairtable -t -c \
        "SELECT rollback_sql FROM migration_log ORDER BY applied_at DESC LIMIT 1;" | tr -d ' ')
    
    if [ -n "$rollback_sql" ] && [ "$rollback_sql" != "" ]; then
        log_info "Found rollback SQL, executing..."
        kubectl exec "$postgres_pod" -n "$NAMESPACE" -- psql -U postgres -d pyairtable -c "$rollback_sql"
        log_success "Database rollback executed"
    else
        log_error "No rollback SQL found in migration log"
        return 1
    fi
}

# Verify system health after rollback
verify_rollback_health() {
    log_info "🏥 Verifying system health after rollback..."
    
    local failed_services=()
    
    for service in "${SERVICES[@]}"; do
        if kubectl get deployment "$service" -n "$NAMESPACE" >/dev/null 2>&1; then
            # Get a pod from the deployment
            pod=$(kubectl get pods -l app="$service" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')
            
            if [ -n "$pod" ]; then
                # Check health endpoint
                if kubectl exec "$pod" -n "$NAMESPACE" -- curl -f http://localhost:8007/health >/dev/null 2>&1; then
                    log_success "✓ $service health check passed"
                else
                    log_error "✗ $service health check failed"
                    failed_services+=("$service")
                fi
            else
                log_error "✗ No pods found for $service"
                failed_services+=("$service")
            fi
        fi
    done
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        log_success "All services are healthy after rollback"
        send_emergency_notification "Rollback verification successful - all services healthy"
        return 0
    else
        log_error "Failed services after rollback: ${failed_services[*]}"
        send_emergency_notification "Rollback verification failed - services still unhealthy: ${failed_services[*]}"
        return 1
    fi
}

# Get system status
get_system_status() {
    log_info "📊 Current system status:"
    
    echo "========================================="
    echo "DEPLOYMENT STATUS"
    echo "========================================="
    
    for service in "${SERVICES[@]}"; do
        if kubectl get deployment "$service" -n "$NAMESPACE" >/dev/null 2>&1; then
            replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.status.replicas}')
            ready_replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
            
            if [ "$replicas" = "$ready_replicas" ]; then
                echo "✅ $service: $ready_replicas/$replicas ready"
            else
                echo "❌ $service: $ready_replicas/$replicas ready"
            fi
        else
            echo "❓ $service: deployment not found"
        fi
    done
    
    echo ""
    echo "========================================="
    echo "POD STATUS"
    echo "========================================="
    kubectl get pods -n "$NAMESPACE" -o wide
    
    echo ""
    echo "========================================="
    echo "SERVICE STATUS"
    echo "========================================="
    kubectl get services -n "$NAMESPACE"
    
    echo ""
    echo "========================================="
    echo "RECENT EVENTS"
    echo "========================================="
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
}

# Main rollback function
main() {
    local rollback_type="${1:-traffic-switch}"
    local target_revision="${2:-}"
    local start_time=$(date +%s)
    
    log_error "🚨 EMERGENCY ROLLBACK INITIATED"
    log_info "Rollback Type: $rollback_type"
    log_info "Target Revision: ${target_revision:-previous}"
    log_info "Namespace: $NAMESPACE"
    log_info "Incident ID: $INCIDENT_ID"
    
    case "$rollback_type" in
        "traffic-switch")
            log_info "Performing emergency traffic switch only..."
            immediate_traffic_switch
            ;;
        "deployment")
            log_info "Performing full deployment rollback..."
            full_deployment_rollback "$target_revision"
            ;;
        "complete")
            log_info "Performing complete system rollback..."
            immediate_traffic_switch
            full_deployment_rollback "$target_revision"
            ;;
        "database")
            log_info "Performing database rollback..."
            database_rollback
            ;;
        "status")
            log_info "Getting current system status..."
            get_system_status
            exit 0
            ;;
        *)
            log_error "Unknown rollback type: $rollback_type"
            echo "Usage: $0 [traffic-switch|deployment|complete|database|status] [revision]"
            exit 1
            ;;
    esac
    
    # Verify health after rollback (except for status check)
    if [ "$rollback_type" != "status" ]; then
        sleep 30  # Wait for services to stabilize
        verify_rollback_health
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_success "🎯 Emergency rollback completed"
        log_success "Rollback duration: ${duration} seconds"
        
        # Generate incident report
        cat > "/tmp/emergency-rollback-report-$INCIDENT_ID.md" << EOF
# Emergency Rollback Report

**Incident ID:** $INCIDENT_ID
**Date:** $(date -u)
**Duration:** ${duration} seconds
**Rollback Type:** $rollback_type
**Target Revision:** ${target_revision:-previous}
**Namespace:** $NAMESPACE

## Actions Taken
- $([ "$rollback_type" = "traffic-switch" ] || [ "$rollback_type" = "complete" ] && echo "✅ Emergency traffic switch performed")
- $([ "$rollback_type" = "deployment" ] || [ "$rollback_type" = "complete" ] && echo "✅ Deployment rollback performed")
- $([ "$rollback_type" = "database" ] && echo "✅ Database rollback performed")
- ✅ System health verification completed

## System Status After Rollback
$(get_system_status)

## Next Steps
- [ ] Investigate root cause of the incident
- [ ] Review logs for the failed deployment
- [ ] Update monitoring and alerting if needed
- [ ] Schedule post-mortem meeting
- [ ] Update runbooks based on lessons learned

## Timeline
- **Incident Start:** $(date -u -d "${duration} seconds ago")
- **Rollback Start:** $(date -u -d "${duration} seconds ago")
- **Rollback Complete:** $(date -u)
- **Duration:** ${duration} seconds

## Contact Information
- **On-Call Engineer:** [To be filled]
- **Incident Commander:** [To be filled]
- **Business Impact:** [To be assessed]
EOF
        
        log_info "Incident report generated: /tmp/emergency-rollback-report-$INCIDENT_ID.md"
        
        send_emergency_notification "Emergency rollback completed successfully in ${duration} seconds. System status verified. Incident report: /tmp/emergency-rollback-report-$INCIDENT_ID.md"
    fi
}

# Handle script termination
cleanup() {
    log_info "Emergency rollback script terminated"
    send_emergency_notification "Emergency rollback script was terminated unexpectedly"
}

trap cleanup EXIT

# Parse command line arguments and execute
if [ $# -eq 0 ]; then
    echo "PyAirtable Emergency Rollback Script"
    echo "======================================"
    echo ""
    echo "Usage: $0 <rollback-type> [target-revision]"
    echo ""
    echo "Rollback Types:"
    echo "  traffic-switch  - Immediately switch traffic to previous version (fastest)"
    echo "  deployment      - Rollback deployments to previous revision"
    echo "  complete        - Full rollback (traffic + deployments)"
    echo "  database        - Rollback database migrations (DESTRUCTIVE)"
    echo "  status          - Show current system status"
    echo ""
    echo "Examples:"
    echo "  $0 traffic-switch              # Emergency traffic switch"
    echo "  $0 deployment                  # Rollback to previous revision"
    echo "  $0 deployment 5                # Rollback to revision 5"
    echo "  $0 complete                    # Full system rollback"
    echo "  $0 status                      # Check system status"
    echo ""
    echo "Environment Variables:"
    echo "  NAMESPACE                      # Kubernetes namespace (default: pyairtable)"
    echo "  ROLLBACK_TIMEOUT               # Rollback timeout in seconds (default: 300)"
    echo "  SLACK_EMERGENCY_WEBHOOK        # Slack webhook for emergency notifications"
    echo "  PAGERDUTY_INTEGRATION_KEY      # PagerDuty integration key"
    echo ""
    exit 1
fi

# Execute main function with arguments
main "$@"