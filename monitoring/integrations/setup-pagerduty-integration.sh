#!/bin/bash

# PyAirtable PagerDuty Integration Setup Script
# Configures PagerDuty for critical alert escalation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# PagerDuty configuration
PAGERDUTY_API_KEY=""
PAGERDUTY_INTEGRATION_KEY=""
PAGERDUTY_SERVICE_ID=""
EMAIL_FROM=""

# Function to get user input
get_user_input() {
    info "PyAirtable PagerDuty Integration Setup"
    echo
    
    read -p "Enter your PagerDuty API key: " PAGERDUTY_API_KEY
    read -p "Enter your PagerDuty integration key: " PAGERDUTY_INTEGRATION_KEY
    read -p "Enter your PagerDuty service ID: " PAGERDUTY_SERVICE_ID
    read -p "Enter email for PagerDuty notifications: " EMAIL_FROM
    
    if [ -z "$PAGERDUTY_API_KEY" ] || [ -z "$PAGERDUTY_INTEGRATION_KEY" ]; then
        error "PagerDuty API key and integration key are required"
        exit 1
    fi
}

# Function to test PagerDuty integration
test_pagerduty_integration() {
    info "Testing PagerDuty integration..."
    
    local test_payload=$(cat << EOF
{
    "routing_key": "$PAGERDUTY_INTEGRATION_KEY",
    "event_action": "trigger",
    "payload": {
        "summary": "PyAirtable Monitoring Test",
        "source": "pyairtable-monitoring",
        "severity": "info",
        "component": "monitoring-system",
        "group": "test",
        "class": "integration-test",
        "custom_details": {
            "description": "This is a test alert from PyAirtable monitoring system",
            "environment": "production",
            "test_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        }
    },
    "links": [
        {
            "href": "https://grafana.pyairtable.com",
            "text": "Grafana Dashboard"
        }
    ]
}
EOF
    )
    
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$test_payload" \
        "https://events.pagerduty.com/v2/enqueue")
    
    local status=$(echo "$response" | jq -r '.status // "error"')
    
    if [ "$status" = "success" ]; then
        local dedup_key=$(echo "$response" | jq -r '.dedup_key')
        success "PagerDuty integration test successful! Incident key: $dedup_key"
        
        # Resolve the test incident
        local resolve_payload=$(cat << EOF
{
    "routing_key": "$PAGERDUTY_INTEGRATION_KEY",
    "event_action": "resolve",
    "dedup_key": "$dedup_key"
}
EOF
        )
        
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$resolve_payload" \
            "https://events.pagerduty.com/v2/enqueue" >/dev/null
        
        info "Test incident resolved automatically"
    else
        error "PagerDuty integration test failed: $response"
        exit 1
    fi
}

# Function to create PagerDuty service configuration
create_pagerduty_service_config() {
    info "Creating PagerDuty service configuration..."
    
    local config_file="$(dirname "$0")/pagerduty-service-config.json"
    
    cat > "$config_file" << EOF
{
    "service": {
        "name": "PyAirtable Production Monitoring",
        "description": "Production monitoring and alerting for PyAirtable platform",
        "status": "active",
        "escalation_policy": {
            "type": "escalation_policy_reference",
            "id": "$PAGERDUTY_SERVICE_ID"
        },
        "incident_urgency_rule": {
            "type": "use_support_hours",
            "during_support_hours": {
                "type": "constant",
                "urgency": "high"
            },
            "outside_support_hours": {
                "type": "constant", 
                "urgency": "high"
            }
        },
        "support_hours": {
            "type": "fixed_time_per_day",
            "time_zone": "UTC",
            "start_time": "00:00:00",
            "end_time": "23:59:59",
            "days_of_week": [1, 2, 3, 4, 5, 6, 7]
        },
        "alert_creation": "create_alerts_and_incidents",
        "alert_grouping": "intelligent",
        "alert_grouping_timeout": 5
    }
}
EOF
    
    success "PagerDuty service configuration created: $config_file"
}

# Function to create escalation policies
create_escalation_policies() {
    info "Recommended PagerDuty escalation policies:"
    echo
    
    cat << 'EOF'
1. Critical Alerts Policy:
   - Level 1: Primary on-call engineer (immediate)
   - Level 2: Secondary on-call engineer (5 minutes)
   - Level 3: Engineering manager (10 minutes)
   - Level 4: CTO/VP Engineering (15 minutes)

2. Warning Alerts Policy:
   - Level 1: Primary on-call engineer (10 minutes)
   - Level 2: Team lead (30 minutes)

3. Business Alerts Policy:
   - Level 1: Product manager (15 minutes)
   - Level 2: Engineering lead (30 minutes)

4. Security Alerts Policy:
   - Level 1: Security team (immediate)
   - Level 2: Security manager (5 minutes)
   - Level 3: CISO (10 minutes)
EOF
    
    echo
    warn "Please create these escalation policies in your PagerDuty dashboard."
}

# Function to create PagerDuty webhooks configuration
create_webhooks_config() {
    info "Creating PagerDuty webhooks configuration..."
    
    local webhooks_config="$(dirname "$0")/pagerduty-webhooks.json"
    
    cat > "$webhooks_config" << EOF
{
    "webhooks": [
        {
            "endpoint_url": "https://your-domain.com/webhooks/pagerduty/incident-update",
            "description": "PyAirtable incident status updates",
            "events": [
                "incident.triggered",
                "incident.acknowledged",
                "incident.resolved",
                "incident.reassigned",
                "incident.escalated"
            ],
            "filter": {
                "type": "account",
                "id": "your-account-id"
            }
        },
        {
            "endpoint_url": "https://your-domain.com/webhooks/pagerduty/maintenance",
            "description": "PyAirtable maintenance window updates",
            "events": [
                "maintenance_window.opened",
                "maintenance_window.closed"
            ]
        }
    ]
}
EOF
    
    success "PagerDuty webhooks configuration created: $webhooks_config"
}

# Function to create alert severity mapping
create_severity_mapping() {
    info "Creating alert severity mapping..."
    
    local mapping_file="$(dirname "$0")/pagerduty-severity-mapping.yml"
    
    cat > "$mapping_file" << 'EOF'
# PyAirtable PagerDuty Severity Mapping
severity_mapping:
  critical:
    pagerduty_severity: "critical"
    urgency: "high"
    escalation_policy: "critical-alerts-policy"
    auto_resolve: false
    
  warning:
    pagerduty_severity: "warning"
    urgency: "low"
    escalation_policy: "warning-alerts-policy"
    auto_resolve: true
    auto_resolve_timeout: "1h"
    
  info:
    pagerduty_severity: "info"
    urgency: "low"
    escalation_policy: "info-alerts-policy"
    auto_resolve: true
    auto_resolve_timeout: "30m"

# Alert type specific configurations
alert_configurations:
  ServiceDown:
    severity: "critical"
    urgency: "high"
    title_template: "🚨 {{ .Labels.service }} Service Down"
    
  HighErrorRate:
    severity: "critical"
    urgency: "high"
    title_template: "⚠️ High Error Rate: {{ .Labels.service }}"
    
  HighLLMCosts:
    severity: "warning"
    urgency: "low"
    title_template: "💰 High LLM Costs Alert"
    
  UnauthorizedAccessAttempts:
    severity: "critical"
    urgency: "high"
    title_template: "🛡️ Security Alert: Unauthorized Access"
    escalation_policy: "security-alerts-policy"
EOF
    
    success "PagerDuty severity mapping created: $mapping_file"
}

# Function to create maintenance window templates
create_maintenance_templates() {
    info "Creating maintenance window templates..."
    
    local templates_dir="$(dirname "$0")/pagerduty-maintenance-templates"
    mkdir -p "$templates_dir"
    
    # Scheduled maintenance template
    cat > "$templates_dir/scheduled-maintenance.json" << 'EOF'
{
    "maintenance_window": {
        "type": "maintenance_window",
        "start_time": "2024-01-01T02:00:00Z",
        "end_time": "2024-01-01T04:00:00Z",
        "description": "PyAirtable scheduled maintenance - {{ .MaintenanceType }}",
        "services": [
            {
                "id": "PYAIRTABLE_SERVICE_ID",
                "type": "service_reference"
            }
        ],
        "teams": [
            {
                "id": "ENGINEERING_TEAM_ID",
                "type": "team_reference"
            }
        ]
    }
}
EOF

    # Emergency maintenance template
    cat > "$templates_dir/emergency-maintenance.json" << 'EOF'
{
    "maintenance_window": {
        "type": "maintenance_window",
        "start_time": "{{ .StartTime }}",
        "end_time": "{{ .EndTime }}",
        "description": "PyAirtable emergency maintenance - {{ .Reason }}",
        "services": [
            {
                "id": "PYAIRTABLE_SERVICE_ID", 
                "type": "service_reference"
            }
        ]
    }
}
EOF
    
    success "Maintenance window templates created in $templates_dir"
}

# Function to update AlertManager configuration
update_alertmanager_config() {
    info "Updating AlertManager configuration with PagerDuty settings..."
    
    local alertmanager_config="../alertmanager/alertmanager-production.yml"
    
    # Backup existing config
    cp "$alertmanager_config" "$alertmanager_config.backup.$(date +%s)"
    
    # Update PagerDuty integration key in the config
    sed -i.bak "s|PAGERDUTY_INTEGRATION_KEY|$PAGERDUTY_INTEGRATION_KEY|g" "$alertmanager_config"
    
    success "AlertManager configuration updated"
}

# Function to create monitoring scripts
create_monitoring_scripts() {
    info "Creating PagerDuty monitoring scripts..."
    
    # Script to check PagerDuty service health
    cat > "$(dirname "$0")/check-pagerduty-health.sh" << EOF
#!/bin/bash

# Check PagerDuty service health
API_KEY="$PAGERDUTY_API_KEY"
SERVICE_ID="$PAGERDUTY_SERVICE_ID"

response=\$(curl -s -H "Authorization: Token token=\$API_KEY" \\
    -H "Accept: application/vnd.pagerduty+json;version=2" \\
    "https://api.pagerduty.com/services/\$SERVICE_ID")

status=\$(echo "\$response" | jq -r '.service.status // "unknown"')

if [ "\$status" = "active" ]; then
    echo "PagerDuty service is healthy"
    exit 0
else
    echo "PagerDuty service status: \$status"
    exit 1
fi
EOF
    
    chmod +x "$(dirname "$0")/check-pagerduty-health.sh"
    
    # Script to create maintenance windows
    cat > "$(dirname "$0")/create-maintenance-window.sh" << EOF
#!/bin/bash

# Create PagerDuty maintenance window
# Usage: ./create-maintenance-window.sh "Maintenance reason" "2024-01-01T02:00:00Z" "2024-01-01T04:00:00Z"

API_KEY="$PAGERDUTY_API_KEY"
SERVICE_ID="$PAGERDUTY_SERVICE_ID"
EMAIL="$EMAIL_FROM"

REASON="\$1"
START_TIME="\$2"
END_TIME="\$3"

if [ \$# -ne 3 ]; then
    echo "Usage: \$0 <reason> <start_time> <end_time>"
    echo "Example: \$0 'Database upgrade' '2024-01-01T02:00:00Z' '2024-01-01T04:00:00Z'"
    exit 1
fi

payload=\$(cat << EOFPAYLOAD
{
    "maintenance_window": {
        "type": "maintenance_window",
        "start_time": "\$START_TIME",
        "end_time": "\$END_TIME",
        "description": "PyAirtable: \$REASON",
        "services": [
            {
                "id": "\$SERVICE_ID",
                "type": "service_reference"
            }
        ]
    }
}
EOFPAYLOAD
)

response=\$(curl -s -X POST \\
    -H "Authorization: Token token=\$API_KEY" \\
    -H "Accept: application/vnd.pagerduty+json;version=2" \\
    -H "Content-Type: application/json" \\
    -H "From: \$EMAIL" \\
    -d "\$payload" \\
    "https://api.pagerduty.com/maintenance_windows")

maintenance_id=\$(echo "\$response" | jq -r '.maintenance_window.id // "error"')

if [ "\$maintenance_id" != "error" ]; then
    echo "Maintenance window created: \$maintenance_id"
    echo "Start: \$START_TIME"
    echo "End: \$END_TIME"
    echo "Reason: \$REASON"
else
    echo "Failed to create maintenance window: \$response"
    exit 1
fi
EOF
    
    chmod +x "$(dirname "$0")/create-maintenance-window.sh"
    
    success "PagerDuty monitoring scripts created"
}

# Main function
main() {
    echo "📟 PyAirtable PagerDuty Integration Setup"
    echo
    
    get_user_input
    test_pagerduty_integration
    create_pagerduty_service_config
    create_escalation_policies
    create_webhooks_config
    create_severity_mapping
    create_maintenance_templates
    update_alertmanager_config
    create_monitoring_scripts
    
    echo
    success "PagerDuty integration setup completed!"
    echo
    echo "Next steps:"
    echo "1. Create the recommended escalation policies in PagerDuty"
    echo "2. Configure on-call schedules for your team"
    echo "3. Set up PagerDuty mobile app for team members"
    echo "4. Test alert escalation by triggering a critical alert"
    echo "5. Configure incident response procedures"
    echo "6. Set up status page integration"
}

# Run main function
main "$@"