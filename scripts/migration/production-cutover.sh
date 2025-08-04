#!/bin/bash
# PyAirtable Production Cutover Script
# ====================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Environment variables with defaults
DOMAIN="${DOMAIN:-pyairtable.com}"
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-Z1234567890ABC}"
SSL_CERT_ARN="${SSL_CERT_ARN:-arn:aws:acm:eu-central-1:123456789012:certificate/12345678-1234-1234-1234-123456789012}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
STAGING_LB="${STAGING_LB:-pyairtable-staging-alb.eu-central-1.elb.amazonaws.com}"
PRODUCTION_LB="${PRODUCTION_LB:-pyairtable-prod-alb.eu-central-1.elb.amazonaws.com}"
ROLLBACK_FILE="${SCRIPT_DIR}/cutover_rollback.json"

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

# Function to save rollback point
save_rollback_point() {
    log_info "Saving rollback point..."
    
    # Get current DNS configuration
    local current_dns=$(aws route53 list-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" \
        --query "ResourceRecordSets[?Name=='api.${DOMAIN}.']" --output json)
    
    # Get current load balancer configuration
    local current_lb_config=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?contains(LoadBalancerName, 'staging')]" --output json)
    
    # Save rollback configuration
    cat > "$ROLLBACK_FILE" <<EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "dns_config": $current_dns,
    "lb_config": $current_lb_config,
    "staging_lb": "$STAGING_LB",
    "production_lb": "$PRODUCTION_LB"
}
EOF
    
    log_success "Rollback point saved to $ROLLBACK_FILE"
}

# Function to validate production environment
validate_production_environment() {
    log_info "Validating production environment..."
    
    local validation_errors=0
    
    # Check production load balancer
    log_info "Checking production load balancer..."
    if ! aws elbv2 describe-load-balancers --names "pyairtable-prod" &>/dev/null; then
        log_error "Production load balancer not found"
        ((validation_errors++))
    else
        local lb_state=$(aws elbv2 describe-load-balancers --names "pyairtable-prod" \
            --query 'LoadBalancers[0].State.Code' --output text)
        if [[ "$lb_state" != "active" ]]; then
            log_error "Production load balancer not active: $lb_state"
            ((validation_errors++))
        fi
    fi
    
    # Check target groups health
    log_info "Checking target group health..."
    local target_groups=$(aws elbv2 describe-target-groups \
        --query 'TargetGroups[?contains(TargetGroupName, `prod`)].TargetGroupArn' \
        --output text)
    
    for tg_arn in $target_groups; do
        local healthy_targets=$(aws elbv2 describe-target-health --target-group-arn "$tg_arn" \
            --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)')
        
        if [[ "$healthy_targets" -eq 0 ]]; then
            log_error "No healthy targets in target group: $tg_arn"
            ((validation_errors++))
        fi
    done
    
    # Check SSL certificate
    log_info "Checking SSL certificate..."
    local cert_status=$(aws acm describe-certificate --certificate-arn "$SSL_CERT_ARN" \
        --query 'Certificate.Status' --output text)
    
    if [[ "$cert_status" != "ISSUED" ]]; then
        log_error "SSL certificate not issued: $cert_status"
        ((validation_errors++))
    fi
    
    # Check DNS zone
    log_info "Checking DNS hosted zone..."
    if ! aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" &>/dev/null; then
        log_error "Hosted zone not found: $HOSTED_ZONE_ID"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "Production environment validation passed"
        return 0
    else
        log_error "Production environment validation failed with $validation_errors errors"
        return 1
    fi
}

# Function to reduce DNS TTL for faster cutover
reduce_dns_ttl() {
    log_info "Reducing DNS TTL for faster cutover..."
    
    # Get current DNS record
    local current_record=$(aws route53 list-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" \
        --query "ResourceRecordSets[?Name=='api.${DOMAIN}.' && Type=='CNAME']" --output json)
    
    if [[ $(echo "$current_record" | jq length) -eq 0 ]]; then
        log_error "DNS record not found for api.$DOMAIN"
        return 1
    fi
    
    # Extract current values
    local current_value=$(echo "$current_record" | jq -r '.[0].ResourceRecords[0].Value')
    
    # Update with low TTL
    local change_batch=$(cat <<EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "api.$DOMAIN",
            "Type": "CNAME",
            "TTL": 60,
            "ResourceRecords": [{"Value": "$current_value"}]
        }
    }]
}
EOF
)
    
    local change_id=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "$change_batch" \
        --query 'ChangeInfo.Id' --output text)
    
    # Wait for change to propagate
    log_info "Waiting for DNS TTL change to propagate..."
    aws route53 wait resource-record-sets-changed --id "$change_id"
    
    log_success "DNS TTL reduced to 60 seconds"
}

