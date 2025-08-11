# PyAirtable Istio Service Mesh

This directory contains a production-ready Istio service mesh configuration for PyAirtable, providing advanced security, traffic management, and observability features.

## 🚀 Features

### Security
- **Strict mTLS** between all services
- **Fine-grained authorization policies** with RBAC
- **JWT authentication** for API endpoints
- **Rate limiting** with tenant isolation
- **Security headers** injection
- **Network policies** for additional isolation

### Traffic Management
- **Circuit breakers** and retry policies
- **Load balancing** strategies (Round Robin, Least Conn)
- **Outlier detection** and health checking
- **Canary deployments** with traffic splitting
- **Request routing** based on headers and paths
- **Timeout and fault injection** for testing

### Observability
- **Distributed tracing** with Jaeger
- **Metrics collection** with Prometheus
- **Custom business metrics** (tenant, LLM usage, file operations)
- **Enhanced access logging** with business context
- **Grafana dashboards** for visualization
- **Alerting rules** for operational monitoring

## 📁 File Structure

```
service-mesh/
├── istio-installation.yaml         # Istio control plane configuration
├── pyairtable-security-policies.yaml   # Security and mTLS configuration
├── pyairtable-traffic-management.yaml  # Traffic routing and circuit breakers
├── pyairtable-observability.yaml       # Monitoring and tracing
├── deploy-istio.sh                      # Deployment script
├── dev/
│   ├── envoy.yaml                      # Envoy config for development
│   └── sidecar-config.json             # Development sidecar simulation
└── README.md                           # This file
```

## 🛠 Quick Start

### Production Deployment

1. **Prerequisites**
   ```bash
   # Ensure kubectl is configured for your cluster
   kubectl cluster-info
   
   # Install cert-manager (if not already installed)
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
   ```

2. **Deploy Istio Service Mesh**
   ```bash
   cd service-mesh
   ./deploy-istio.sh
   ```

3. **Verify Deployment**
   ```bash
   # Check Istio status
   istioctl proxy-status
   
   # Analyze configuration
   istioctl analyze -n pyairtable
   
   # Check mTLS status
   istioctl authn tls-check -n pyairtable
   ```

### Development Environment

1. **Start Development Environment**
   ```bash
   # Use the Istio-enabled Docker Compose
   docker-compose -f docker-compose.istio-dev.yml up -d
   
   # Access services through the mesh proxy
   curl http://localhost:8080/health
   ```

2. **Monitor Services**
   ```bash
   # Prometheus metrics
   open http://localhost:9090
   
   # Jaeger tracing
   open http://localhost:16686
   
   # Grafana dashboards
   open http://localhost:3001
   ```

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ISTIO_VERSION` | `1.20.2` | Istio version to install |
| `NAMESPACE` | `pyairtable` | Target namespace for services |
| `ENVIRONMENT` | `production` | Deployment environment |
| `ISTIO_NAMESPACE` | `istio-system` | Istio control plane namespace |

### TLS Configuration

For production, update the certificate configuration in Gateway resources:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: pyairtable-gateway
spec:
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - "your-domain.com"
    tls:
      mode: SIMPLE
      credentialName: your-tls-secret
```

### Rate Limiting

Configure rate limits per tenant tier:

```yaml
rate_limits:
  - match:
      headers:
        x-tenant-tier:
          exact: "free"
    limits:
      requests_per_minute: 100
      llm_tokens_per_day: 10000
```

## 📊 Monitoring

### Key Metrics

1. **Request Rate**: `pyairtable:istio_request_total:rate5m`
2. **Error Rate**: `pyairtable:istio_error_rate:rate5m`
3. **Latency P99**: `pyairtable:istio_request_duration:p99`
4. **mTLS Success**: `pyairtable:mesh_mtls_success_rate:rate5m`
5. **Circuit Breaker**: `pyairtable:mesh_circuit_breaker_open`

### Alerts

Critical alerts are configured for:
- High error rates (>5%)
- High latency (P99 > 1s)
- Circuit breaker activation
- mTLS handshake failures
- Rate limit exceeded

### Custom Business Metrics

- **API Requests by Tenant**: `pyairtable_api_requests_total`
- **LLM Token Usage**: `pyairtable_llm_tokens_used_total`
- **File Uploads**: `pyairtable_file_uploads_total`
- **Workflow Executions**: `pyairtable_workflow_executions_total`

## 🔒 Security

### mTLS Configuration

Strict mTLS is enforced between all services:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default-strict-mtls
spec:
  mtls:
    mode: STRICT
```

### Authorization Policies

Fine-grained access control:

```yaml
# Example: Auth service can only be accessed by API Gateway
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: auth-service-access
spec:
  selector:
    matchLabels:
      app: auth-service
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/pyairtable/sa/api-gateway-sa"]
```

### JWT Authentication

API endpoints require valid JWT tokens:

```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: pyairtable-jwt-auth
spec:
  jwtRules:
  - issuer: "pyairtable-auth"
    jwksUri: "http://auth-service/.well-known/jwks.json"
