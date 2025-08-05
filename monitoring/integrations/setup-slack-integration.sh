#!/bin/bash

# PyAirtable Slack Integration Setup Script
# Configures Slack webhooks and channels for monitoring alerts

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

# Slack configuration
SLACK_WORKSPACE=""
SLACK_WEBHOOK_URL=""
CHANNELS=(
    "alerts-critical"
    "alerts-warnings"  
    "alerts-business"
    "alerts-infrastructure"
    "alerts-security"
    "alerts-service-down"
)

# Function to get user input
get_user_input() {
    info "PyAirtable Slack Integration Setup"
    echo
    
    read -p "Enter your Slack workspace name: " SLACK_WORKSPACE
    read -p "Enter your Slack webhook URL: " SLACK_WEBHOOK_URL
    
    if [[ ! "$SLACK_WEBHOOK_URL" =~ ^https://hooks\.slack\.com/services/.* ]]; then
        error "Invalid Slack webhook URL format"
        exit 1
    fi
}

# Function to create Slack channels
create_slack_channels() {
    info "Recommended Slack channels for PyAirtable monitoring:"
    echo
    
    for channel in "${CHANNELS[@]}"; do
        echo "  #$channel - $(get_channel_description "$channel")"
    done
    
    echo
    warn "Please create these channels in your Slack workspace manually."
    warn "Add the PyAirtable monitoring bot to each channel."
    read -p "Press Enter after creating the channels..."
}

# Function to get channel description
get_channel_description() {
    local channel="$1"
    case "$channel" in
        "alerts-critical")
            echo "Critical system alerts requiring immediate attention"
            ;;
        "alerts-warnings")
            echo "Warning alerts that need monitoring but aren't critical"
            ;;
        "alerts-business")
            echo "Business metric alerts (costs, usage, performance)"
            ;;
        "alerts-infrastructure")
            echo "Infrastructure alerts (CPU, memory, disk space)"
            ;;
        "alerts-security")
            echo "Security alerts (unauthorized access, suspicious activity)"
            ;;
        "alerts-service-down")
            echo "Service downtime and availability alerts"
            ;;
        *)
            echo "General monitoring channel"
            ;;
    esac
}

# Function to test Slack integration
test_slack_integration() {
    info "Testing Slack integration..."
    
    local test_payload=$(cat << EOF
{
    "text": "PyAirtable Monitoring Test",
    "attachments": [
        {
            "color": "good",
            "title": "Test Alert",
            "text": "This is a test message from PyAirtable monitoring system.",
            "fields": [
                {
                    "title": "Environment",
                    "value": "Production",
                    "short": true
                },
                {
                    "title": "Status",
                    "value": "Test Successful",
                    "short": true
                }
            ],
            "footer": "PyAirtable Monitoring",
            "ts": $(date +%s)
        }
    ]
}
EOF
    )
    
    local response=$(curl -s -X POST -H 'Content-type: application/json' \
        --data "$test_payload" \
        "$SLACK_WEBHOOK_URL")
    
    if [ "$response" = "ok" ]; then
        success "Slack integration test successful!"
    else
        error "Slack integration test failed: $response"
        exit 1
    fi
}

