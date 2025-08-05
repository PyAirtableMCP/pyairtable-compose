#!/bin/bash

# PyAirtable Monitoring Stack Validation Script
# Validates the complete monitoring setup and configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    local level=$1
    shift
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $*" ;;
        "SUCCESS") echo -e "${GREEN}[✓]${NC} $*" ;;
        "FAIL") echo -e "${RED}[✗]${NC} $*" ;;
    esac
}

check_file_exists() {
    local file=$1
    local description=$2
    
    if [ -f "$file" ]; then
        log "SUCCESS" "$description exists: $file"
        return 0
    else
        log "FAIL" "$description missing: $file"
        return 1
    fi
}

check_directory_exists() {
    local dir=$1
    local description=$2
    
    if [ -d "$dir" ]; then
        log "SUCCESS" "$description exists: $dir"
        return 0
    else
        log "FAIL" "$description missing: $dir"
        return 1
    fi
}

validate_yaml_syntax() {
    local file=$1
    local description=$2
    
    if [ ! -f "$file" ]; then
        log "FAIL" "$description file not found: $file"
        return 1
    fi
    
    if command -v yq &> /dev/null; then
        if yq eval '.' "$file" > /dev/null 2>&1; then
            log "SUCCESS" "$description YAML syntax is valid"
            return 0
        else
            log "FAIL" "$description YAML syntax is invalid"
            return 1
        fi
    elif python3 -c "import yaml" 2>/dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            log "SUCCESS" "$description YAML syntax is valid"
            return 0
        else
            log "FAIL" "$description YAML syntax is invalid"
            return 1
        fi
    else
        log "WARN" "Cannot validate YAML syntax (yq or python3+yaml not available)"
        return 0
    fi
}

validate_json_syntax() {
    local file=$1
    local description=$2
    
    if [ ! -f "$file" ]; then
        log "FAIL" "$description file not found: $file"
        return 1
    fi
    
    if python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
        log "SUCCESS" "$description JSON syntax is valid"
        return 0
    else
        log "FAIL" "$description JSON syntax is invalid"
        return 1
    fi
}

