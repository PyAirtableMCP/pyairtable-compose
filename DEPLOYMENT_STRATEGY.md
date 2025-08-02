# PyAirtable Platform Deployment Strategy

## 🎯 Overview

This deployment strategy focuses on getting a working Phase 1 deployment quickly to validate the architecture and test service communication. The platform uses a hybrid Python-Go microservices architecture with PostgreSQL and Redis as core infrastructure.

## 🏗️ Current Architecture Status

### ✅ Phase 1 Services (Complete)
1. **API Gateway** (Go) - Port 8080 - Main entry point
2. **Auth Service** (Go) - Port 8001 - JWT authentication 
3. **User Service** (Go) - Port 8002 - User management
4. **Airtable Gateway** (Python) - Port 8002 - Airtable API integration

### ✅ Phase 2 Services (Complete)
1. **Workspace Service** (Go) - Multi-tenant workspace management
2. **Tenant Service** (Go) - Tenant isolation and permissions

### ✅ Core Python Services (Stable)
1. **MCP Server** (Python) - Port 8001 - Protocol implementation
2. **LLM Orchestrator** (Python) - Port 8003 - Gemini integration
3. **Platform Services** (Python) - Port 8007 - Unified auth & analytics
4. **Automation Services** (Python) - Port 8006 - Workflow automation

## 📋 Phase 1 Deployment Plan

### Step 1: Environment Setup (5 minutes)

1. **Copy environment template**
```bash
cd /Users/kg/IdeaProjects/pyairtable-compose
cp .env.example .env
```

2. **Configure critical variables**
```bash
# Edit .env file with required values:
# AIRTABLE_TOKEN=your-airtable-personal-access-token
# GEMINI_API_KEY=your-gemini-api-key
# API_KEY=generated-secure-api-key-for-service-communication
# JWT_SECRET=generated-jwt-secret-64-chars
# POSTGRES_PASSWORD=secure-postgres-password
# REDIS_PASSWORD=secure-redis-password
```

3. **Generate secure secrets**
```bash
# Generate API key
python3 -c "import secrets; print('API_KEY=' + secrets.token_urlsafe(48))" >> .env

# Generate JWT secret
python3 -c "import secrets; print('JWT_SECRET=' + secrets.token_urlsafe(64))" >> .env

# Generate Redis password
python3 -c "import secrets; print('REDIS_PASSWORD=' + secrets.token_urlsafe(32))" >> .env
```

### Step 2: Infrastructure Bootstrap (3 minutes)

1. **Start core infrastructure**
```bash
# Start PostgreSQL and Redis first
docker-compose up -d postgres redis

# Wait for health checks
sleep 30
docker-compose ps
```

2. **Initialize databases**
```bash
# Run database migrations
cd go-services/migrations
./run-migrations.sh
cd ../..
```

### Step 3: Core Services Deployment (10 minutes)

1. **Start Python services first** (stable dependencies)
```bash
# Start core Python services
docker-compose up -d airtable-gateway mcp-server llm-orchestrator
```

2. **Start Go services** (Phase 1)
```bash
# Start Go microservices
docker-compose -f go-services/docker-compose.phase1.yml up -d
```

3. **Start remaining services**
```bash
# Start platform and automation services
docker-compose up -d platform-services automation-services
```

### Step 4: API Gateway and Frontend (5 minutes)

1. **Start API Gateway**
```bash
# Main entry point
docker-compose up -d api-gateway
```

2. **Start Frontend** (optional for API testing)
```bash
# Web interface
docker-compose up -d frontend
```

### Step 5: Validation and Testing (5 minutes)

1. **Run health checks**
```bash
./quick-health-check.sh
```

2. **Run smoke tests**
```bash
./test-phase1.sh
```

## 🐳 Docker Compose Configuration

### Production-Ready Configuration

The platform uses multiple docker-compose files for different deployment scenarios:

