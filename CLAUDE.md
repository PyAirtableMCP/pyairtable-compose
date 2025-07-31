# PyAirtable Compose - Claude Context

## 🎯 Repository Purpose
This is the **orchestration hub** for the entire PyAirtable ecosystem - containing Docker Compose configurations, environment setup, deployment scripts, and operational tools. It brings all microservices together into a cohesive, runnable system.

## 🏗️ Current State
- **Docker Compose**: ✅ Complete setup for all services
- **Database Init**: ✅ PostgreSQL schema ready
- **Environment Config**: ⚠️ Insecure defaults in .env.example
- **Health Scripts**: ✅ Basic testing scripts
- **Monitoring**: ❌ Not implemented
- **Backup**: ❌ No automation

## 📁 Repository Structure
```
pyairtable-compose/
├── docker-compose.yml         # Production configuration
├── docker-compose.dev.yml     # Development overrides
├── docker-compose.prod.yml    # Future: production optimizations
├── docker-compose.monitoring.yml  # TODO: Prometheus/Grafana
├── .env.example              # Environment template
├── init-db.sql              # PostgreSQL initialization
├── scripts/
│   ├── test-health.sh       # Health check testing
│   ├── test-chat.sh         # Chat functionality test
│   ├── backup.sh            # TODO: Backup automation
│   └── restore.sh           # TODO: Restore procedures
└── monitoring/              # TODO: Monitoring configs
```

## 🐳 Service Architecture
```yaml
Services:
  api-gateway (8000) → Routes all traffic
  llm-orchestrator (8003) → Gemini 2.5 Flash
  mcp-server (8001) → MCP protocol server
  airtable-gateway (8002) → Airtable API
  postgres (5432) → Session & metadata storage
  redis (6379) → Caching layer
```

## 🚀 Immediate Priorities

1. **Fix Security Issues** (CRITICAL)
   ```yaml
   # Remove from .env.example:
   POSTGRES_PASSWORD=changeme  # ❌ BAD
   REDIS_PASSWORD=changeme     # ❌ BAD
   
   # Replace with:
   POSTGRES_PASSWORD=  # Generate with: openssl rand -base64 32
   REDIS_PASSWORD=     # Generate with: openssl rand -base64 32
   ```

2. **Add Resource Limits** (HIGH)
   ```yaml
   services:
     api-gateway:
       deploy:
         resources:
           limits:
             cpus: '0.5'
             memory: 512M
   ```

3. **Implement Monitoring Stack** (HIGH)
   ```yaml
   # Create docker-compose.monitoring.yml
   prometheus:
     image: prom/prometheus:latest
   grafana:
     image: grafana/grafana:latest
   ```

## 🔮 Future Enhancements

### Phase 1 (Next Sprint)
- [ ] Automated backup scripts
- [ ] Monitoring stack (Prometheus/Grafana)
- [ ] Log aggregation (ELK or Loki)
- [ ] Service health dashboard

### Phase 2 (Next Month)
- [ ] Blue-green deployment support
- [ ] Kubernetes manifests option
- [ ] CI/CD integration scripts
- [ ] Performance testing suite

### Phase 3 (Future)
- [ ] Multi-environment support
- [ ] Terraform for cloud deployment
- [ ] Disaster recovery automation
- [ ] A/B testing infrastructure

## ⚠️ Known Issues
1. **Insecure defaults** in .env.example
2. **No resource limits** - can consume all host resources
3. **Database ports exposed** - security risk
4. **No backup automation** - data loss risk

## 🧪 Testing Commands
```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f [service-name]

# Run health check
./scripts/test-health.sh

# Test chat functionality
./scripts/test-chat.sh

# Stop all services
docker-compose down

# Reset everything (WARNING: data loss)
docker-compose down -v
```

## 🔧 Environment Variables
```bash
# Critical (must set)
AIRTABLE_TOKEN=pat_xxx      # Your Airtable PAT
GEMINI_API_KEY=xxx          # Your Gemini API key
POSTGRES_PASSWORD=xxx       # Strong password
REDIS_PASSWORD=xxx          # Strong password

# Service Configuration
API_KEY=xxx                 # Internal service auth
THINKING_BUDGET=5          # Gemini reasoning depth
LOG_LEVEL=INFO             # Logging verbosity

# Infrastructure
POSTGRES_DB=pyairtablemcp
POSTGRES_USER=admin
```

## 📊 Deployment Patterns

### Local Development
```bash
# Use dev override for hot reload
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up
```

### Production Deployment
```bash
# Future: Use production optimizations
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Scaling Services
```bash
# Scale specific service
docker-compose up -d --scale llm-orchestrator=3
```

## 🤝 Service Dependencies
```
Start Order:
1. postgres, redis
2. airtable-gateway
3. mcp-server
4. llm-orchestrator
5. api-gateway
```

## 💡 Operational Tips
1. Always check `.env` before starting
2. Monitor disk space (logs can grow)
3. Use `docker-compose logs` for debugging
4. Backup PostgreSQL before updates

## 🚨 Critical Operational Tasks

### Daily
- Check service health
- Monitor disk usage
- Review error logs

### Weekly
- Backup PostgreSQL data
- Update container images
- Review performance metrics

### Monthly
- Security updates
- Clean old logs
- Performance optimization

## 🔒 Security Checklist
- [ ] Change all default passwords
- [ ] Remove database port exposures
- [ ] Add network segmentation
- [ ] Enable TLS for Redis
- [ ] Implement secrets management
- [ ] Add firewall rules

## 📈 Monitoring Metrics
```yaml
# Future metrics to track:
- Service uptime per container
- Memory usage per service
- Request latency (p50, p95, p99)
- Error rates by service
- Database connection pool usage
- Redis cache hit rates
```

## 🎯 Backup Strategy
```bash
# TODO: Implement automated backup
#!/bin/bash
# Backup PostgreSQL
docker exec postgres pg_dump -U admin pyairtablemcp > backup_$(date +%Y%m%d).sql

# Backup Redis
docker exec redis redis-cli SAVE
docker cp redis:/data/dump.rdb redis_backup_$(date +%Y%m%d).rdb

# Backup environment
cp .env .env.backup.$(date +%Y%m%d)
```

## ⚡ Performance Tuning
1. **PostgreSQL**: Tune connection pool size
2. **Redis**: Configure maxmemory policy
3. **Docker**: Adjust container memory limits
4. **Network**: Use host networking for performance

Remember: This repository is the **operational control center** - it must be secure, well-documented, and easy to operate!