# Function to create Slack notification templates
create_notification_templates() {
    info "Creating Slack notification templates..."
    
    local templates_dir="$(dirname "$0")/slack-templates"
    mkdir -p "$templates_dir"
    
    # Critical alert template
    cat > "$templates_dir/critical-alert.json" << 'EOF'
{
    "text": "🚨 CRITICAL ALERT 🚨",
    "attachments": [
        {
            "color": "danger",
            "title": "{{ .GroupLabels.alertname }}",
            "title_link": "{{ .Alerts.0.Annotations.dashboard_url }}",
            "text": "{{ range .Alerts }}{{ .Annotations.summary }}\n{{ .Annotations.description }}{{ end }}",
            "fields": [
                {
                    "title": "Service",
                    "value": "{{ .GroupLabels.service }}",
                    "short": true
                },
                {
                    "title": "Severity",
                    "value": "{{ .GroupLabels.severity }}",
                    "short": true
                },
                {
                    "title": "Status",
                    "value": "{{ .Status }}",
                    "short": true
                },
                {
                    "title": "Started",
                    "value": "{{ .Alerts.0.StartsAt.Format \"2006-01-02 15:04:05 UTC\" }}",
                    "short": true
                }
            ],
            "actions": [
                {
                    "type": "button",
                    "text": "View Runbook",
                    "url": "{{ .Alerts.0.Annotations.runbook_url }}"
                },
                {
                    "type": "button", 
                    "text": "View Dashboard",
                    "url": "{{ .Alerts.0.Annotations.dashboard_url }}"
                }
            ],
            "footer": "PyAirtable Monitoring",
            "ts": {{ .Alerts.0.StartsAt.Unix }}
        }
    ]
}
EOF

    # Warning alert template
    cat > "$templates_dir/warning-alert.json" << 'EOF'
{
    "text": "⚠️ Warning Alert",
    "attachments": [
        {
            "color": "warning",
            "title": "{{ .GroupLabels.alertname }}",
            "title_link": "{{ .Alerts.0.Annotations.dashboard_url }}",
            "text": "{{ range .Alerts }}{{ .Annotations.summary }}\n{{ .Annotations.description }}{{ end }}",
            "fields": [
                {
                    "title": "Service",
                    "value": "{{ .GroupLabels.service }}",
                    "short": true
                },
                {
                    "title": "Category",
                    "value": "{{ .GroupLabels.category }}",
                    "short": true
                }
            ],
            "footer": "PyAirtable Monitoring",
            "ts": {{ .Alerts.0.StartsAt.Unix }}
        }
    ]
}
EOF

    # Business metrics alert template
    cat > "$templates_dir/business-alert.json" << 'EOF'
{
    "text": "📊 Business Metrics Alert",
    "attachments": [
        {
            "color": "#ff9500",
            "title": "{{ .GroupLabels.alertname }}",
            "text": "{{ range .Alerts }}{{ .Annotations.summary }}\n{{ .Annotations.description }}{{ end }}",
            "fields": [
                {
                    "title": "Business Impact",
                    "value": "{{ .Alerts.0.Annotations.business_impact }}",
                    "short": false
                },
                {
                    "title": "Current Value", 
                    "value": "{{ .GroupLabels.value }}",
                    "short": true
                },
                {
                    "title": "Threshold",
                    "value": "{{ .Alerts.0.Annotations.threshold }}",
                    "short": true
                }
            ],
            "footer": "PyAirtable Business Monitoring",
            "ts": {{ .Alerts.0.StartsAt.Unix }}
        }
    ]
}
EOF

    success "Slack notification templates created in $templates_dir"
}

# Function to create Slack bot configuration
create_slack_bot_config() {
    info "Creating Slack bot configuration..."
    
    local config_file="$(dirname "$0")/slack-bot-config.yml"
    
    cat > "$config_file" << EOF
# PyAirtable Slack Bot Configuration
slack:
  workspace: "$SLACK_WORKSPACE"
  webhook_url: "$SLACK_WEBHOOK_URL"
  
  # Channel mapping for different alert types
  channels:
    critical: "alerts-critical"
    warning: "alerts-warnings"
    business: "alerts-business"
    infrastructure: "alerts-infrastructure"
    security: "alerts-security"
    service_down: "alerts-service-down"
  
  # Message formatting
  formatting:
    use_threads: true
    mention_on_critical: true
    include_graphs: true
    max_message_length: 4000
  
  # Rate limiting
  rate_limit:
    messages_per_minute: 20
    burst_limit: 5
  
  # Bot settings
  bot:
    name: "PyAirtable Monitor"
    icon_emoji: ":warning:"
    username: "pyairtable-bot"
EOF
    
    success "Slack bot configuration created: $config_file"
}

# Function to update AlertManager configuration
update_alertmanager_config() {
    info "Updating AlertManager configuration with Slack settings..."
    
    local alertmanager_config="../alertmanager/alertmanager-production.yml"
    
    # Backup existing config
    cp "$alertmanager_config" "$alertmanager_config.backup.$(date +%s)"
    
    # Update Slack webhook URL in the config
    sed -i.bak "s|SLACK_WEBHOOK_URL|$SLACK_WEBHOOK_URL|g" "$alertmanager_config"
    
    success "AlertManager configuration updated"
}

# Function to create Slack slash commands
create_slash_commands() {
    info "Slack slash commands to create in your workspace:"
    echo
    
    echo "1. /pyairtable-status"
    echo "   Description: Get current system status"
    echo "   Request URL: https://your-domain.com/slack/status"
    echo
    
    echo "2. /pyairtable-silence"
    echo "   Description: Silence alerts for a specified time"
    echo "   Request URL: https://your-domain.com/slack/silence"
    echo
    
    echo "3. /pyairtable-dashboard"
    echo "   Description: Get links to monitoring dashboards"
    echo "   Request URL: https://your-domain.com/slack/dashboards"
    echo
    
    warn "Please create these slash commands manually in your Slack app configuration."
}

# Main function
main() {
    echo "🔧 PyAirtable Slack Integration Setup"
    echo
    
    get_user_input
    create_slack_channels
    test_slack_integration
    create_notification_templates
    create_slack_bot_config
    update_alertmanager_config
    create_slash_commands
    
    echo
    success "Slack integration setup completed!"
    echo
    echo "Next steps:"
    echo "1. Create the recommended Slack channels"
    echo "2. Add the monitoring bot to each channel"
    echo "3. Test alert delivery by triggering a test alert"
    echo "4. Create Slack slash commands for interactive monitoring"
    echo "5. Configure additional team members as channel admins"
}

# Run main function
main "$@"