```

## 🚦 Traffic Management

### Circuit Breakers

Protect services from cascading failures:

```yaml
trafficPolicy:
  connectionPool:
    tcp:
      maxConnections: 50
    http:
      maxRequestsPerConnection: 5
      maxRetries: 3
  outlierDetection:
    consecutiveGatewayErrors: 3
    interval: 30s
    baseEjectionTime: 30s
```

### Canary Deployments

Gradually roll out new versions:

```yaml
http:
- route:
  - destination:
      host: api-gateway
      subset: stable
    weight: 90
  - destination:
      host: api-gateway
      subset: canary
    weight: 10
```

### Fault Injection

Test resilience with controlled failures:

```yaml
fault:
  delay:
    percentage:
      value: 1.0
    fixedDelay: 2s
  abort:
    percentage:
      value: 0.5
    httpStatus: 503
```

## 🧪 Testing

### Chaos Engineering

Enable fault injection for testing:

```bash
# Enable chaos testing
curl -H "x-chaos-test: enabled" http://api-gateway/api/v1/airtable/health

# Start chaos monkey (in Docker Compose)
docker-compose -f docker-compose.istio-dev.yml --profile chaos up
```

### Load Testing

Use tools like `hey` or `k6` to test:

```bash
# Install hey
go install github.com/rakyll/hey@latest

# Load test API endpoint
hey -n 1000 -c 10 -H "Authorization: Bearer <token>" \
    http://localhost:8080/api/v1/airtable/bases
```

### mTLS Verification

Test mutual TLS:

```bash
# Check mTLS status
istioctl authn tls-check api-gateway.pyairtable.svc.cluster.local

# View proxy configuration
istioctl proxy-config cluster api-gateway-<pod-id> -n pyairtable
```

## 🐛 Troubleshooting

### Common Issues

1. **Sidecar not injected**
   ```bash
   # Check namespace label
   kubectl get namespace pyairtable -o yaml
   
   # Verify injection
   kubectl get pods -n pyairtable -o jsonpath='{.items[*].spec.containers[*].name}'
   ```

2. **mTLS connection errors**
   ```bash
   # Check certificates
   istioctl proxy-config secret api-gateway-<pod-id> -n pyairtable
   
   # View TLS configuration
   istioctl proxy-config cluster api-gateway-<pod-id> -n pyairtable -o json
   ```

3. **Traffic not routing**
   ```bash
   # Check virtual service configuration
   istioctl proxy-config route api-gateway-<pod-id> -n pyairtable
   
   # Verify destination rules
   istioctl proxy-config endpoints api-gateway-<pod-id> -n pyairtable
   ```

### Debug Commands

```bash
# View all proxy configuration
istioctl proxy-config all api-gateway-<pod-id> -n pyairtable

# Get envoy access logs
kubectl logs api-gateway-<pod-id> -n pyairtable -c istio-proxy

# Check configuration analysis
istioctl analyze -n pyairtable --color=false

# Describe virtual service
kubectl describe virtualservice pyairtable-external-routes -n pyairtable
```

## 📈 Performance Tuning

### Resource Limits

Adjust sidecar resources:

```yaml
global:
  proxy:
    resources:
      requests:
        cpu: 10m
        memory: 40Mi
      limits:
        cpu: 100m
        memory: 128Mi
```

### Connection Pool Tuning

Optimize for your workload:

```yaml
connectionPool:
  tcp:
    maxConnections: 100
    connectTimeout: 30s
  http:
    http1MaxPendingRequests: 50
    http2MaxRequests: 100
    maxRequestsPerConnection: 10
```

## 🔄 Upgrading

### Istio Upgrade

```bash
# Download new version
export ISTIO_VERSION=1.21.0
curl -L https://istio.io/downloadIstio | sh -

# Upgrade control plane
istioctl upgrade

# Restart workloads to get new sidecars
kubectl rollout restart deployment -n pyairtable
```

### Configuration Updates

```bash
# Apply updated configurations
kubectl apply -f pyairtable-traffic-management.yaml

# Validate changes
istioctl analyze -n pyairtable
```

## 🤝 Contributing

When modifying the service mesh configuration:

1. Test changes in development environment first
2. Validate with `istioctl analyze`
3. Update documentation and examples
4. Test canary deployments before full rollout

## 📚 Additional Resources

- [Istio Documentation](https://istio.io/latest/docs/)
- [Envoy Configuration](https://www.envoyproxy.io/docs/envoy/latest/)
- [WASM Plugins](https://istio.io/latest/docs/reference/config/proxy_extensions/wasm-plugin/)
- [Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)