# Function to update load balancer listeners
update_load_balancer_listeners() {
    log_info "Updating load balancer listeners..."
    
    # Get production load balancer ARN
    local prod_lb_arn=$(aws elbv2 describe-load-balancers --names "pyairtable-prod" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Get listeners
    local listeners=$(aws elbv2 describe-listeners --load-balancer-arn "$prod_lb_arn" \
        --query 'Listeners[].ListenerArn' --output text)
    
    for listener_arn in $listeners; do
        # Update HTTPS listener with SSL certificate
        if aws elbv2 describe-listeners --listener-arns "$listener_arn" \
           --query 'Listeners[0].Protocol' --output text | grep -q "HTTPS"; then
            
            log_info "Updating HTTPS listener with SSL certificate..."
            aws elbv2 modify-listener --listener-arn "$listener_arn" \
                --certificates CertificateArn="$SSL_CERT_ARN"
        fi
    done
    
    log_success "Load balancer listeners updated"
}

# Function to configure load balancer health checks
configure_health_checks() {
    log_info "Configuring comprehensive health checks..."
    
    # Get all production target groups
    local target_groups=$(aws elbv2 describe-target-groups \
        --query 'TargetGroups[?contains(TargetGroupName, `prod`)].TargetGroupArn' \
        --output text)
    
    for tg_arn in $target_groups; do
        log_info "Configuring health check for target group: $tg_arn"
        
        aws elbv2 modify-target-group \
            --target-group-arn "$tg_arn" \
            --health-check-enabled \
            --health-check-path '/health/deep' \
            --health-check-protocol HTTP \
            --health-check-port traffic-port \
            --health-check-interval-seconds 10 \
            --health-check-timeout-seconds 5 \
            --healthy-threshold-count 2 \
            --unhealthy-threshold-count 3 \
            --matcher HttpCode=200
    done
    
    log_success "Health checks configured"
}

# Function to perform gradual traffic cutover
perform_gradual_cutover() {
    log_info "Starting gradual traffic cutover..."
    
    local percentages=(10 25 50 75 100)
    
    for percentage in "${percentages[@]}"; do
        log_info "Shifting $percentage% traffic to production..."
        
        # Calculate traffic weights
        local prod_weight=$percentage
        local staging_weight=$((100 - percentage))
        
        # Update Route 53 weighted routing
        shift_traffic_weighted "$prod_weight" "$staging_weight"
        
        # Wait and monitor
        log_info "Monitoring traffic shift for 2 minutes..."
        sleep 120
        
        # Check error rates and performance
        if ! validate_traffic_health "$percentage"; then
            log_error "Traffic health validation failed at $percentage%"
            log_warning "Rolling back traffic..."
            shift_traffic_weighted 0 100
            return 1
        fi
        
        log_success "$percentage% traffic shift completed successfully"
    done
    
    log_success "Gradual cutover completed - 100% traffic on production"
}

# Function to shift traffic using weighted routing
shift_traffic_weighted() {
    local prod_weight="$1"
    local staging_weight="$2"
    
    # Create change batch for weighted routing
    local change_batch=$(cat <<EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "api.$DOMAIN",
                "Type": "CNAME",
                "SetIdentifier": "production",
                "Weight": $prod_weight,
                "TTL": 60,
                "ResourceRecords": [{"Value": "$PRODUCTION_LB"}]
            }
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "api.$DOMAIN",
                "Type": "CNAME",
                "SetIdentifier": "staging",
                "Weight": $staging_weight,
                "TTL": 60,
                "ResourceRecords": [{"Value": "$STAGING_LB"}]
            }
        }
    ]
}
EOF
)
    
    # Apply DNS changes
    local change_id=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "$change_batch" \
        --query 'ChangeInfo.Id' --output text)
    
    # Wait for propagation
    aws route53 wait resource-record-sets-changed --id "$change_id"
}

# Function to validate traffic health
validate_traffic_health() {
    local traffic_percentage="$1"
    
    log_info "Validating traffic health at $traffic_percentage%..."
    
    # Check error rates through CloudWatch
    local error_rate=$(aws cloudwatch get-metric-statistics \
        --namespace "AWS/ApplicationELB" \
        --metric-name "HTTPCode_Target_5XX_Count" \
        --dimensions Name=LoadBalancer,Value="app/pyairtable-prod/$(date +%s)" \
        --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 300 \
        --statistics Sum \
        --query 'Datapoints[0].Sum' --output text 2>/dev/null || echo "0")
    
    # Check response times
    local response_time=$(aws cloudwatch get-metric-statistics \
        --namespace "AWS/ApplicationELB" \
        --metric-name "TargetResponseTime" \
        --dimensions Name=LoadBalancer,Value="app/pyairtable-prod/$(date +%s)" \
        --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 300 \
        --statistics Average \
        --query 'Datapoints[0].Average' --output text 2>/dev/null || echo "0")
    
    # Validate thresholds
    local error_threshold=10  # Max 10 errors in 5 minutes
    local response_threshold=2.0  # Max 2 seconds average response time
    
    if [[ $(echo "$error_rate > $error_threshold" | bc -l) -eq 1 ]]; then
        log_error "Error rate too high: $error_rate (threshold: $error_threshold)"
        return 1
    fi
    
    if [[ $(echo "$response_time > $response_threshold" | bc -l) -eq 1 ]]; then
        log_error "Response time too high: ${response_time}s (threshold: ${response_threshold}s)"
        return 1
    fi
    
    # Test direct API calls
    local api_test_result
    api_test_result=$(curl -s -o /dev/null -w "%{http_code}" "https://api.$DOMAIN/health" || echo "000")
    
    if [[ "$api_test_result" != "200" ]]; then
        log_error "API health check failed: HTTP $api_test_result"
        return 1
    fi
    
    log_success "Traffic health validation passed"
    return 0
}