1. **Main Services**: `docker-compose.yml` - Core Python services
2. **Phase 1 Go Services**: `go-services/docker-compose.phase1.yml` - Go microservices
3. **Development**: `docker-compose.dev.yml` - Development overrides

### Key Configuration Updates Needed

#### Resource Limits
```yaml
# Add to each service
deploy:
  resources:
    limits:
      cpus: '0.5'
      memory: 512M
    reservations:
      cpus: '0.25'
      memory: 256M
```

#### Health Checks
```yaml
# Standardized health checks
healthcheck:
  test: ["CMD-SHELL", "curl -f http://localhost:$PORT/health || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

#### Security Hardening
```yaml
# Remove exposed ports for internal services
# Only API Gateway (8080) and Frontend (3000) should be exposed
```

## 🔍 Health Check Procedures

### Automated Health Checks

1. **Infrastructure Health**
```bash
#!/bin/bash
echo "Checking infrastructure..."
docker-compose exec postgres pg_isready -U postgres
docker-compose exec redis redis-cli ping
```

2. **Service Health Matrix**
```bash
#!/bin/bash
services=(
    "API Gateway:8080:/health"
    "Auth Service:8001:/health"
    "User Service:8002:/health"
    "Airtable Gateway:8002:/health"
    "MCP Server:8001:/health"
    "LLM Orchestrator:8003:/health"
    "Platform Services:8007:/health"
    "Automation Services:8006:/health"
    "Frontend:3000:/api/health"
)

for service in "${services[@]}"; do
    IFS=':' read -r name port path <<< "$service"
    url="http://localhost:$port$path"
    
    if curl -s --max-time 5 "$url" | jq -e '.status == "healthy"' > /dev/null 2>&1; then
        echo "✅ $name - OK"
    else
        echo "❌ $name - FAILED"
    fi
done
```

### Smoke Test Procedures

1. **Authentication Flow Test**
```bash
# Register user
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"Test123!"}'

# Login and get token
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"Test123!"}' | jq -r '.access_token')

# Test authenticated endpoint
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/users/me
```

2. **Service Communication Test**
```bash
# Test API Gateway -> Auth Service
curl -X POST http://localhost:8080/api/v1/auth/validate \
  -H "Authorization: Bearer $TOKEN"

# Test API Gateway -> Airtable Gateway
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/airtable/bases
```

## 🔐 Critical Environment Variables

### Security Secrets (Required)
```bash
# Service Communication
API_KEY=<48-char-secure-token>              # CRITICAL: Service-to-service auth
JWT_SECRET=<64-char-secure-token>           # CRITICAL: JWT token signing

# External APIs
AIRTABLE_TOKEN=<airtable-personal-access-token>    # REQUIRED: Airtable integration
GEMINI_API_KEY=<google-gemini-api-key>            # REQUIRED: LLM functionality

# Database Security
POSTGRES_PASSWORD=<secure-password>         # CRITICAL: Database access
REDIS_PASSWORD=<secure-password>           # CRITICAL: Cache/session security
```

### Service Configuration
```bash
# Environment
ENVIRONMENT=production                      # production/staging/development
LOG_LEVEL=INFO                             # DEBUG/INFO/WARNING/ERROR

# CORS (Production)
CORS_ORIGINS=https://yourdomain.com        # NEVER use "*" in production

# Rate Limiting
DEFAULT_RATE_LIMIT=100/minute              # Adjust based on expected load
BURST_RATE_LIMIT=200/minute               # Peak traffic handling

# Database Connection
POSTGRES_HOST=postgres                     # Docker service name
POSTGRES_PORT=5432
POSTGRES_DB=pyairtable
POSTGRES_USER=postgres

# Redis Configuration
REDIS_HOST=redis                          # Docker service name  
REDIS_PORT=6379
REDIS_DB=0
```

### Service-Specific Variables
```bash
# MCP Server
MCP_SERVER_MODE=http                      # http/stdio
MCP_SERVER_PORT=8001

