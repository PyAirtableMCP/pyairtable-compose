#!/bin/bash

# PyAirtable Security Compliance Framework Setup Script
# This script initializes the comprehensive security compliance framework

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_DIR="$(dirname "$BASE_DIR")"
LOG_FILE="/var/log/security-framework-setup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root for security reasons"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check for required commands
    local required_commands=(
        "docker"
        "docker-compose" 
        "python3"
        "pip3"
        "git"
        "curl"
        "jq"
        "openssl"
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # Check Python version
    local python_version=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1-2)
    if [[ $(echo "$python_version < 3.8" | bc -l) -eq 1 ]]; then
        error "Python 3.8 or higher is required. Found: $python_version"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    log "System requirements check completed successfully"
}

# Install security tools
install_security_tools() {
    log "Installing security scanning tools..."
    
    # Create tools directory
    mkdir -p "$BASE_DIR/tools"
    cd "$BASE_DIR/tools"
    
    # Install Python security tools
    log "Installing Python security tools..."
    pip3 install --user \
        bandit \
        safety \
        semgrep \
        snyk \
        pip-audit \
        checkov \
        detect-secrets
    
    # Install OWASP Dependency Check
    log "Installing OWASP Dependency Check..."
    if [[ ! -f "dependency-check/bin/dependency-check.sh" ]]; then
        curl -L "https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.0/dependency-check-8.4.0-release.zip" -o dependency-check.zip
        unzip -q dependency-check.zip
        rm dependency-check.zip
        chmod +x dependency-check/bin/dependency-check.sh
    fi
    
    # Install Nuclei
    log "Installing Nuclei vulnerability scanner..."
    if ! command -v nuclei &> /dev/null; then
        curl -L "https://github.com/projectdiscovery/nuclei/releases/latest/download/nuclei_2.9.4_linux_amd64.zip" -o nuclei.zip
        unzip -q nuclei.zip
        sudo mv nuclei /usr/local/bin/
        rm nuclei.zip
        nuclei -update-templates
    fi
    
    # Install TruffleHog for secret detection
    log "Installing TruffleHog for secret detection..."
    if ! command -v trufflehog &> /dev/null; then
        curl -L "https://github.com/trufflesecurity/trufflehog/releases/latest/download/trufflehog_3.54.0_linux_amd64.tar.gz" -o trufflehog.tar.gz
        tar -xzf trufflehog.tar.gz
        sudo mv trufflehog /usr/local/bin/
        rm trufflehog.tar.gz
    fi
    
    log "Security tools installation completed"
}

# Setup database and directories
setup_infrastructure() {
    log "Setting up security infrastructure..."
    
    # Create necessary directories
    mkdir -p "$BASE_DIR"/{logs,data,configs,reports,evidence,keys}
    
    # Set proper permissions
    chmod 750 "$BASE_DIR"/{data,evidence,keys}
    chmod 755 "$BASE_DIR"/{logs,configs,reports}
    
    # Create security database directory
    mkdir -p "$BASE_DIR/data/security"
    
    # Generate encryption keys for sensitive data
    log "Generating encryption keys..."
    if [[ ! -f "$BASE_DIR/keys/master.key" ]]; then
        openssl rand -base64 32 > "$BASE_DIR/keys/master.key"
        chmod 600 "$BASE_DIR/keys/master.key"
    fi
    
    # Create SSL certificates for internal communication
    log "Creating SSL certificates..."
    if [[ ! -f "$BASE_DIR/keys/server.crt" ]]; then
        openssl req -x509 -newkey rsa:4096 -keyout "$BASE_DIR/keys/server.key" -out "$BASE_DIR/keys/server.crt" -days 365 -nodes -subj "/C=US/ST=CA/L=SF/O=PyAirtable/CN=security.pyairtable.local"
        chmod 600 "$BASE_DIR/keys/server.key"
        chmod 644 "$BASE_DIR/keys/server.crt"
    fi
    
    log "Infrastructure setup completed"
}

