# PyAirtable Local Deployment Guide
## MacBook Air M2 Optimized Configuration

### Resource Allocation Summary

#### Total Resource Budget (16GB MacBook Air M2)
- **Available for containers**: 12GB RAM (leaving 4GB for macOS)
- **CPU allocation**: 6 cores (2 reserved for system)
- **Storage**: Efficient volume management with retention policies

#### Service Resource Allocation

| Service | Memory Limit | CPU Limit | Purpose |
|---------|--------------|-----------|---------|
| **Application Services** | | | |
| pyairtable-api | 512MB | 0.5 cores | Main API server |
| pyairtable-worker | 256MB | 0.25 cores | Background tasks |
| pyairtable-scheduler | 256MB | 0.25 cores | Scheduled jobs |
| pyairtable-sync | 256MB | 0.25 cores | Data synchronization |
| pyairtable-webhook | 256MB | 0.25 cores | Webhook handling |
| pyairtable-frontend | 512MB | 0.5 cores | React frontend |
| **Database Services** | | | |
| PostgreSQL | 1024MB | 0.5 cores | Primary database |
| Redis | 256MB | 0.25 cores | Cache & sessions |
| **Monitoring Stack** | | | |
| Loki | 256MB | 0.25 cores | Log aggregation |
| Grafana | 512MB | 0.5 cores | Visualization |
| Tempo | 256MB | 0.25 cores | Tracing |
| Mimir | 512MB | 0.5 cores | Metrics storage |
| Prometheus | 512MB | 0.5 cores | Metrics collection |
| **Infrastructure** | | | |
| Nginx | 128MB | 0.25 cores | Load balancer |
| **TOTAL** | **~5.5GB** | **4.25 cores** | |

### Quick Start

1. **Prerequisites**
   ```bash
   # Ensure Docker Desktop is installed and running
   # Allocate at least 8GB RAM to Docker Desktop
   # Enable Kubernetes in Docker Desktop (optional)
   ```

2. **Clone and Setup**
   ```bash
   cd /Users/kg/IdeaProjects/pyairtable-compose
   cp .env.local .env  # Copy and modify as needed
   ```

3. **Start Environment**
   ```bash
   ./scripts/start-local.sh
   ```

4. **Monitor Resources**
   ```bash
   ./scripts/monitor-resources.sh
   ```

### Access URLs

- **Frontend**: http://pyairtable.local
- **API**: http://localhost:8000
- **Grafana**: http://monitoring.local
- **Prometheus**: http://localhost:9090
- **PostgreSQL**: localhost:5432 (postgres/postgres)
- **Redis**: localhost:6379

### Performance Optimizations

#### Database Optimizations

**PostgreSQL Configuration**:
- `shared_buffers=256MB` (optimized for 1GB limit)
- `effective_cache_size=1GB`
- `max_connections=100` (suitable for development)
- `wal_buffers=16MB`
- `checkpoint_completion_target=0.9`
- `random_page_cost=1.1` (optimized for SSD)

**Redis Configuration**:
- `maxmemory=200MB` (with LRU eviction)
- `maxmemory-policy=allkeys-lru`
- `save 900 1` (persistence for development)

#### Monitoring Optimizations

**Retention Policies**:
- Prometheus: 7 days, 1GB max
- Loki: 7 days retention
- Tempo: 1 hour blocks, minimal retention
- Mimir: 7 days for local development

**Sampling Rates**:
- Metrics collection: 15s intervals
- Log retention: 7 days
- Trace sampling: High for local development

### Development Workflow

#### Starting Services
```bash
# Full environment
./scripts/start-local.sh

# Individual services
docker-compose -f docker-compose.local.yml up -d postgres redis
docker-compose -f docker-compose.local.yml up -d pyairtable-api
```

#### Monitoring and Debugging
```bash
# Resource monitoring
./scripts/monitor-resources.sh

# Continuous monitoring
./scripts/monitor-resources.sh watch

# View logs
docker-compose -f docker-compose.local.yml logs -f pyairtable-api

# Health checks
curl http://localhost:8000/health
```

#### Database Access
```bash
# PostgreSQL
docker exec -it postgres psql -U postgres -d pyairtable

# Redis
docker exec -it redis redis-cli
```

### Troubleshooting

#### Common Issues

1. **High Memory Usage**
   - Check resource allocation: `./scripts/monitor-resources.sh`
   - Adjust limits in `docker-compose.local.yml`
   - Increase Docker Desktop memory allocation

2. **Services Not Starting**
   - Check Docker Desktop is running
   - Verify port availability: `lsof -i :8000`
   - Check logs: `docker-compose logs [service-name]`

3. **Database Connection Issues**
   - Wait for databases to initialize (30-60 seconds)
   - Check database health: `docker exec postgres pg_isready`

4. **DNS Resolution Issues**
   - Verify /etc/hosts entries
   - Restart network: `sudo dscacheutil -flushcache`

#### Resource Optimization Tips

1. **Reduce Memory Usage**
   ```bash
   # Stop non-essential services
   docker-compose -f docker-compose.local.yml stop tempo mimir
   
   # Use lighter monitoring
   # Comment out Mimir and Tempo in docker-compose.local.yml
   ```

2. **Improve Performance**
   ```bash
   # Increase Docker Desktop resources
   # Docker Desktop > Settings > Resources > Advanced
   # Memory: 8GB, CPUs: 6
   ```

3. **Development Mode Optimizations**
   - Disable non-essential monitoring
   - Use in-memory databases for testing
   - Enable hot-reload for frontend development

### Integration with IDEs

#### VS Code Integration
```json
// .vscode/settings.json
{
  "docker-compose.files": ["docker-compose.local.yml"],
  "docker-compose.projectName": "pyairtable-local"
}
```

#### JetBrains Integration
- Use Docker plugin
- Configure remote interpreters
- Set up database connections

### Security for Local Development

- Self-signed certificates in `nginx/certs/`
- Development-only secrets in `.env.local`
- Rate limiting configured in Nginx
- CORS enabled for local development

### CI/CD Integration

The local environment can be used for:
- E2E testing before deployment
- Integration testing with external APIs
- Performance baseline establishment
- Database migration testing

### Cost Considerations

**Local Development Costs**: $0
- No cloud resources required
- Uses local compute only
- Minimal external API calls

**Resource Efficiency**:
- ARM64 optimized images
- Minimal retention policies
- Efficient container layering
- Shared volumes for persistence

This configuration provides a production-like environment while maintaining optimal performance on MacBook Air M2 hardware.