# Function to finalize DNS cutover
finalize_dns_cutover() {
    log_info "Finalizing DNS cutover..."
    
    # Remove weighted routing and point directly to production
    local change_batch=$(cat <<EOF
{
    "Changes": [
        {
            "Action": "DELETE",
            "ResourceRecordSet": {
                "Name": "api.$DOMAIN",
                "Type": "CNAME",
                "SetIdentifier": "production",
                "Weight": 100,
                "TTL": 60,
                "ResourceRecords": [{"Value": "$PRODUCTION_LB"}]
            }
        },
        {
            "Action": "DELETE",
            "ResourceRecordSet": {
                "Name": "api.$DOMAIN",
                "Type": "CNAME",
                "SetIdentifier": "staging",
                "Weight": 0,
                "TTL": 60,
                "ResourceRecords": [{"Value": "$STAGING_LB"}]
            }
        },
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "api.$DOMAIN",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [{"Value": "$PRODUCTION_LB"}]
            }
        }
    ]
}
EOF
)
    
    # Apply final DNS changes
    local change_id=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "$change_batch" \
        --query 'ChangeInfo.Id' --output text)
    
    # Wait for propagation
    aws route53 wait resource-record-sets-changed --id "$change_id"
    
    log_success "DNS cutover finalized - api.$DOMAIN now points to production"
}

# Function to run post-cutover validation
run_post_cutover_validation() {
    log_info "Running post-cutover validation..."
    
    # Wait for DNS propagation
    log_info "Waiting for DNS propagation (2 minutes)..."
    sleep 120
    
    # Validate DNS resolution
    local resolved_ip
    resolved_ip=$(dig +short "api.$DOMAIN" | tail -n1)
    local expected_ip
    expected_ip=$(dig +short "$PRODUCTION_LB" | tail -n1)
    
    if [[ "$resolved_ip" == "$expected_ip" ]]; then
        log_success "DNS resolution validated - api.$DOMAIN resolves to production"
    else
        log_error "DNS resolution failed - Expected: $expected_ip, Got: $resolved_ip"
        return 1
    fi
    
    # Run comprehensive API tests
    log_info "Running comprehensive API tests..."
    
    # Test critical endpoints
    local endpoints=(
        "/health"
        "/api/v1/auth/validate"
        "/api/v1/users/profile"
        "/api/v1/workspaces"
        "/api/v1/airtable/bases"
    )
    
    for endpoint in "${endpoints[@]}"; do
        local response_code
        response_code=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $API_KEY" \
            "https://api.$DOMAIN$endpoint" || echo "000")
        
        if [[ "$response_code" =~ ^[23] ]]; then
            log_success "✅ $endpoint: HTTP $response_code"
        else
            log_error "❌ $endpoint: HTTP $response_code"
        fi
    done
    
    # Test WebSocket connections
    log_info "Testing WebSocket connections..."
    timeout 10 curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
        -H "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" \
        -H "Sec-WebSocket-Version: 13" \
        "wss://api.$DOMAIN/ws" &>/dev/null && \
        log_success "✅ WebSocket connection test passed" || \
        log_warning "⚠️  WebSocket connection test failed"
    
    log_success "Post-cutover validation completed"
}