# Setup configuration files
setup_configurations() {
    log "Setting up configuration files..."
    
    # SOC 2 configuration
    cat > "$BASE_DIR/configs/soc2-config.yaml" << 'EOF'
evidence_retention_years: 7
encryption_enabled: true
auto_collection_enabled: true
collection_frequency:
  daily: ['A1.1', 'PI1.1', 'CC7.1']
  weekly: ['CC6.2', 'C1.1']
  monthly: ['CC6.1', 'CC6.3', 'A1.2']
  quarterly: ['CC2.1', 'CC3.1', 'P1']
  annually: ['CC1.1', 'CC1.2', 'CC1.3']
system_endpoints:
  auth_service: 'http://auth-service:8080'
  audit_service: 'http://audit-service:8080'
  monitoring_service: 'http://monitoring-service:8080'
database_path: '/data/security/soc2_evidence.db'
evidence_path: '/evidence/soc2'
EOF

    # OWASP configuration
    cat > "$BASE_DIR/configs/owasp-config.yaml" << 'EOF'
scan_schedule:
  sast: 'daily'
  dast: 'weekly'
  sca: 'daily'
  manual: 'monthly'
severity_thresholds:
  critical: 0
  high: 5
  medium: 20
  low: 50
security_tools:
  sonarqube:
    enabled: true
    url: 'http://sonarqube:9000'
  owasp_zap:
    enabled: true
    url: 'http://zap:8080'
  snyk:
    enabled: true
  dependency_check:
    enabled: true
compliance_frameworks: ['OWASP_ASVS', 'NIST_CSF', 'ISO_27001']
database_path: '/data/security/owasp_security.db'
EOF

    # Privacy management configuration
    cat > "$BASE_DIR/configs/privacy-config.yaml" << 'EOF'
dsar_response_days: 30
ccpa_response_days: 45
breach_notification_hours: 72
consent_renewal_months: 24
retention_periods:
  customer_data: 2555  # 7 years
  marketing_data: 1095  # 3 years
  transaction_data: 3650  # 10 years
  log_data: 730  # 2 years
notification_settings:
  smtp_server: 'localhost'
  smtp_port: 587
  from_email: 'privacy@pyairtable.com'
  dpo_email: 'dpo@pyairtable.com'
database_path: '/data/security/privacy_management.db'
EOF

    log "Configuration files created successfully"
}

# Deploy security monitoring stack
deploy_monitoring_stack() {
    log "Deploying security monitoring stack..."
    
    # Create monitoring docker-compose file
    cat > "$BASE_DIR/docker-compose.security.yml" << 'EOF'
version: '3.8'

services:
  # OWASP ZAP for DAST scanning
  zap:
    image: owasp/zap2docker-stable:latest
    container_name: security-zap
    ports:
      - "8080:8080"
    command: zap-webswing.sh
    environment:
      - ZAP_AUTH_HEADER_VALUE=zap-api-key
    volumes:
      - zap-data:/zap/wrk
    networks:
      - security-net

  # SonarQube for SAST analysis
  sonarqube:
    image: sonarqube:community
    container_name: security-sonarqube
    ports:
      - "9000:9000"
    environment:
      - SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true
      - SONAR_JDBC_URL=jdbc:postgresql://sonar-db:5432/sonar
      - SONAR_JDBC_USERNAME=sonar
      - SONAR_JDBC_PASSWORD=sonar
    volumes:
      - sonarqube-data:/opt/sonarqube/data
      - sonarqube-logs:/opt/sonarqube/logs
      - sonarqube-extensions:/opt/sonarqube/extensions
    depends_on:
      - sonar-db
    networks:
      - security-net

  sonar-db:
    image: postgres:13
    container_name: security-sonar-db
    environment:
      - POSTGRES_USER=sonar
      - POSTGRES_PASSWORD=sonar
      - POSTGRES_DB=sonar
    volumes:
      - sonar-postgres-data:/var/lib/postgresql/data
    networks:
      - security-net

  # Vault for secrets management
  vault:
    image: vault:latest
    container_name: security-vault
    ports:
      - "8200:8200"
    environment:
      - VAULT_DEV_ROOT_TOKEN_ID=dev-root-token
      - VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200
    cap_add:
      - IPC_LOCK
    volumes:
      - vault-data:/vault/data
    networks:
      - security-net

  # Security dashboard
  security-dashboard:
    image: grafana/grafana:latest
    container_name: security-dashboard
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    volumes:
      - grafana-data:/var/lib/grafana
    networks:
      - security-net

volumes:
  zap-data:
  sonarqube-data:
  sonarqube-logs:
  sonarqube-extensions:
  sonar-postgres-data:
  vault-data:
  grafana-data:

networks:
  security-net:
    driver: bridge
EOF

    # Start security monitoring stack
    docker-compose -f "$BASE_DIR/docker-compose.security.yml" up -d
    
    # Wait for services to be ready
    log "Waiting for security services to start..."
    sleep 30
    
    # Configure SonarQube quality gates
    configure_sonarqube
    
    log "Security monitoring stack deployed successfully"
}

