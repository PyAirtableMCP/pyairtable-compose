#!/bin/bash

# PyAirtable Visual Testing Monitoring Setup for LGTM Stack
# This script sets up monitoring and alerting for Playwright visual tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MONITORING_DIR="$PROJECT_DIR/monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
}

# Create Grafana dashboard for visual testing metrics
create_grafana_dashboard() {
    log "INFO" "Creating Grafana dashboard configuration for visual testing..."
    
    local dashboard_file="$MONITORING_DIR/grafana/dashboards/visual-testing-dashboard.json"
    mkdir -p "$(dirname "$dashboard_file")"
    
    cat > "$dashboard_file" << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "PyAirtable Visual Testing Dashboard",
    "tags": ["pyairtable", "visual-testing", "playwright"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Test Execution Overview",
        "type": "stat",
        "targets": [
          {
            "expr": "playwright_tests_passed",
            "legendFormat": "Passed Tests",
            "refId": "A"
          },
          {
            "expr": "playwright_tests_failed",
            "legendFormat": "Failed Tests",
            "refId": "B"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "palette-classic"
            },
            "custom": {
              "displayMode": "list",
              "orientation": "horizontal"
            },
            "mappings": [],
            "thresholds": {
              "steps": [
                {
                  "color": "green",
                  "value": null
                },
                {
                  "color": "red",
                  "value": 1
                }
              ]
            }
          }
        },
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 0
        }
      },
      {
        "id": 2,
        "title": "Test Suite Success Rate",
        "type": "piechart",
        "targets": [
          {
            "expr": "sum by (suite) (playwright_tests_passed)",
            "legendFormat": "{{suite}} Passed",
            "refId": "A"
          },
          {
            "expr": "sum by (suite) (playwright_tests_failed)",
            "legendFormat": "{{suite}} Failed",
            "refId": "B"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 0
        }
      },
      {
        "id": 3,
        "title": "Test Execution Duration",
        "type": "timeseries",
        "targets": [
          {
            "expr": "playwright_test_duration_ms",
            "legendFormat": "{{suite}} Duration (ms)",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "palette-classic"
            },
            "custom": {
              "axisLabel": "",
              "axisPlacement": "auto",
              "barAlignment": 0,
              "drawStyle": "line",
              "fillOpacity": 10,
              "gradientMode": "none",
              "hideFrom": {
                "legend": false,
                "tooltip": false,
                "vis": false
              },
              "lineInterpolation": "linear",
              "lineWidth": 1,
              "pointSize": 5,
              "scaleDistribution": {
                "type": "linear"
              },
              "showPoints": "never",
              "spanNulls": false,
              "stacking": {
                "group": "A",
                "mode": "none"
              },
              "thresholdsStyle": {
                "mode": "off"
              }
            },
            "unit": "ms"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 24,
          "x": 0,
          "y": 8
        }
      },
      {
        "id": 4,
        "title": "Test Failure Rate by Suite",
        "type": "bargauge",
        "targets": [
          {
            "expr": "rate(playwright_tests_failed[5m]) * 100",
            "legendFormat": "{{suite}} Failure Rate %",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "thresholds": {
              "steps": [
                {
                  "color": "green",
                  "value": null
                },
                {
                  "color": "yellow",
                  "value": 5
                },
                {
                  "color": "red",
                  "value": 10
                }
              ]
            },
            "unit": "percent"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 16
        }
      },
      {
        "id": 5,
        "title": "Recent Test Logs",
        "type": "logs",
        "targets": [
          {
            "expr": "{job=\"playwright_tests\"} |= \"METRICS\"",
            "refId": "A"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 16
        }
      }
    ],
    "refresh": "30s",
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "timepicker": {},
    "templating": {
      "list": []
    },
    "annotations": {
      "list": []
    },
    "schemaVersion": 27,
    "version": 0,
    "links": []
  }
}
EOF

    log "INFO" "Grafana dashboard created: $dashboard_file"
}