# Function to rollback cutover
rollback_cutover() {
    log_error "🔄 Rolling back production cutover..."
    
    if [[ ! -f "$ROLLBACK_FILE" ]]; then
        log_error "Rollback file not found: $ROLLBACK_FILE"
        return 1
    fi
    
    # Load rollback configuration
    local rollback_config
    rollback_config=$(cat "$ROLLBACK_FILE")
    
    local original_staging_lb
    original_staging_lb=$(echo "$rollback_config" | jq -r '.staging_lb')
    
    # Immediately shift all traffic back to staging
    log_info "Shifting 100% traffic back to staging..."
    
    local change_batch=$(cat <<EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "api.$DOMAIN",
            "Type": "CNAME",
            "TTL": 60,
            "ResourceRecords": [{"Value": "$original_staging_lb"}]
        }
    }]
}
EOF
)
    
    local change_id=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "$change_batch" \
        --query 'ChangeInfo.Id' --output text)
    
    # Wait for propagation
    aws route53 wait resource-record-sets-changed --id "$change_id"
    
    # Validate rollback
    local resolved_ip
    resolved_ip=$(dig +short "api.$DOMAIN" | tail -n1)
    local staging_ip
    staging_ip=$(dig +short "$original_staging_lb" | tail -n1)
    
    if [[ "$resolved_ip" == "$staging_ip" ]]; then
        log_success "✅ Rollback successful - traffic restored to staging"
        return 0
    else
        log_error "❌ Rollback validation failed"
        return 1
    fi
}

# Function to show cutover status
show_cutover_status() {
    log_info "Production Cutover Status"
    echo "========================="
    
    # DNS status
    echo -e "\n${BLUE}DNS Configuration:${NC}"
    local current_target
    current_target=$(dig +short "api.$DOMAIN" | tail -n1)
    local prod_target
    prod_target=$(dig +short "$PRODUCTION_LB" | tail -n1)
    
    if [[ "$current_target" == "$prod_target" ]]; then
        echo -e "api.$DOMAIN → ${GREEN}Production${NC} ($current_target)"
    else
        echo -e "api.$DOMAIN → ${YELLOW}Staging${NC} ($current_target)"
    fi
    
    # Load balancer health
    echo -e "\n${BLUE}Load Balancer Health:${NC}"
    local target_groups
    target_groups=$(aws elbv2 describe-target-groups \
        --query 'TargetGroups[?contains(TargetGroupName, `prod`)].TargetGroupArn' \
        --output text)
    
    for tg_arn in $target_groups; do
        local tg_name
        tg_name=$(aws elbv2 describe-target-groups --target-group-arns "$tg_arn" \
            --query 'TargetGroups[0].TargetGroupName' --output text)
        
        local healthy_count
        healthy_count=$(aws elbv2 describe-target-health --target-group-arn "$tg_arn" \
            --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)')
        
        local total_count
        total_count=$(aws elbv2 describe-target-health --target-group-arn "$tg_arn" \
            --query 'TargetHealthDescriptions | length(@)')
        
        if [[ "$healthy_count" -eq "$total_count" ]] && [[ "$total_count" -gt 0 ]]; then
            echo -e "$tg_name: ${GREEN}✅ $healthy_count/$total_count healthy${NC}"
        else
            echo -e "$tg_name: ${RED}❌ $healthy_count/$total_count healthy${NC}"
        fi
    done
    
    # SSL certificate status
    echo -e "\n${BLUE}SSL Certificate:${NC}"
    local cert_status
    cert_status=$(aws acm describe-certificate --certificate-arn "$SSL_CERT_ARN" \
        --query 'Certificate.Status' --output text)
    
    if [[ "$cert_status" == "ISSUED" ]]; then
        echo -e "SSL Certificate: ${GREEN}✅ $cert_status${NC}"
    else
        echo -e "SSL Certificate: ${RED}❌ $cert_status${NC}"
    fi
}

# Main execution function
main() {
    local command="${1:-cutover}"
    
    case "$command" in
        "validate")
            validate_production_environment
            ;;
        "cutover")
            log_info "🚀 Starting production cutover process..."
            save_rollback_point
            validate_production_environment || exit 1
            reduce_dns_ttl
            update_load_balancer_listeners
            configure_health_checks
            perform_gradual_cutover || exit 1
            finalize_dns_cutover
            run_post_cutover_validation
            show_cutover_status
            log_success "🎉 Production cutover completed successfully!"
            ;;
        "rollback")
            rollback_cutover
            ;;
        "status")
            show_cutover_status
            ;;
        *)
            echo "Usage: $0 {validate|cutover|rollback|status}"
            echo ""
            echo "Commands:"
            echo "  validate  - Validate production environment readiness"
            echo "  cutover   - Perform complete production cutover"
            echo "  rollback  - Rollback to previous configuration"
            echo "  status    - Show current cutover status"
            echo ""
            echo "Environment Variables:"
            echo "  DOMAIN            - Domain name (default: pyairtable.com)"
            echo "  HOSTED_ZONE_ID    - Route53 hosted zone ID"
            echo "  SSL_CERT_ARN      - ACM SSL certificate ARN"
            echo "  AWS_REGION        - AWS region (default: eu-central-1)"
            echo "  STAGING_LB        - Staging load balancer DNS name"
            echo "  PRODUCTION_LB     - Production load balancer DNS name"
            echo "  API_KEY           - API key for testing"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"