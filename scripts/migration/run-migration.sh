#!/bin/bash
# PyAirtable Production Migration Runner
# =====================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="${SCRIPT_DIR}/migration-config.yaml"
LOG_FILE="${SCRIPT_DIR}/migration-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Migration state file
STATE_FILE="${SCRIPT_DIR}/migration_state.json"
ROLLBACK_FILE="${SCRIPT_DIR}/cutover_rollback.json"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $timestamp - $message" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $timestamp - $message" | tee -a "$LOG_FILE"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $timestamp - $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $timestamp - $message" | tee -a "$LOG_FILE"
            ;;
        "PHASE")
            echo -e "${PURPLE}[PHASE]${NC} $timestamp - $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Required tools
    local tools=("kubectl" "helm" "aws" "docker" "python3" "jq" "yq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "ERROR" "Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Required environment variables
    local required_vars=(
        "AWS_ACCOUNT_ID"
        "SOURCE_DATABASE_URL"
        "TARGET_DATABASE_URL"
        "REDIS_URL"
        "KAFKA_BROKERS"
        "HOSTED_ZONE_ID"
        "SSL_CERT_ARN"
        "AIRTABLE_TOKEN"
        "GEMINI_API_KEY"
        "API_KEY"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR" "Required environment variable not set: $var"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured"
        exit 1
    fi
    
    # Check Kubernetes access
    if ! kubectl cluster-info &> /dev/null; then
        log "ERROR" "kubectl not connected to cluster"
        exit 1
    fi
    
    # Check Python dependencies
    if ! python3 -c "import asyncio, aiohttp, asyncpg, redis, boto3, yaml" &> /dev/null; then
        log "WARNING" "Installing Python dependencies..."
        pip3 install asyncio aiohttp asyncpg redis boto3 pyyaml
    fi
    
    log "SUCCESS" "Prerequisites check completed"
}

# Function to validate configuration
validate_configuration() {
    log "INFO" "Validating migration configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR" "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Validate YAML syntax
    if ! yq eval '.' "$CONFIG_FILE" > /dev/null; then
        log "ERROR" "Invalid YAML syntax in configuration file"
        exit 1
    fi
    
    # Validate required sections
    local required_sections=("environment" "database" "services" "aws" "migration_phases")
    for section in "${required_sections[@]}"; do
        if ! yq eval ".$section" "$CONFIG_FILE" > /dev/null; then
            log "ERROR" "Missing configuration section: $section"
            exit 1
        fi
    done
    
    log "SUCCESS" "Configuration validation completed"
}

# Function to initialize migration
initialize_migration() {
    log "INFO" "Initializing migration environment..."
    
    # Create migration workspace
    mkdir -p "${SCRIPT_DIR}/workspace"
    mkdir -p "${SCRIPT_DIR}/logs"
    mkdir -p "${SCRIPT_DIR}/backups"
    
    # Initialize migration state
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" <<EOF
{
    "migration_id": "$(uuidgen)",
    "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "current_phase": "initialization",
    "completed_phases": [],
    "failed_phases": [],
    "rollback_points": {},
    "metadata": {
        "operator": "$(whoami)",
        "hostname": "$(hostname)",
        "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
    }
}
EOF
    fi
    
    # Set up AWS CLI profile
    export AWS_DEFAULT_REGION="${AWS_REGION:-eu-central-1}"
    
    # Update kubeconfig
    local cluster_name
    cluster_name=$(yq eval '.environment.cluster_name' "$CONFIG_FILE")
    aws eks update-kubeconfig --region "$AWS_DEFAULT_REGION" --name "$cluster_name"
    
    log "SUCCESS" "Migration environment initialized"
}

# Function to execute migration phase
execute_phase() {
    local phase_name="$1"
    local phase_script="$2"
    
    log "PHASE" "Starting phase: $phase_name"
    
    # Update migration state
    jq --arg phase "$phase_name" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.current_phase = $phase | .phase_started_at = $timestamp' \
       "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    # Execute phase script
    local phase_start_time=$(date +%s)
    local phase_status="FAIL"
    
    if [[ -x "$phase_script" ]]; then
        if "$phase_script"; then
            phase_status="SUCCESS"
            
            # Update completed phases
            jq --arg phase "$phase_name" \
               '.completed_phases += [$phase] | 
                .failed_phases = (.failed_phases - [$phase])' \
               "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        else
            # Update failed phases
            jq --arg phase "$phase_name" \
               '.failed_phases += [$phase]' \
               "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        fi
    else
        log "ERROR" "Phase script not found or not executable: $phase_script"
    fi
    
    local phase_end_time=$(date +%s)
    local phase_duration=$((phase_end_time - phase_start_time))
    
    # Log phase completion
    if [[ "$phase_status" == "SUCCESS" ]]; then
        log "SUCCESS" "Phase completed: $phase_name (${phase_duration}s)"
    else
        log "ERROR" "Phase failed: $phase_name (${phase_duration}s)"
        return 1
    fi
}

# Function to run database migration
run_database_migration() {
    log "INFO" "Starting database migration phase..."
    
    # Run database migration script
    if python3 "${SCRIPT_DIR}/migration-orchestrator.py" \
        --config "$CONFIG_FILE" \
        --phase database; then
        log "SUCCESS" "Database migration completed"
    else
        log "ERROR" "Database migration failed"
        return 1
    fi
}

# Function to run service deployment
run_service_deployment() {
    log "INFO" "Starting service deployment phase..."
    
    # Set build version
    export BUILD_VERSION="${BUILD_VERSION:-$(date +%Y%m%d-%H%M%S)}"
    
    # Run service deployment script
    if "${SCRIPT_DIR}/service-deployment-automation.sh" deploy; then
        log "SUCCESS" "Service deployment completed"
    else
        log "ERROR" "Service deployment failed"
        return 1
    fi
}

# Function to run production cutover
run_production_cutover() {
    log "INFO" "Starting production cutover phase..."
    
    # Run cutover script
    if "${SCRIPT_DIR}/production-cutover.sh" cutover; then
        log "SUCCESS" "Production cutover completed"
    else
        log "ERROR" "Production cutover failed"
        return 1
    fi
}

# Function to run post-migration validation
run_post_migration_validation() {
    log "INFO" "Starting post-migration validation..."
    
    # Create validation config
    local validation_config="${SCRIPT_DIR}/workspace/validation-config.yaml"
    cat > "$validation_config" <<EOF
api_base_url: "https://api.$(yq eval '.environment.domain' "$CONFIG_FILE")"
api_key: "$API_KEY"
database_url: "$TARGET_DATABASE_URL"
redis_url: "$REDIS_URL"
aws_region: "$(yq eval '.aws.region' "$CONFIG_FILE")"
cluster_name: "$(yq eval '.environment.cluster_name' "$CONFIG_FILE")"
performance_thresholds:
$(yq eval '.performance' "$CONFIG_FILE" | sed 's/^/  /')
monitoring_endpoints:
$(yq eval '.monitoring.endpoints' "$CONFIG_FILE" | sed 's/^/  /')
EOF
    
    # Run validation script
    if python3 "${SCRIPT_DIR}/post-migration-validation.py" \
        --config "$validation_config" \
        --output "${SCRIPT_DIR}/workspace/validation-report.json"; then
        log "SUCCESS" "Post-migration validation completed"
    else
        log "ERROR" "Post-migration validation failed"
        return 1
    fi
}

# Function to perform cleanup
perform_cleanup() {
    log "INFO" "Starting cleanup phase..."
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/workspace/validation-config.yaml"
    
    # Archive logs
    local archive_dir="${SCRIPT_DIR}/logs/migration-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$archive_dir"
    cp "$LOG_FILE" "$archive_dir/"
    cp "$STATE_FILE" "$archive_dir/"
    [[ -f "$ROLLBACK_FILE" ]] && cp "$ROLLBACK_FILE" "$archive_dir/"
    [[ -f "${SCRIPT_DIR}/workspace/validation-report.json" ]] && \
        cp "${SCRIPT_DIR}/workspace/validation-report.json" "$archive_dir/"
    
    # Update migration state
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.completed_at = $timestamp | .status = "completed"' \
       "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    log "SUCCESS" "Cleanup completed - logs archived to $archive_dir"
}

# Function to handle rollback
handle_rollback() {
    log "ERROR" "🔄 Initiating migration rollback..."
    
    # Run rollback procedures
    if "${SCRIPT_DIR}/production-cutover.sh" rollback; then
        log "SUCCESS" "Traffic rollback completed"
    else
        log "ERROR" "Traffic rollback failed"
    fi
    
    # Run service rollback
    if "${SCRIPT_DIR}/service-deployment-automation.sh" rollback; then
        log "SUCCESS" "Service rollback completed"
    else
        log "ERROR" "Service rollback failed"
    fi
    
    # Update migration state
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.rollback_at = $timestamp | .status = "rolled_back"' \
       "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    log "ERROR" "Migration rolled back - check logs for details"
}

# Function to send notifications
send_notifications() {
    local status="$1"
    local message="$2"
    
    # Slack notification (if webhook configured)
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -X POST -H 'Content-type:application/json' \
            --data "{\"text\":\"PyAirtable Migration $status: $message\"}" \
            "$SLACK_WEBHOOK_URL" || true
    fi
    
    # Email notification (if configured)
    if [[ -n "${EMAIL_RECIPIENTS:-}" ]]; then
        echo "$message" | mail -s "PyAirtable Migration $status" "$EMAIL_RECIPIENTS" || true
    fi
    
    log "INFO" "Notifications sent: $status"
}

# Function to show migration status
show_migration_status() {
    log "INFO" "Migration Status Report"
    echo "======================="
    
    if [[ -f "$STATE_FILE" ]]; then
        echo "Migration ID: $(jq -r '.migration_id' "$STATE_FILE")"
        echo "Started: $(jq -r '.started_at' "$STATE_FILE")"
        echo "Current Phase: $(jq -r '.current_phase' "$STATE_FILE")"
        echo "Status: $(jq -r '.status // "in_progress"' "$STATE_FILE")"
        echo ""
        echo "Completed Phases:"
        jq -r '.completed_phases[]' "$STATE_FILE" | sed 's/^/  ✅ /'
        echo ""
        echo "Failed Phases:"
        jq -r '.failed_phases[]?' "$STATE_FILE" | sed 's/^/  ❌ /' || echo "  None"
    else
        echo "No migration state found"
    fi
    
    echo ""
    echo "Current Infrastructure Status:"
    "${SCRIPT_DIR}/production-cutover.sh" status
}

# Function to run complete migration
run_complete_migration() {
    local migration_start_time=$(date +%s)
    local migration_success=true
    
    log "INFO" "🚀 Starting PyAirtable production migration"
    send_notifications "STARTED" "Production migration initiated"
    
    # Migration phases
    local phases=(
        "Database Migration:run_database_migration"
        "Service Deployment:run_service_deployment"
        "Production Cutover:run_production_cutover"
        "Post-Migration Validation:run_post_migration_validation"
        "Cleanup:perform_cleanup"
    )
    
    # Execute each phase
    for phase_info in "${phases[@]}"; do
        local phase_name="${phase_info%%:*}"
        local phase_function="${phase_info##*:}"
        
        if ! $phase_function; then
            log "ERROR" "Migration failed at phase: $phase_name"
            migration_success=false
            break
        fi
    done
    
    local migration_end_time=$(date +%s)
    local migration_duration=$((migration_end_time - migration_start_time))
    local duration_formatted=$(printf "%02d:%02d:%02d" $((migration_duration/3600)) $((migration_duration%3600/60)) $((migration_duration%60)))
    
    if [[ "$migration_success" == "true" ]]; then
        log "SUCCESS" "🎉 Migration completed successfully in $duration_formatted"
        send_notifications "COMPLETED" "Production migration completed successfully in $duration_formatted"
        return 0
    else
        log "ERROR" "❌ Migration failed after $duration_formatted"
        handle_rollback
        send_notifications "FAILED" "Production migration failed and was rolled back after $duration_formatted"
        return 1
    fi
}

# Function to show help
show_help() {
    cat <<EOF
PyAirtable Production Migration Runner

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  migrate     - Run complete production migration
  rollback    - Rollback migration to previous state
  status      - Show current migration status
  validate    - Validate migration configuration and prerequisites
  
Options:
  --dry-run   - Perform dry run without making changes
  --config    - Specify custom configuration file
  --help      - Show this help message

Environment Variables:
  AWS_ACCOUNT_ID         - AWS account ID
  SOURCE_DATABASE_URL    - Source database connection URL
  TARGET_DATABASE_URL    - Target database connection URL
  REDIS_URL             - Redis connection URL
  KAFKA_BROKERS         - Kafka broker endpoints
  HOSTED_ZONE_ID        - Route53 hosted zone ID
  SSL_CERT_ARN          - ACM SSL certificate ARN
  AIRTABLE_TOKEN        - Airtable API token
  GEMINI_API_KEY        - Google Gemini API key
  API_KEY               - Application API key
  BUILD_VERSION         - Docker image build version (optional)
  SLACK_WEBHOOK_URL     - Slack notification webhook (optional)
  EMAIL_RECIPIENTS      - Email notification recipients (optional)

Examples:
  # Run complete migration
  $0 migrate
  
  # Perform dry run
  $0 migrate --dry-run
  
  # Check migration status
  $0 status
  
  # Rollback migration
  $0 rollback
  
  # Validate configuration
  $0 validate

Migration Phases:
  1. Database Migration     - Zero-downtime database migration with replication
  2. Service Deployment     - Phased deployment of microservices
  3. Production Cutover     - Gradual traffic routing with DNS updates
  4. Post-Migration Tests   - Comprehensive validation and testing
  5. Cleanup               - Resource cleanup and documentation updates

For detailed documentation, see: PRODUCTION_MIGRATION_PLAN.md
EOF
}

# Main execution function
main() {
    local command="${1:-migrate}"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                export DRY_RUN=true
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Execute command
    case "$command" in
        "migrate")
            check_prerequisites
            validate_configuration
            initialize_migration
            run_complete_migration
            ;;
        "rollback")
            handle_rollback
            ;;
        "status")
            show_migration_status
            ;;
        "validate")
            check_prerequisites
            validate_configuration
            log "SUCCESS" "Validation completed successfully"
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Set up signal handlers for graceful shutdown
trap 'log "ERROR" "Migration interrupted by user"; handle_rollback; exit 130' INT TERM

# Execute main function
main "$@"