# Create Prometheus recording rules for visual testing metrics
create_prometheus_rules() {
    log "INFO" "Creating Prometheus recording rules for visual testing..."
    
    local rules_file="$MONITORING_DIR/prometheus/visual-testing-rules.yml"
    mkdir -p "$(dirname "$rules_file")"
    
    cat > "$rules_file" << 'EOF'
groups:
- name: visual_testing_rules
  interval: 30s
  rules:
  - record: pyairtable:playwright_test_success_rate
    expr: |
      (
        sum(playwright_tests_passed) / 
        (sum(playwright_tests_passed) + sum(playwright_tests_failed))
      ) * 100
    labels:
      component: visual_testing
      
  - record: pyairtable:playwright_test_failure_rate_5m
    expr: |
      rate(playwright_tests_failed[5m]) * 60
    labels:
      component: visual_testing
      
  - record: pyairtable:playwright_avg_duration_5m
    expr: |
      avg_over_time(playwright_test_duration_ms[5m])
    labels:
      component: visual_testing

  - record: pyairtable:playwright_total_tests_5m
    expr: |
      increase(playwright_tests_passed[5m]) + increase(playwright_tests_failed[5m])
    labels:
      component: visual_testing
EOF

    log "INFO" "Prometheus rules created: $rules_file"
}

# Create alerting rules for visual testing
create_alerting_rules() {
    log "INFO" "Creating alerting rules for visual testing..."
    
    local alerts_file="$MONITORING_DIR/prometheus/visual-testing-alerts.yml"
    mkdir -p "$(dirname "$alerts_file")"
    
    cat > "$alerts_file" << 'EOF'
groups:
- name: visual_testing_alerts
  rules:
  - alert: PlaywrightTestsFailureRateHigh
    expr: pyairtable:playwright_test_failure_rate_5m > 0.5
    for: 2m
    labels:
      severity: warning
      component: visual_testing
      team: frontend
    annotations:
      summary: "High failure rate in Playwright visual tests"
      description: "Visual test failure rate is {{ $value }} failures per minute over the last 5 minutes"
      runbook_url: "https://docs.pyairtable.com/runbooks/visual-testing-failures"
      
  - alert: PlaywrightTestsAllFailing
    expr: pyairtable:playwright_test_success_rate < 50
    for: 5m
    labels:
      severity: critical
      component: visual_testing
      team: frontend
    annotations:
      summary: "Visual tests success rate critically low"
      description: "Visual test success rate is {{ $value }}% - most tests are failing"
      runbook_url: "https://docs.pyairtable.com/runbooks/visual-testing-outage"
      
  - alert: PlaywrightTestDurationHigh
    expr: pyairtable:playwright_avg_duration_5m > 300000  # 5 minutes
    for: 3m
    labels:
      severity: warning
      component: visual_testing
      team: frontend
    annotations:
      summary: "Visual tests taking too long to execute"
      description: "Average test duration is {{ $value | humanizeDuration }} - consider optimizing tests"
      
  - alert: PlaywrightTestsNotRunning
    expr: |
      (time() - max(timestamp(playwright_tests_passed))) > 3600  # 1 hour
    for: 5m
    labels:
      severity: warning
      component: visual_testing
      team: frontend
    annotations:
      summary: "Visual tests haven't run recently"
      description: "No visual test metrics received for over 1 hour - check test automation"
EOF

    log "INFO" "Alerting rules created: $alerts_file"
}