# Configure SonarQube
configure_sonarqube() {
    log "Configuring SonarQube quality gates..."
    
    # Wait for SonarQube to be ready
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s -f http://localhost:9000/api/system/status | jq -r '.status' | grep -q "UP"; then
            break
        fi
        log "Waiting for SonarQube to be ready... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error "SonarQube failed to start within expected time"
        return 1
    fi
    
    # Create security-focused quality gate
    log "Creating security quality gate..."
    curl -s -u admin:admin -X POST "http://localhost:9000/api/qualitygates/create" \
        -d "name=Security Gate"
    
    # Add security conditions
    local gate_id=$(curl -s -u admin:admin "http://localhost:9000/api/qualitygates/list" | jq -r '.qualitygates[] | select(.name=="Security Gate") | .id')
    
    if [[ -n "$gate_id" ]]; then
        # Add security-related conditions
        curl -s -u admin:admin -X POST "http://localhost:9000/api/qualitygates/create_condition" \
            -d "gateId=$gate_id&metric=security_hotspots&op=GT&error=0"
        
        curl -s -u admin:admin -X POST "http://localhost:9000/api/qualitygates/create_condition" \
            -d "gateId=$gate_id&metric=vulnerabilities&op=GT&error=0"
        
        curl -s -u admin:admin -X POST "http://localhost:9000/api/qualitygates/create_condition" \
            -d "gateId=$gate_id&metric=security_rating&op=GT&error=1"
        
        log "Security quality gate configured successfully"
    fi
}

# Setup CI/CD integration
setup_cicd_integration() {
    log "Setting up CI/CD security integration..."
    
    # Create GitHub Actions workflow for security scanning
    mkdir -p "$COMPOSE_DIR/.github/workflows"
    
    cat > "$COMPOSE_DIR/.github/workflows/security-scan.yml" << 'EOF'
name: Security Scan

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  security-scan:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v3
      with:
        fetch-depth: 0
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.9'
    
    - name: Install security tools
      run: |
        pip install bandit safety semgrep
        curl -L "https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.0/dependency-check-8.4.0-release.zip" -o dependency-check.zip
        unzip dependency-check.zip
        
    - name: Run Bandit security scan
      run: |
        bandit -r . -f json -o bandit-report.json || true
        
    - name: Run Safety dependency scan
      run: |
        safety check --json --output safety-report.json || true
        
    - name: Run Semgrep scan
      run: |
        semgrep --config=auto --json --output=semgrep-report.json . || true
        
    - name: Run OWASP Dependency Check
      run: |
        ./dependency-check/bin/dependency-check.sh --project "PyAirtable" --scan . --format JSON --out dependency-check-report.json || true
        
    - name: Upload security reports
      uses: actions/upload-artifact@v3
      with:
        name: security-reports
        path: |
          bandit-report.json
          safety-report.json
          semgrep-report.json
          dependency-check-report.json
          
    - name: Security Gate Check
      run: |
        python security-compliance/scripts/security-gate-check.py
EOF

    log "CI/CD security integration configured"
}

# Initialize databases
initialize_databases() {
    log "Initializing security databases..."
    
    # Run Python initialization scripts
    cd "$BASE_DIR"
    
    # Initialize SOC 2 evidence database
    python3 -c "
import sys
sys.path.append('soc2')
from evidence_collection import SOC2EvidenceCollector
collector = SOC2EvidenceCollector()
print('SOC 2 evidence database initialized')
"

    # Initialize OWASP security database
    python3 -c "
import sys
sys.path.append('application-security')
from owasp_security_framework import OWASPSecurityFramework
framework = OWASPSecurityFramework()
print('OWASP security database initialized')
"

    # Initialize privacy management database
    python3 -c "
import sys
sys.path.append('compliance')
from privacy_management_system import PrivacyManagementSystem
pms = PrivacyManagementSystem()
print('Privacy management database initialized')
"

    log "Security databases initialized successfully"
}

# Setup monitoring and alerting
setup_monitoring() {
    log "Setting up security monitoring and alerting..."
    
    # Create monitoring configuration
    mkdir -p "$BASE_DIR/monitoring"
    
    cat > "$BASE_DIR/monitoring/prometheus-security.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "security-rules.yml"

scrape_configs:
  - job_name: 'security-metrics'
    static_configs:
      - targets: ['localhost:8000']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'vulnerability-metrics'
    static_configs:
      - targets: ['localhost:8001']
    scrape_interval: 300s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
EOF

    # Create security alerting rules
    cat > "$BASE_DIR/monitoring/security-rules.yml" << 'EOF'
groups:
- name: security.rules
  rules:
  - alert: CriticalVulnerabilityDetected
    expr: security_vulnerabilities{severity="critical"} > 0
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Critical security vulnerability detected"
      description: "{{ $value }} critical vulnerabilities found"

  - alert: HighVulnerabilityThreshold
    expr: security_vulnerabilities{severity="high"} > 5
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High vulnerability count exceeded threshold"
      description: "{{ $value }} high severity vulnerabilities detected"

  - alert: SecurityScanFailure
    expr: security_scan_status != 1
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Security scan failed"
      description: "Security scanning pipeline has failed"
EOF

    log "Security monitoring and alerting configured"
}

