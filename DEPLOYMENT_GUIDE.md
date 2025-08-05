# PyAirtable Consolidated Services Deployment Guide

This guide provides comprehensive instructions for deploying the consolidated PyAirtable services to production.

## Repository Structure

The consolidated services have been deployed to the PyAirtableMCP GitHub organization:

### Go Services
- **pyairtable-auth-consolidated**: JWT authentication, OAuth, multi-tenant auth
- **pyairtable-tenant-consolidated**: Multi-tenant management and resource isolation
- **pyairtable-gateway-consolidated**: API gateway with routing and rate limiting

### Python Services  
- **pyairtable-data-consolidated**: Airtable API proxy, caching, and analytics
- **pyairtable-automation-consolidated**: Workflow engine and task scheduling
- **pyairtable-ai-consolidated**: LLM integration and intelligent data processing

## CI/CD Pipeline Features

Each service includes a comprehensive CI/CD pipeline with:

### Testing & Quality
- **Multi-version testing** (Python 3.9-3.11 for Python services)
- **Code quality checks** (Black, isort, ruff for Python; golangci-lint for Go)
- **Security scanning** (Bandit, safety for Python; gosec for Go)
- **Type checking** (mypy for Python)
- **Coverage reporting** with Codecov integration

### Security
- **Vulnerability scanning** with Trivy
- **Container security** with multi-stage builds
- **Non-root user** execution in containers
- **Minimal base images** (Alpine for Go, slim for Python)
- **Security headers** and best practices

### Deployment
- **Multi-platform builds** (linux/amd64, linux/arm64)
- **Container registry** integration (ghcr.io)
- **Staging and production** environments
- **Health checks** and monitoring
- **Zero-downtime deployment** support

## Production Deployment

### Prerequisites

1. **Kubernetes cluster** (recommended) or Docker Swarm
2. **Container registry** access (GitHub Container Registry)
3. **External services**:
   - PostgreSQL (for metadata)
   - Redis (for caching)
   - Message queue (Redis/RabbitMQ)

### Environment Variables

Each service requires specific environment variables. See individual service READMEs for complete lists.

#### Common Variables
```bash
# Application
ENVIRONMENT=production
LOG_LEVEL=info
PORT=8080

# Database
DATABASE_URL=postgresql://user:pass@postgres:5432/dbname
REDIS_URL=redis://redis:6379/0

# Security
JWT_SECRET_KEY=your-super-secret-key
API_KEY_HEADER=X-API-Key

# Monitoring
ENABLE_METRICS=true
METRICS_PORT=9090
```

### Kubernetes Deployment

#### 1. Create Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: pyairtable
```

#### 2. Create Secrets
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pyairtable-secrets
  namespace: pyairtable
type: Opaque
stringData:
  jwt-secret: "your-jwt-secret-key"
  database-url: "postgresql://user:pass@postgres:5432/pyairtable"
  redis-url: "redis://redis:6379/0"
  airtable-api-key: "your-airtable-api-key"
```

#### 3. Deploy Services
```yaml
# Gateway Service
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pyairtable-gateway
  namespace: pyairtable
spec:
  replicas: 3
  selector:
    matchLabels:
      app: pyairtable-gateway
  template:
    metadata:
      labels:
        app: pyairtable-gateway
    spec:
      containers:
      - name: gateway
        image: ghcr.io/pyairtablemcp/pyairtable-gateway-consolidated:latest
        ports:
        - containerPort: 8080
        env:
        - name: AUTH_SERVICE_URL
          value: "http://pyairtable-auth:8080"
        - name: DATA_SERVICE_URL
          value: "http://pyairtable-data:8000"
        envFrom:
        - secretRef:
            name: pyairtable-secrets
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: pyairtable-gateway
  namespace: pyairtable
spec:
  selector:
    app: pyairtable-gateway
  ports:
  - port: 80
    targetPort: 8080
  type: LoadBalancer
```

### Docker Compose (Development/Testing)

