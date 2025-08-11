# Docker Usage Guide - Consolidated Configuration

## Quick Reference

### Development (Default)
```bash
# Start all services
docker-compose up

# Start specific services
docker-compose up api-gateway llm-orchestrator

# Background mode
docker-compose up -d

# View logs
docker-compose logs -f api-gateway
```

### Production
```bash
# Deploy production stack
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Validate before deploy
docker-compose -f docker-compose.yml -f docker-compose.prod.yml config

# Scale services
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d --scale api-gateway=3

# Monitor production
docker-compose -f docker-compose.yml -f docker-compose.prod.yml exec prometheus sh
```

### Testing
```bash
# Run integration tests
docker-compose -f docker-compose.yml -f docker-compose.test.yml up test-runner

# Performance testing
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile performance up

# Chaos testing
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile chaos up

# Interactive test environment
docker-compose -f docker-compose.yml -f docker-compose.test.yml up -d
```

## Environment Variables

### Required (.env file)
```bash
# Core API Keys
API_KEY=your-api-key-here
AIRTABLE_TOKEN=your-airtable-token
AIRTABLE_BASE=your-base-id
GEMINI_API_KEY=your-gemini-key

# Database
POSTGRES_DB=pyairtable
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your-secure-password

# Redis
REDIS_PASSWORD=your-redis-password

# Security
JWT_SECRET=your-jwt-secret
NEXTAUTH_SECRET=your-nextauth-secret
```

### Production Additional
```bash
# SSL and Domain
NEXTAUTH_URL=https://app.pyairtable.com
CORS_ORIGINS=https://app.pyairtable.com,https://admin.pyairtable.com

# Monitoring
GRAFANA_ADMIN_PASSWORD=secure-grafana-password
GRAFANA_DOMAIN=monitoring.pyairtable.com

# Performance
RATE_LIMIT_RPM=100
THINKING_BUDGET=10000
AIRTABLE_RATE_LIMIT=5
```

## Service Endpoints

### Development
- **API Gateway**: http://localhost:8000
- **Frontend**: http://localhost:3000  
- **LLM Orchestrator**: http://localhost:8003
- **Airtable Gateway**: http://localhost:8002
- **Platform Services**: http://localhost:8007
- **Automation Services**: http://localhost:8006
- **SAGA Orchestrator**: http://localhost:8008

### Production Additional
- **Nginx**: http://localhost:80, https://localhost:443
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3001

### Testing Additional  
- **Mock Airtable**: http://localhost:8080
- **Mock Gemini**: http://localhost:8081
- **Test Reports**: ./test-reports/ volume

## Common Operations

### Health Checks
```bash
# Check all services
docker-compose ps

# Individual health checks
curl http://localhost:8000/api/health    # API Gateway
curl http://localhost:8002/health        # Airtable Gateway
curl http://localhost:8003/health        # LLM Orchestrator
curl http://localhost:8007/health        # Platform Services
curl http://localhost:8008/health/       # SAGA Orchestrator
```

### Logs and Debugging
```bash
# Follow all logs
docker-compose logs -f

# Service specific logs
docker-compose logs -f api-gateway llm-orchestrator

# Debug a single service
docker-compose exec api-gateway sh
```

### Data Management
```bash
# Database operations
docker-compose exec postgres psql -U postgres -d pyairtable

# Redis operations
docker-compose exec redis redis-cli -a $REDIS_PASSWORD

# Backup volumes
docker run --rm -v pyairtable-compose_postgres-data:/data busybox tar -czf backup.tar.gz /data
```

### Updates and Maintenance
```bash
# Pull latest images
docker-compose pull

# Rebuild services
docker-compose build --no-cache

# Clean up
docker-compose down -v  # Removes volumes too
docker system prune -a  # Clean all unused containers/images
```

## Troubleshooting

### Service Won't Start
1. Check logs: `docker-compose logs service-name`
2. Verify environment variables in `.env`
3. Check port conflicts: `netstat -tulpn | grep :8000`
4. Validate config: `docker-compose config`

### Database Connection Issues
1. Check database is healthy: `docker-compose ps postgres`  
2. Test connection: `docker-compose exec postgres pg_isready`
3. Check credentials in `.env` file
4. Verify network connectivity

### Performance Issues
1. Check resource usage: `docker stats`
2. Review service limits in production config  
3. Monitor logs for errors
4. Use production configuration for better performance

### Network Issues
1. Verify all services in same network: `docker network ls`
2. Test inter-service communication: `docker-compose exec api-gateway ping postgres`
3. Check firewall rules on host system

## Best Practices

### Development
- Always use `docker-compose up` without override files
- Keep `.env` file secure and never commit it
- Use `docker-compose logs -f` for debugging
- Restart services individually when making changes

### Production
- Always validate config before deployment
- Use proper SSL certificates, not self-signed  
- Set resource limits appropriately for your hardware
- Monitor logs and metrics regularly
- Backup data volumes regularly

### Testing
- Use test configuration for CI/CD pipelines
- Mock external services to avoid API rate limits
- Run tests in isolated environments
- Keep test data separate from development data

---

**Pro Tip**: Create aliases for common commands:
```bash
alias dc='docker-compose'
alias dcp='docker-compose -f docker-compose.yml -f docker-compose.prod.yml' 
alias dct='docker-compose -f docker-compose.yml -f docker-compose.test.yml'
```