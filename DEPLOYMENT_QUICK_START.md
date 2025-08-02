# PyAirtable Platform - Quick Deployment Guide

## 🚀 30-Minute Deployment

This guide will get your PyAirtable platform running in 30 minutes or less.

### Prerequisites (5 minutes)

1. **Install Dependencies**
   ```bash
   # macOS
   brew install docker docker-compose jq
   
   # Ubuntu/Debian
   sudo apt-get update && sudo apt-get install -y docker.io docker-compose jq curl
   
   # Verify installation
   docker --version && docker-compose --version && jq --version
   ```

2. **Get API Keys**
   - **Airtable Personal Access Token**: https://airtable.com/developers/web/api/authentication
   - **Google Gemini API Key**: https://cloud.google.com/ai-platform/generative-ai/docs/api-key

### Quick Start (25 minutes)

1. **Environment Setup** (5 minutes)
   ```bash
   cd /Users/kg/IdeaProjects/pyairtable-compose
   ./scripts/setup-environment.sh
   ```
   
   This interactive script will:
   - Generate secure secrets automatically
   - Prompt for your API keys
   - Create optimized configuration

2. **Deploy Platform** (15 minutes)
   ```bash
   ./scripts/deploy-platform.sh
   ```
   
   This automated script will:
   - Backup current state (safety)
   - Start infrastructure (PostgreSQL, Redis)
   - Run database migrations
   - Deploy services in optimal order
   - Verify health of all components

3. **Verify Deployment** (5 minutes)
   ```bash
   # Check service health
   ./scripts/health-check.sh
   
   # Run end-to-end tests
   ./scripts/smoke-test.sh
   ```

### Access Your Platform

- **API Gateway**: http://localhost:8080
- **Frontend**: http://localhost:3000  
- **Monitoring**: http://localhost:9090

### Test API Endpoints

```bash
# Register a user
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "Test123!",
    "first_name": "John",
    "last_name": "Doe"
  }'

# Login
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"Test123!"}' | jq -r '.access_token')

# Access protected endpoint
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/users/me
```

## 🔧 Configuration Files Created

### Core Files
- `/DEPLOYMENT_STRATEGY.md` - Complete deployment strategy
- `/docker-compose.production.yml` - Production-ready configuration
- `/scripts/setup-environment.sh` - Environment configuration
- `/scripts/deploy-platform.sh` - Automated deployment
- `/scripts/health-check.sh` - Service health monitoring
- `/scripts/smoke-test.sh` - End-to-end testing

### Monitoring
- `/monitoring/prometheus.yml` - Metrics collection
- `/monitoring/alert_rules.yml` - Alerting rules

## 📊 Platform Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │    │  API Gateway    │    │  Load Balancer  │
│   (Next.js)     │◄───┤  (Go - 8080)    │◄───┤  (Nginx/Cloud)  │
│   Port 3000     │    │                 │    │                 │
└─────────────────┘    └─────┬───────────┘    └─────────────────┘
                             │
                    ┌────────┴────────┐
                    │                 │
          ┌─────────▼─────────┐ ┌─────▼─────────────────┐
          │  Auth Service     │ │  User Service         │
          │  (Go - 8001)      │ │  (Go - 8002)          │
          └─────────┬─────────┘ └─────┬─────────────────┘
                    │                 │
          ┌─────────▼─────────────────▼─────────────────┐
          │  Workspace Service (Go - 8004)              │
          └─────────┬─────────────────────────────────────┘
                    │
     ┌──────────────┼──────────────────────────────────┐
     │              │                                  │
┌────▼─────┐ ┌─────▼──────┐ ┌─────────────┐ ┌─────────▼──────┐
│Airtable  │ │MCP Server  │ │LLM Orch.    │ │Platform Svcs   │
│Gateway   │ │(Py-8001)   │ │(Py-8003)    │ │(Py-8007)       │
│(Py-8002) │ │            │ │             │ │                │
└────┬─────┘ └─────┬──────┘ └─────────────┘ └─────────┬──────┘
     │             │                                  │
     └─────────────┼──────────────────────────────────┘
                   │
        ┌──────────▼──────────┐
        │  Infrastructure     │
        │                     │
        │  PostgreSQL  Redis  │
        │  (5432)      (6379) │
        └─────────────────────┘
```

## 🔐 Security Features

- **JWT Authentication** with secure token rotation
- **API Key Protection** for service-to-service communication
- **Rate Limiting** on all public endpoints
- **CORS Protection** with configurable origins
- **Database Encryption** at rest and in transit
- **Secret Management** with auto-generated secure keys
- **Network Isolation** between internal and public services

## 📈 Monitoring & Observability

- **Health Checks** on all services
- **Prometheus Metrics** collection
- **Alert Rules** for critical issues
- **Centralized Logging** with structured JSON
- **Performance Tracking** with request/response times
- **Resource Monitoring** (CPU, memory, disk)

## 🚨 Troubleshooting

### Common Issues

1. **Port Conflicts**
   ```bash
   # Check what's using the ports
   lsof -i :8080 -i :3000 -i :5432 -i :6379
   
   # Stop conflicting services
   sudo pkill -f "port 8080"
   ```

2. **Database Connection Issues**
   ```bash
   # Check PostgreSQL status
   docker-compose -f docker-compose.production.yml logs postgres
   
   # Test connection
   docker-compose -f docker-compose.production.yml exec postgres pg_isready
   ```

3. **Service Won't Start**
   ```bash
   # Check logs
   docker-compose -f docker-compose.production.yml logs [service-name]
   
   # Restart specific service
   docker-compose -f docker-compose.production.yml restart [service-name]
   ```

4. **API Errors**
   ```bash
   # Check API Gateway logs
   docker-compose -f docker-compose.production.yml logs api-gateway
   
   # Test health endpoint
   curl http://localhost:8080/health
   ```

### Emergency Rollback

```bash
./scripts/deploy-platform.sh --rollback
```

## 📝 Next Steps

1. **Production Hardening**
   - Configure SSL/TLS certificates
   - Set up proper DNS and load balancing
   - Implement log aggregation (ELK/Loki)
   - Configure automated backups

2. **Scaling**
   - Implement horizontal pod autoscaling
   - Add read replicas for database
   - Configure CDN for static assets
   - Set up service mesh (Istio/Linkerd)

3. **CI/CD Pipeline**
   - GitHub Actions for automated testing
   - Automated deployment triggers
   - Security scanning integration
   - Performance regression testing

## 🆘 Support

- **Documentation**: Check `/docs` folder for detailed guides
- **Health Check**: `./scripts/health-check.sh --verbose`
- **Service Status**: `docker-compose -f docker-compose.production.yml ps`
- **Logs**: `docker-compose -f docker-compose.production.yml logs -f`

---

**Estimated Deployment Time**: 30 minutes  
**Recovery Time**: 5 minutes  
**Uptime Target**: 99.9%