# Create Loki log parsing configuration
create_loki_config() {
    log "INFO" "Creating Loki configuration for visual testing logs..."
    
    local loki_config="$MONITORING_DIR/loki/visual-testing-config.yml"
    mkdir -p "$(dirname "$loki_config")"
    
    cat > "$loki_config" << 'EOF'
# Loki configuration for visual testing logs
server:
  http_listen_port: 3100

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
- job_name: playwright_tests
  static_configs:
  - targets:
      - localhost
    labels:
      job: playwright_tests
      component: visual_testing
      __path__: /var/log/pyairtable/visual-test-reports/*.log
  
  pipeline_stages:
  - regex:
      expression: '\[(?P<timestamp>[^\]]+)\] \[(?P<level>[^\]]+)\] (?P<message>.*)'
  
  - labels:
      level:
      timestamp:
  
  - timestamp:
      source: timestamp
      format: '2006-01-02 15:04:05'
  
  # Parse structured metrics logs
  - match:
      selector: '{job="playwright_tests"} |= "METRICS:"'
      stages:
      - regex:
          expression: 'METRICS: suite=(?P<suite>[^ ]+) passed=(?P<passed>[^ ]+) failed=(?P<failed>[^ ]+) duration_ms=(?P<duration>[^ ]+)'
      - labels:
          suite:
          test_passed: passed
          test_failed: failed
          test_duration: duration
EOF

    log "INFO" "Loki configuration created: $loki_config"
}

# Create monitoring setup script
create_monitoring_setup() {
    log "INFO" "Creating monitoring setup script..."
    
    local setup_script="$MONITORING_DIR/setup-visual-test-monitoring.sh"
    
    cat > "$setup_script" << 'EOF'
#!/bin/bash

# Setup monitoring for PyAirtable visual testing

set -e

MONITORING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Check if LGTM stack is running
check_lgtm_stack() {
    log "Checking LGTM stack services..."
    
    local services=("loki:3100" "grafana:3000" "prometheus:9090")
    local healthy=0
    
    for service in "${services[@]}"; do
        IFS=':' read -r name port <<< "$service"
        if curl -s -f "http://localhost:$port" > /dev/null 2>&1; then
            log "✓ $name is running on port $port"
            ((healthy++))
        else
            log "✗ $name is not accessible on port $port"
        fi
    done
    
    if [ $healthy -eq ${#services[@]} ]; then
        log "All LGTM services are running"
        return 0
    else
        log "Warning: Not all LGTM services are available ($healthy/${#services[@]})"
        return 1
    fi
}

# Import Grafana dashboard
import_grafana_dashboard() {
    log "Importing Grafana dashboard..."
    
    local dashboard_file="$MONITORING_DIR/grafana/dashboards/visual-testing-dashboard.json"
    
    if [ -f "$dashboard_file" ]; then
        # Try to import dashboard via Grafana API
        if curl -s -f -X POST \
            -H "Content-Type: application/json" \
            -d @"$dashboard_file" \
            "http://admin:admin@localhost:3000/api/dashboards/db" > /dev/null; then
            log "✓ Grafana dashboard imported successfully"
        else
            log "✗ Failed to import Grafana dashboard - you may need to import manually"
            log "Dashboard file: $dashboard_file"
        fi
    else
        log "✗ Dashboard file not found: $dashboard_file"
    fi
}

# Setup Prometheus rules
setup_prometheus_rules() {
    log "Setting up Prometheus rules..."
    
    local rules_dir="/etc/prometheus/rules.d"
    local rules_file="$MONITORING_DIR/prometheus/visual-testing-rules.yml"
    local alerts_file="$MONITORING_DIR/prometheus/visual-testing-alerts.yml"
    
    # Copy rules if Prometheus config directory exists
    if [ -d "/etc/prometheus" ]; then
        sudo mkdir -p "$rules_dir"
        sudo cp "$rules_file" "$rules_dir/"
        sudo cp "$alerts_file" "$rules_dir/"
        log "✓ Prometheus rules installed"
        
        # Reload Prometheus configuration
        if curl -s -f -X POST "http://localhost:9090/-/reload"; then
            log "✓ Prometheus configuration reloaded"
        else
            log "✗ Failed to reload Prometheus - restart manually"
        fi
    else
        log "! Prometheus config directory not found - copy rules manually:"
        log "  Rules: $rules_file"
        log "  Alerts: $alerts_file"
    fi
}

# Main setup function
main() {
    log "Starting PyAirtable visual testing monitoring setup..."
    
    if check_lgtm_stack; then
        import_grafana_dashboard
        setup_prometheus_rules
        log "✓ Monitoring setup complete"
    else
        log "! LGTM stack not fully available - manual setup may be required"
    fi
    
    log "Monitoring artifacts available in: $MONITORING_DIR"
    log "Dashboard: http://localhost:3000/d/visual-testing"
    log "Prometheus: http://localhost:9090"
    log "Loki: http://localhost:3100"
}

main "$@"
EOF

    chmod +x "$setup_script"
    log "INFO" "Monitoring setup script created: $setup_script"
}

# Create documentation for the monitoring setup
create_monitoring_docs() {
    log "INFO" "Creating monitoring documentation..."
    
    local docs_file="$MONITORING_DIR/VISUAL_TESTING_MONITORING.md"
    
    cat > "$docs_file" << 'EOF'
# PyAirtable Visual Testing Monitoring

This document describes the monitoring setup for PyAirtable visual testing using the LGTM stack.

## Overview

The visual testing monitoring includes:
- **Grafana Dashboard**: Visual representation of test metrics
- **Prometheus Metrics**: Collection and storage of test data
- **Loki Logs**: Centralized log collection and analysis
- **Alerting**: Automated notifications for test failures

## Metrics Collected

### Core Metrics
- `playwright_tests_passed`: Number of passed tests by suite
- `playwright_tests_failed`: Number of failed tests by suite  
- `playwright_test_duration_ms`: Test execution duration in milliseconds

### Derived Metrics
- `pyairtable:playwright_test_success_rate`: Overall success rate percentage
- `pyairtable:playwright_test_failure_rate_5m`: Failure rate per minute (5m average)
- `pyairtable:playwright_avg_duration_5m`: Average test duration (5m average)

## Dashboard Access

- **Grafana**: http://localhost:3000/d/visual-testing
- **Prometheus**: http://localhost:9090
- **Loki**: http://localhost:3100

Default Grafana credentials: admin/admin

## Alerts Configured

### Warning Alerts
- **PlaywrightTestsFailureRateHigh**: Failure rate > 0.5/min for 2+ minutes
- **PlaywrightTestDurationHigh**: Average duration > 5 minutes for 3+ minutes
- **PlaywrightTestsNotRunning**: No metrics for 1+ hour

### Critical Alerts
- **PlaywrightTestsAllFailing**: Success rate < 50% for 5+ minutes

## Setup Instructions

1. Ensure LGTM stack is running:
   ```bash
   docker-compose -f docker-compose.lgtm.yml up -d
   ```

2. Run the monitoring setup:
   ```bash
   ./monitoring/setup-visual-test-monitoring.sh
   ```

3. Execute visual tests with monitoring:
   ```bash
   PROMETHEUS_PUSHGATEWAY_URL=http://localhost:9091 ./scripts/run-visual-tests.sh
   ```

## Troubleshooting

### Metrics Not Appearing
- Check if pushgateway is accessible
- Verify `PROMETHEUS_PUSHGATEWAY_URL` environment variable
- Check test execution logs

### Dashboard Empty
- Confirm Prometheus is scraping pushgateway
- Check Prometheus targets: http://localhost:9090/targets
- Verify dashboard datasource configuration

### Alerts Not Firing
- Check alertmanager configuration
- Verify alert rules syntax in Prometheus
- Test alert conditions manually

## Log Analysis

Visual test logs are structured with the format:
```
[TIMESTAMP] [LEVEL] MESSAGE
[TIMESTAMP] [INFO] METRICS: suite=SUITE passed=N failed=N duration_ms=MS timestamp=TS
```

Use Loki queries to analyze test patterns:
```logql
{job="playwright_tests"} |= "METRICS"
{job="playwright_tests"} |= "ERROR"
{job="playwright_tests",suite="visual-regression"}
```

## Extending Monitoring

To add custom metrics:

1. Update test runner script to emit new metrics
2. Add recording rules in `prometheus/visual-testing-rules.yml`
3. Update Grafana dashboard with new panels
4. Add alerts if needed in `prometheus/visual-testing-alerts.yml`

## Best Practices

- Run tests regularly (e.g., every 30 minutes)
- Set up notifications for critical alerts
- Review dashboard weekly for trends
- Update baseline screenshots when UI changes
- Monitor test execution duration for performance

---

For support, check the PyAirtable documentation or contact the frontend team.
EOF

    log "INFO" "Monitoring documentation created: $docs_file"
}

# Main execution
main() {
    log "INFO" "Setting up PyAirtable Visual Testing Monitoring..."
    
    create_grafana_dashboard
    create_prometheus_rules
    create_alerting_rules
    create_loki_config
    create_monitoring_setup
    create_monitoring_docs
    
    log "INFO" "Monitoring setup complete!"
    log "INFO" "Next steps:"
    log "INFO" "1. Start LGTM stack: docker-compose -f docker-compose.lgtm.yml up -d"
    log "INFO" "2. Run setup: $MONITORING_DIR/setup-visual-test-monitoring.sh" 
    log "INFO" "3. Execute tests: PROMETHEUS_PUSHGATEWAY_URL=http://localhost:9091 ./scripts/run-visual-tests.sh"
    log "INFO" "4. View dashboard: http://localhost:3000/d/visual-testing"
}

main "$@"