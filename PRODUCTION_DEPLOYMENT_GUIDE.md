# Production Deployment Guide

This guide provides step-by-step instructions for deploying the PyAirtable Compose infrastructure to production with enterprise-grade security and monitoring.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Infrastructure Setup](#infrastructure-setup)
3. [Security Configuration](#security-configuration)
4. [Secrets Management](#secrets-management)
5. [SSL/TLS Configuration](#ssltls-configuration)
6. [Monitoring Stack Deployment](#monitoring-stack-deployment)
7. [Network Security](#network-security)
8. [Container Security](#container-security)
9. [Database Configuration](#database-configuration)
10. [Application Deployment](#application-deployment)
11. [Testing and Validation](#testing-and-validation)
12. [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

- **Operating System:** Ubuntu 20.04 LTS or newer, RHEL 8+, or CentOS 8+
- **CPU:** Minimum 8 cores (16 cores recommended)
- **Memory:** Minimum 16GB RAM (32GB recommended)
- **Storage:** Minimum 100GB SSD (500GB recommended for production data)
- **Network:** Static IP address, proper DNS configuration

### Software Requirements

- Docker 24.0+ with Docker Compose Plugin
- Git 2.20+
- OpenSSL 1.1.1+
- curl, wget, jq
- Trivy security scanner

### Access Requirements

- **API Keys:** Gemini API key, Airtable Personal Access Token
- **SSL Certificates:** Valid TLS certificates for your domain
- **Network Access:** Firewall rules configured for required ports
- **Monitoring Access:** SMTP credentials for alerting

## Infrastructure Setup

### 1. Server Preparation

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    jq \
    openssl \
    git

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install -y docker-compose-plugin

# Install Trivy
sudo apt-get install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy
```

### 2. Directory Structure Setup

```bash
# Create application directory
sudo mkdir -p /opt/pyairtable-compose
sudo chown $USER:$USER /opt/pyairtable-compose
cd /opt/pyairtable-compose

# Clone repository
git clone <repository-url> .

# Create additional directories
mkdir -p {logs,backups,certificates,monitoring-data}
chmod 700 secrets backups certificates
```

### 3. Firewall Configuration

```bash
# Configure UFW firewall
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (adjust port as needed)
sudo ufw allow 22/tcp

# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow monitoring access (restrict to monitoring networks)
sudo ufw allow from 10.0.0.0/8 to any port 9090 proto tcp
sudo ufw allow from 172.16.0.0/12 to any port 3000 proto tcp
sudo ufw allow from 192.168.0.0/16 to any port 3000 proto tcp

# Reload firewall
sudo ufw reload
```

## Security Configuration

### 1. System Hardening

```bash
# Disable unused services
sudo systemctl disable --now \
    cups \
    bluetooth \
    avahi-daemon \
    whoopsie

# Configure system limits
cat << 'EOF' | sudo tee -a /etc/security/limits.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF

# Configure kernel parameters
cat << 'EOF' | sudo tee -a /etc/sysctl.conf
# Network security
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Performance tuning
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_syncookies = 1
fs.file-max = 2097152
EOF

sudo sysctl -p
```

### 2. Docker Security Configuration

```bash
# Create Docker daemon configuration
sudo mkdir -p /etc/docker
cat << 'EOF' | sudo tee /etc/docker/daemon.json
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "userland-proxy": false,
    "no-new-privileges": true,
    "seccomp-profile": "/etc/docker/seccomp-profile.json",
    "default-ulimits": {
        "nofile": {
            "name": "nofile",
            "hard": 65536,
            "soft": 65536
        },
        "nproc": {
            "name": "nproc",
            "hard": 32768,
            "soft": 32768
        }
    }
}
EOF

# Restart Docker
sudo systemctl restart docker
```

## Secrets Management

### 1. Generate Production Secrets

```bash
# Set environment variables
export GEMINI_API_KEY="your-actual-gemini-api-key"
export AIRTABLE_TOKEN="your-actual-airtable-token"
export POSTGRES_USER="pyairtable"
export POSTGRES_DB="pyairtable"

# Generate all secrets
./scripts/generate-production-secrets.sh

# Verify secrets were created
ls -la secrets/
```

### 2. Secure Secrets Directory

```bash
# Set proper permissions
chmod 700 secrets/
chmod 600 secrets/*.txt

# Create backup
tar -czf backups/secrets-$(date +%Y%m%d_%H%M%S).tar.gz secrets/
chmod 600 backups/secrets-*.tar.gz
```

## SSL/TLS Configuration

### 1. Obtain SSL Certificates

**Using Let's Encrypt (Recommended):**

```bash
# Install Certbot
sudo snap install --classic certbot

# Obtain certificates
sudo certbot certonly --standalone \
    -d your-domain.com \
    -d api.your-domain.com \
    --email your-email@example.com \
    --agree-tos \
    --non-interactive

# Copy certificates to nginx directory
sudo mkdir -p infrastructure/nginx/ssl
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem infrastructure/nginx/ssl/
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem infrastructure/nginx/ssl/
sudo cp /etc/letsencrypt/live/your-domain.com/chain.pem infrastructure/nginx/ssl/
sudo chown -R $USER:$USER infrastructure/nginx/ssl/
chmod 600 infrastructure/nginx/ssl/*.pem
```

**Using Custom Certificates:**

```bash
# Copy your certificates to the nginx directory
cp your-fullchain.pem infrastructure/nginx/ssl/fullchain.pem
cp your-private-key.pem infrastructure/nginx/ssl/privkey.pem
cp your-ca-chain.pem infrastructure/nginx/ssl/chain.pem
chmod 600 infrastructure/nginx/ssl/*.pem
```

### 2. Create Default Self-Signed Certificate (Fallback)

```bash
# Generate self-signed certificate for default server
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout infrastructure/nginx/ssl/default.key \
    -out infrastructure/nginx/ssl/default.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=default"

chmod 600 infrastructure/nginx/ssl/default.*
```

### 3. Configure Certificate Auto-Renewal

```bash
# Add renewal cron job
echo "0 12 * * * /usr/bin/certbot renew --quiet && docker compose -f /opt/pyairtable-compose/docker-compose.production.yml restart nginx-proxy" | sudo crontab -
```

## Monitoring Stack Deployment

### 1. Create Environment Configuration

```bash
# Create production environment file
cat << 'EOF' > .env.production
# Domain Configuration
DOMAIN_NAME=your-domain.com
CORS_ORIGINS=https://your-domain.com

# Database Configuration
POSTGRES_USER=pyairtable
POSTGRES_DB=pyairtable

# Application Configuration
ENVIRONMENT=production
LOG_LEVEL=info
VERSION_TAG=latest

# Monitoring Configuration
ENABLE_METRICS=true
SHOW_COST_TRACKING=true

# Performance Configuration
THINKING_BUDGET=10000
MAX_FILE_SIZE=10MB
ALLOWED_EXTENSIONS=pdf,doc,docx,txt,csv,xlsx

# Security Configuration
PASSWORD_MIN_LENGTH=12
PASSWORD_HASH_ROUNDS=14
SESSION_TIMEOUT=3600
MAX_LOGIN_ATTEMPTS=5
LOCKOUT_DURATION=900

# External Service URLs
AIRTABLE_BASE=your-airtable-base-id
EOF

chmod 600 .env.production
```

### 2. Configure Grafana Datasources

```bash
# Create Grafana datasources configuration
cat << 'EOF' > monitoring/grafana/datasources/prometheus.yml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
    
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: true
    
  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    editable: true
EOF
```

## Network Security

### 1. Configure Network Policies

The production docker-compose file already includes network segmentation:

- **pyairtable-frontend**: Public-facing network for nginx
- **pyairtable-internal**: Internal services communication
- **pyairtable-monitoring**: Isolated monitoring stack

### 2. Additional Firewall Rules

```bash
# Block common attack vectors
sudo iptables -A INPUT -p tcp --dport 80 -m string --string "User-Agent: sqlmap" --algo bm -j DROP
sudo iptables -A INPUT -p tcp --dport 443 -m string --string "User-Agent: sqlmap" --algo bm -j DROP

# Rate limiting at iptables level
sudo iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -m limit --limit 25/minute --limit-burst 20 -j ACCEPT

# Save rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

## Container Security

### 1. Run Security Scan

```bash
# Perform comprehensive security scan
./scripts/security-scan.sh docker-compose.production.yml

# Review results
less security-scan-results/security-scan-summary.txt
firefox security-scan-results/security-scan-report.html
```

### 2. Fix Critical Vulnerabilities

If critical vulnerabilities are found:

```bash
# Update base images
docker compose -f docker-compose.production.yml pull

# Rebuild custom images
docker compose -f docker-compose.production.yml build --no-cache

# Re-run security scan
./scripts/security-scan.sh docker-compose.production.yml
```

## Database Configuration

### 1. Initialize PostgreSQL

```bash
# Create database initialization script
cat << 'EOF' > init-db-production.sql
-- Create additional databases if needed
CREATE DATABASE monitoring;
CREATE DATABASE grafana;

-- Create roles with minimal privileges
CREATE ROLE app_read WITH LOGIN;
CREATE ROLE app_write WITH LOGIN;

-- Grant appropriate permissions
GRANT CONNECT ON DATABASE pyairtable TO app_read, app_write;
GRANT USAGE ON SCHEMA public TO app_read, app_write;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_write;

-- Set default privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_write;
EOF
```

### 2. Configure Database Backup

```bash
# Create backup script
cat << 'EOF' > scripts/backup-database.sh
#!/bin/bash

BACKUP_DIR="/opt/pyairtable-compose/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_NAME="pyairtable"
DB_USER="pyairtable"

# Create backup
docker compose -f docker-compose.production.yml exec postgres pg_dump \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    --verbose \
    --clean \
    --no-owner \
    --no-privileges > "$BACKUP_DIR/postgres_backup_$TIMESTAMP.sql"

# Compress backup
gzip "$BACKUP_DIR/postgres_backup_$TIMESTAMP.sql"

# Remove backups older than 7 days
find "$BACKUP_DIR" -name "postgres_backup_*.sql.gz" -mtime +7 -delete

echo "Database backup completed: postgres_backup_$TIMESTAMP.sql.gz"
EOF

chmod +x scripts/backup-database.sh

# Add to crontab
echo "0 2 * * * /opt/pyairtable-compose/scripts/backup-database.sh" | crontab -
```

## Application Deployment

### 1. Pre-Deployment Validation

```bash
# Validate docker-compose file
docker compose -f docker-compose.production.yml config

# Check secrets
ls -la secrets/
test -f secrets/api_key.txt || echo "Missing api_key.txt"
test -f secrets/postgres_password.txt || echo "Missing postgres_password.txt"

# Test SSL certificates
openssl x509 -in infrastructure/nginx/ssl/fullchain.pem -text -noout
```

### 2. Initial Deployment

```bash
# Load environment variables
export $(grep -v '^#' .env.production | xargs)

# Pull all images
docker compose -f docker-compose.production.yml pull

# Start infrastructure services first
docker compose -f docker-compose.production.yml up -d postgres redis

# Wait for databases to be ready
sleep 30

# Start remaining services
docker compose -f docker-compose.production.yml up -d

# Monitor startup
docker compose -f docker-compose.production.yml logs -f
```

### 3. Post-Deployment Verification

```bash
# Check service health
docker compose -f docker-compose.production.yml ps

# Test health endpoints
curl -k https://localhost/health
curl -k https://localhost/api/health

# Verify monitoring stack
curl -s http://localhost:9090/-/healthy  # Prometheus
curl -s http://localhost:3100/ready      # Loki
curl -s http://localhost:3200/ready      # Tempo
```

## Testing and Validation

### 1. Security Testing

```bash
# Run comprehensive security scan
./scripts/security-scan.sh

# Test SSL configuration
testssl.sh your-domain.com

# Test for common vulnerabilities
nmap -sV --script vuln your-domain.com
```

### 2. Performance Testing

```bash
# Load test with Apache Bench
ab -n 1000 -c 10 https://your-domain.com/api/health

# Test with wrk
wrk -t12 -c400 -d30s https://your-domain.com/api/health
```

### 3. Monitoring Validation

```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'

# Verify metrics collection
curl -s http://localhost:9090/api/v1/query?query=up

# Test alerting
curl -s http://localhost:9093/api/v1/alerts
```

## Troubleshooting

### Common Issues

#### 1. Container Won't Start

```bash
# Check logs
docker compose -f docker-compose.production.yml logs <service-name>

# Check resource usage
docker stats

# Verify secrets
ls -la secrets/
cat secrets/<secret-file>.txt
```

#### 2. SSL Certificate Issues

```bash
# Verify certificate files
openssl x509 -in infrastructure/nginx/ssl/fullchain.pem -text -noout

# Check certificate expiry
openssl x509 -in infrastructure/nginx/ssl/fullchain.pem -enddate -noout

# Test SSL configuration
curl -vI https://your-domain.com
```

#### 3. Database Connection Issues

```bash
# Check PostgreSQL logs
docker compose -f docker-compose.production.yml logs postgres

# Test database connection
docker compose -f docker-compose.production.yml exec postgres psql -U pyairtable -d pyairtable -c "SELECT version();"

# Verify network connectivity
docker compose -f docker-compose.production.yml exec api-gateway nc -zv postgres 5432
```

#### 4. Monitoring Issues

```bash
# Check Prometheus configuration
docker compose -f docker-compose.production.yml exec prometheus promtool check config /etc/prometheus/prometheus.yml

# Verify service discovery
curl -s http://localhost:9090/api/v1/targets

# Check Grafana logs
docker compose -f docker-compose.production.yml logs grafana
```

### Performance Tuning

#### 1. Database Optimization

```sql
-- Connect to database
\c pyairtable

-- Analyze query performance
ANALYZE;

-- Check slow queries
SELECT query, mean_time, calls, total_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- Optimize indexes
REINDEX DATABASE pyairtable;
```

#### 2. Redis Optimization

```bash
# Monitor Redis performance
docker compose -f docker-compose.production.yml exec redis redis-cli info memory
docker compose -f docker-compose.production.yml exec redis redis-cli info stats
```

#### 3. Application Tuning

```bash
# Monitor application metrics
curl -s http://localhost:9090/api/v1/query?query=rate(http_requests_total[5m])

# Check memory usage
docker compose -f docker-compose.production.yml exec api-gateway free -m
```

## Maintenance Procedures

### 1. Regular Updates

```bash
# Update system packages (schedule during maintenance window)
sudo apt update && sudo apt upgrade -y

# Update Docker images
docker compose -f docker-compose.production.yml pull
docker compose -f docker-compose.production.yml up -d

# Update SSL certificates
sudo certbot renew --quiet
docker compose -f docker-compose.production.yml restart nginx-proxy
```

### 2. Log Rotation

```bash
# Configure logrotate for application logs
cat << 'EOF' | sudo tee /etc/logrotate.d/pyairtable-compose
/opt/pyairtable-compose/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

### 3. Monitoring Maintenance

```bash
# Clean old metrics data (Prometheus)
docker compose -f docker-compose.production.yml exec prometheus \
    curl -X POST http://localhost:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~".+"}

# Clean old logs (Loki)
docker compose -f docker-compose.production.yml exec loki \
    /usr/bin/loki -config.file=/etc/loki/local-config.yaml -target=compactor -config.expand-env=true
```

## Support and Escalation

### Emergency Procedures

1. **Service Outage**: Check `/opt/pyairtable-compose/PRODUCTION_DEPLOYMENT_CHECKLIST.md`
2. **Security Incident**: Follow security incident response procedures
3. **Data Loss**: Restore from latest backup in `/opt/pyairtable-compose/backups/`

### Contact Information

- **Technical Lead**: [Contact Information]
- **Security Team**: [Contact Information]
- **Operations Team**: [Contact Information]
- **24/7 Support**: [Emergency Contact]

---

This deployment guide should be followed exactly for production deployments. Any deviations should be documented and approved by the security and operations teams.