# Generate security documentation
generate_documentation() {
    log "Generating security documentation..."
    
    # Create security runbook
    cat > "$BASE_DIR/docs/SECURITY_RUNBOOK.md" << 'EOF'
# Security Operations Runbook

## Daily Operations

### Security Scanning
1. Review overnight security scan results
2. Triage new vulnerabilities
3. Update vulnerability remediation status
4. Check compliance metrics

### Monitoring
1. Review security alerts and incidents
2. Check system health and availability
3. Monitor threat intelligence feeds
4. Update security dashboards

## Weekly Operations

### Vulnerability Management
1. Run comprehensive DAST scans
2. Review dependency vulnerabilities
3. Update security patches
4. Conduct penetration testing

### Compliance
1. Review SOC 2 control evidence
2. Update privacy compliance metrics
3. Generate weekly security reports
4. Conduct access reviews

## Monthly Operations

### Risk Assessment
1. Update threat model
2. Review security architecture
3. Conduct security training
4. Update security policies

### Audit Preparation
1. Collect compliance evidence
2. Update documentation
3. Prepare audit materials
4. Review control effectiveness

## Incident Response

### Severity 1 (Critical)
- Immediate response required
- Notify security team within 15 minutes
- Begin containment procedures
- Activate incident response team

### Severity 2 (High)
- Response within 2 hours
- Assess impact and scope
- Implement containment measures
- Document incident details

### Severity 3 (Medium)
- Response within 8 hours
- Investigate and analyze
- Plan remediation actions
- Update security controls

### Severity 4 (Low)
- Response within 24 hours
- Document findings
- Schedule remediation
- Monitor for patterns

## Emergency Contacts

- Security Team: security@pyairtable.com
- Incident Response: incident@pyairtable.com
- Management: management@pyairtable.com
- Legal: legal@pyairtable.com
EOF

    log "Security documentation generated"
}

# Run security validation tests
run_validation_tests() {
    log "Running security framework validation tests..."
    
    # Test database connectivity
    python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$BASE_DIR/data/security/soc2_evidence.db')
    conn.close()
    print('✓ SOC 2 database connectivity test passed')
except Exception as e:
    print(f'✗ SOC 2 database test failed: {e}')
"

    # Test security tools
    if command -v bandit &> /dev/null; then
        log "✓ Bandit installation verified"
    else
        error "✗ Bandit not found"
    fi
    
    if command -v semgrep &> /dev/null; then
        log "✓ Semgrep installation verified"
    else
        error "✗ Semgrep not found"
    fi
    
    if command -v nuclei &> /dev/null; then
        log "✓ Nuclei installation verified"
    else
        error "✗ Nuclei not found"
    fi
    
    # Test docker services
    if docker ps | grep -q "security-zap"; then
        log "✓ OWASP ZAP container running"
    else
        warning "✗ OWASP ZAP container not running"
    fi
    
    if docker ps | grep -q "security-sonarqube"; then
        log "✓ SonarQube container running"
    else
        warning "✗ SonarQube container not running"
    fi
    
    log "Security framework validation completed"
}

# Display setup summary
display_summary() {
    log "Security Compliance Framework Setup Complete!"
    echo
    echo "=== Setup Summary ==="
    echo "✓ Security tools installed"
    echo "✓ Infrastructure configured"
    echo "✓ Monitoring stack deployed"
    echo "✓ CI/CD integration configured"
    echo "✓ Databases initialized"
    echo "✓ Documentation generated"
    echo
    echo "=== Access Information ==="
    echo "SonarQube: http://localhost:9000 (admin/admin)"
    echo "OWASP ZAP: http://localhost:8080"
    echo "Security Dashboard: http://localhost:3000 (admin/admin123)"
    echo "Vault: http://localhost:8200 (token: dev-root-token)"
    echo
    echo "=== Next Steps ==="
    echo "1. Run initial security scan: ./scripts/run-security-scan.sh"
    echo "2. Configure compliance settings: ./scripts/configure-compliance.sh"
    echo "3. Set up alerting: ./scripts/setup-alerting.sh"
    echo "4. Review security documentation: ./docs/SECURITY_RUNBOOK.md"
    echo
    echo "=== Important Files ==="
    echo "Master key: $BASE_DIR/keys/master.key (keep secure!)"
    echo "SSL certificates: $BASE_DIR/keys/"
    echo "Configuration: $BASE_DIR/configs/"
    echo "Logs: $BASE_DIR/logs/"
    echo
}

# Main execution
main() {
    log "Starting PyAirtable Security Compliance Framework Setup"
    
    check_root
    check_requirements
    install_security_tools
    setup_infrastructure
    setup_configurations
    deploy_monitoring_stack
    setup_cicd_integration
    initialize_databases
    setup_monitoring
    generate_documentation
    run_validation_tests
    display_summary
    
    log "Setup completed successfully!"
}

# Run main function
main "$@"