# LLM Orchestrator
THINKING_BUDGET=50000                     # Token budget for reasoning
USE_HTTP_MCP=true                        # HTTP mode for performance

# File Processing
MAX_FILE_SIZE=10MB                       # File upload limit
ALLOWED_EXTENSIONS=pdf,doc,docx,txt,csv,xlsx

# Workflow Engine
DEFAULT_WORKFLOW_TIMEOUT=300             # Seconds
MAX_WORKFLOW_RETRIES=3
```

## 📊 Monitoring and Logging Setup

### Basic Monitoring Stack

1. **Prometheus Configuration**
```yaml
# monitoring/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'pyairtable-services'
    static_configs:
      - targets: ['api-gateway:8080', 'auth-service:8001', 'user-service:8002']
    metrics_path: '/metrics'
```

2. **Grafana Dashboards**
```bash
# Pre-configured dashboards for:
# - Service health metrics
# - Request/response times  
# - Error rates
# - Database performance
# - Redis cache statistics
```

### Centralized Logging

1. **Log Format Standardization**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "level": "INFO",
  "service": "auth-service",
  "request_id": "req-123",
  "user_id": "user-456",
  "message": "User authenticated successfully",
  "duration_ms": 45
}
```

2. **Log Aggregation**
```yaml
# Use ELK stack or Loki for log aggregation
# Configure log rotation and retention
# Set up alert rules for errors
```

## 🚨 Rollback Procedures

### Quick Rollback Plan

1. **Service Rollback**
```bash
# Stop problematic service
docker-compose stop <service-name>

# Rollback to previous image
docker-compose pull <service-name>:previous-tag
docker-compose up -d <service-name>
```

2. **Database Rollback**
```bash
# Automatic backup before migrations
# Keep last 3 backup files
# 5-minute recovery time target
```

3. **Zero-Downtime Rollback**
```bash
# Blue-green deployment strategy
# Keep previous version running
# Switch traffic gradually
```

## ⚡ Performance Optimization

### Resource Allocation
- **API Gateway**: 1 CPU, 512MB RAM
- **Auth Service**: 0.5 CPU, 256MB RAM  
- **User Service**: 0.5 CPU, 256MB RAM
- **Airtable Gateway**: 0.5 CPU, 512MB RAM (Python overhead)
- **Database**: 2 CPU, 2GB RAM
- **Redis**: 0.5 CPU, 512MB RAM

### Caching Strategy
- **Redis TTL**: 15 minutes for user data, 1 hour for Airtable data
- **Database Connection Pooling**: 25 max connections per service
- **HTTP Caching**: ETag headers for static responses

## 📝 Deployment Checklist

### Pre-Deployment
- [ ] Environment variables configured
- [ ] Secrets generated and secured
- [ ] Database schemas up to date
- [ ] Docker images built and tested
- [ ] Health check endpoints verified

### Deployment
- [ ] Infrastructure services started (postgres, redis)
- [ ] Database migrations completed
- [ ] Core Python services deployed
- [ ] Go microservices deployed
- [ ] API Gateway configured
- [ ] Frontend deployed (optional)

### Post-Deployment
- [ ] All health checks passing
- [ ] Smoke tests completed
- [ ] Service communication verified
- [ ] Monitoring alerts configured
- [ ] Logs flowing correctly
- [ ] Backup procedures verified

## 🔄 Next Steps After Phase 1

1. **Integration Testing**: Comprehensive end-to-end test suite
2. **Performance Testing**: Load testing with realistic traffic patterns
3. **Security Audit**: Penetration testing and vulnerability assessment
4. **CI/CD Pipeline**: Automated testing and deployment
5. **Production Hardening**: Service mesh, advanced monitoring, auto-scaling

---

**Estimated Total Deployment Time**: 30 minutes
**Recovery Time Objective (RTO)**: 5 minutes
**Recovery Point Objective (RPO)**: 1 hour