```yaml
version: '3.8'

services:
  gateway:
    image: ghcr.io/pyairtablemcp/pyairtable-gateway-consolidated:latest
    ports:
      - "8080:8080"
    environment:
      - AUTH_SERVICE_URL=http://auth:8080
      - DATA_SERVICE_URL=http://data:8000
      - REDIS_URL=redis://redis:6379
    depends_on:
      - auth
      - data
      - redis

  auth:
    image: ghcr.io/pyairtablemcp/pyairtable-auth-consolidated:latest
    ports:
      - "8081:8080"
    environment:
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/auth
      - JWT_SECRET_KEY=development-secret-key
    depends_on:
      - postgres

  data:
    image: ghcr.io/pyairtablemcp/pyairtable-data-consolidated:latest
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/data
      - REDIS_URL=redis://redis:6379
      - AIRTABLE_API_KEY=${AIRTABLE_API_KEY}
    depends_on:
      - postgres
      - redis

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=pyairtable
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
```

## Monitoring & Observability

### Prometheus Metrics

Each service exposes metrics at `/metrics`:

- **HTTP metrics**: Request count, duration, status codes
- **Business metrics**: Service-specific KPIs
- **System metrics**: Memory, CPU, connections

### Health Checks

All services provide health check endpoints:

- `/health` - Overall service health
- `/health/live` - Liveness probe
- `/health/ready` - Readiness probe

### Logging

Structured JSON logging with:

- **Request tracing** with correlation IDs
- **Error tracking** with stack traces
- **Performance metrics** and timing
- **Security events** and audit logs

## Security Considerations

### Container Security

- **Non-root users** in all containers
- **Minimal base images** to reduce attack surface
- **Security scanning** in CI/CD pipeline
- **Regular updates** for base images and dependencies

### Network Security

- **TLS termination** at load balancer
- **Internal service communication** over secure channels
- **Network policies** to restrict inter-service communication
- **Rate limiting** and DDoS protection

### Secrets Management

- **Environment variables** for development
- **Kubernetes secrets** for production
- **External secret managers** (AWS Secrets Manager, HashiCorp Vault)
- **Secret rotation** policies

## Scaling Considerations

### Horizontal Scaling

- **Stateless services** for easy horizontal scaling
- **Load balancing** across multiple instances
- **Auto-scaling** based on CPU/memory/custom metrics
- **Circuit breakers** to prevent cascading failures

### Database Scaling

- **Connection pooling** to optimize database connections
- **Read replicas** for read-heavy workloads
- **Database sharding** for multi-tenant isolation
- **Caching strategies** to reduce database load

## Troubleshooting

### Common Issues

1. **Service Discovery**: Ensure services can reach each other
2. **Database Connections**: Check connection strings and credentials
3. **Memory Issues**: Monitor memory usage and adjust limits
4. **Rate Limiting**: Verify rate limit configurations

### Debugging Tools

- **Health check endpoints** for service status
- **Metrics dashboards** for performance monitoring
- **Log aggregation** for centralized logging
- **Distributed tracing** for request flow analysis

## Rollback Procedures

### Quick Rollback

```bash
# Rollback to previous image version
kubectl set image deployment/pyairtable-gateway gateway=ghcr.io/pyairtablemcp/pyairtable-gateway-consolidated:previous-tag

# Check rollback status
kubectl rollout status deployment/pyairtable-gateway

# If issues persist, rollback completely
kubectl rollout undo deployment/pyairtable-gateway
```

### Database Rollback

- **Migration rollback** scripts for database changes
- **Data backup** before major updates
- **Point-in-time recovery** for critical issues

## Maintenance

### Regular Tasks

- **Security updates** for base images and dependencies
- **Log rotation** and cleanup
- **Database maintenance** (VACUUM, index optimization)
- **Metric cleanup** and data retention

### Monitoring Alerts

- **High error rates** (>5% 5xx responses)
- **High response times** (>2s p95)
- **Memory/CPU usage** (>80%)
- **Database connection issues**
- **Service unavailability**

## Support

For deployment issues:

1. Check service logs and metrics
2. Verify environment configuration
3. Test connectivity between services
4. Review GitHub Actions for CI/CD issues
5. Contact the development team for complex issues

## Next Steps

1. **Service Mesh**: Consider Istio or Linkerd for advanced traffic management
2. **GitOps**: Implement ArgoCD or Flux for declarative deployments  
3. **Observability**: Add distributed tracing with Jaeger or Zipkin
4. **Chaos Engineering**: Implement chaos testing for resilience
5. **Multi-region**: Plan for multi-region deployment strategy