main() {
    local errors=0
    
    log "INFO" "Starting PyAirtable Monitoring Stack validation..."
    echo
    
    # Check core files
    log "INFO" "=== Core Configuration Files ==="
    check_file_exists "$SCRIPT_DIR/docker-compose.observability.yml" "Observability Docker Compose" || ((errors++))
    check_file_exists "$SCRIPT_DIR/deploy-monitoring-stack.sh" "Deployment Script" || ((errors++))
    check_file_exists "$SCRIPT_DIR/MONITORING_DEPLOYMENT_GUIDE.md" "Monitoring Guide" || ((errors++))
    echo
    
    # Check monitoring configurations
    log "INFO" "=== Monitoring Configuration ==="
    check_file_exists "$SCRIPT_DIR/monitoring/prometheus/prometheus.yml" "Prometheus Config" || ((errors++))
    check_file_exists "$SCRIPT_DIR/monitoring/prometheus/alert_rules.yml" "Alert Rules" || ((errors++))
    check_file_exists "$SCRIPT_DIR/monitoring/alertmanager/alertmanager.yml" "AlertManager Config" || ((errors++))
    check_file_exists "$SCRIPT_DIR/monitoring/otel/otel-collector-config.yml" "OpenTelemetry Config" || ((errors++))
    echo
    
    # Check Loki configuration
    log "INFO" "=== Loki Configuration ==="
    check_file_exists "$SCRIPT_DIR/monitoring/loki/loki-config.yml" "Loki Config" || ((errors++))
    check_file_exists "$SCRIPT_DIR/monitoring/promtail/promtail-config.yml" "Promtail Config" || ((errors++))
    echo
    
    # Check Grafana configuration
    log "INFO" "=== Grafana Configuration ==="
    check_file_exists "$SCRIPT_DIR/monitoring/grafana/datasources/datasources.yml" "Grafana Datasources" || ((errors++))
    check_file_exists "$SCRIPT_DIR/monitoring/grafana/dashboards/dashboards.yml" "Dashboard Provisioning" || ((errors++))
    echo
    
    # Check dashboards
    log "INFO" "=== Grafana Dashboards ==="
    check_file_exists "$SCRIPT_DIR/monitoring/grafana/dashboards/platform/pyairtable-platform-overview.json" "Platform Overview Dashboard" || ((errors++))
    check_file_exists "$SCRIPT_DIR/monitoring/grafana/dashboards/platform/ai-llm-cost-tracking.json" "AI/LLM Cost Dashboard" || ((errors++))
    check_file_exists "$SCRIPT_DIR/monitoring/grafana/dashboards/platform/business-metrics.json" "Business Metrics Dashboard" || ((errors++))
    check_file_exists "$SCRIPT_DIR/monitoring/grafana/dashboards/infrastructure/infrastructure-overview.json" "Infrastructure Dashboard" || ((errors++))
    echo
    
    # Check directories
    log "INFO" "=== Directory Structure ==="
    check_directory_exists "$SCRIPT_DIR/monitoring" "Monitoring Directory" || ((errors++))
    check_directory_exists "$SCRIPT_DIR/monitoring/prometheus" "Prometheus Directory" || ((errors++))
    check_directory_exists "$SCRIPT_DIR/monitoring/grafana" "Grafana Directory" || ((errors++))
    check_directory_exists "$SCRIPT_DIR/monitoring/loki" "Loki Directory" || ((errors++))
    check_directory_exists "$SCRIPT_DIR/monitoring/alertmanager" "AlertManager Directory" || ((errors++))
    echo
    
    # Validate YAML syntax
    log "INFO" "=== YAML Syntax Validation ==="
    validate_yaml_syntax "$SCRIPT_DIR/docker-compose.observability.yml" "Docker Compose" || ((errors++))
    validate_yaml_syntax "$SCRIPT_DIR/monitoring/prometheus/prometheus.yml" "Prometheus Config" || ((errors++))
    validate_yaml_syntax "$SCRIPT_DIR/monitoring/prometheus/alert_rules.yml" "Alert Rules" || ((errors++))
    validate_yaml_syntax "$SCRIPT_DIR/monitoring/alertmanager/alertmanager.yml" "AlertManager Config" || ((errors++))
    validate_yaml_syntax "$SCRIPT_DIR/monitoring/otel/otel-collector-config.yml" "OpenTelemetry Config" || ((errors++))
    validate_yaml_syntax "$SCRIPT_DIR/monitoring/loki/loki-config.yml" "Loki Config" || ((errors++))
    validate_yaml_syntax "$SCRIPT_DIR/monitoring/promtail/promtail-config.yml" "Promtail Config" || ((errors++))
    validate_yaml_syntax "$SCRIPT_DIR/monitoring/grafana/datasources/datasources.yml" "Grafana Datasources" || ((errors++))
    validate_yaml_syntax "$SCRIPT_DIR/monitoring/grafana/dashboards/dashboards.yml" "Dashboard Provisioning" || ((errors++))
    echo
    
    # Validate JSON syntax (dashboards)
    log "INFO" "=== JSON Syntax Validation ==="
    validate_json_syntax "$SCRIPT_DIR/monitoring/grafana/dashboards/platform/pyairtable-platform-overview.json" "Platform Overview Dashboard" || ((errors++))
    validate_json_syntax "$SCRIPT_DIR/monitoring/grafana/dashboards/platform/ai-llm-cost-tracking.json" "AI/LLM Cost Dashboard" || ((errors++))
    validate_json_syntax "$SCRIPT_DIR/monitoring/grafana/dashboards/platform/business-metrics.json" "Business Metrics Dashboard" || ((errors++))
    validate_json_syntax "$SCRIPT_DIR/monitoring/grafana/dashboards/infrastructure/infrastructure-overview.json" "Infrastructure Dashboard" || ((errors++))
    echo
    
    # Check for required services in Prometheus config
    log "INFO" "=== Prometheus Service Configuration ==="
    local prometheus_config="$SCRIPT_DIR/monitoring/prometheus/prometheus.yml"
    local required_services=("api-gateway" "llm-orchestrator" "mcp-server" "airtable-gateway" "platform-services" "automation-services" "saga-orchestrator" "frontend")
    
    for service in "${required_services[@]}"; do
        if grep -q "job_name: '$service'" "$prometheus_config"; then
            log "SUCCESS" "Prometheus configured for $service"
        else
            log "FAIL" "Prometheus missing configuration for $service"
            ((errors++))
        fi
    done
    echo
    
    # Check alert rules for key alerts
    log "INFO" "=== Alert Rules Validation ==="
    local alert_rules="$SCRIPT_DIR/monitoring/prometheus/alert_rules.yml"
    local required_alerts=("ServiceDown" "HighErrorRate" "HighResponseTime" "HighCPUUsage" "HighMemoryUsage")
    
    for alert in "${required_alerts[@]}"; do
        if grep -q "alert: $alert" "$alert_rules"; then
            log "SUCCESS" "Alert rule configured: $alert"
        else
            log "FAIL" "Missing alert rule: $alert"
            ((errors++))
        fi
    done
    echo
    
    # Summary
    log "INFO" "=== Validation Summary ==="
    if [ $errors -eq 0 ]; then
        log "SUCCESS" "All validation checks passed! ✅"
        log "INFO" "The monitoring stack is ready for deployment."
        echo
        log "INFO" "Next steps:"
        log "INFO" "1. Review and customize .env file if needed"
        log "INFO" "2. Deploy: ./deploy-monitoring-stack.sh deploy loki"
        log "INFO" "3. Access Grafana: http://localhost:3001 (admin/admin123)"
        echo
        exit 0
    else
        log "FAIL" "Validation failed with $errors error(s) ❌"
        log "ERROR" "Please fix the above issues before deploying."
        exit 1
    fi
}

main "$@"