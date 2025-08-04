# PyAirtable Security Implementation Guide
**Production-Ready Security Deployment for 3vantage Organization**

## Overview

This guide provides step-by-step instructions for implementing the three critical security improvements for PyAirtable:

1. **mTLS Configuration** - Service-to-service mutual TLS authentication
2. **HashiCorp Vault Integration** - Enterprise secrets management
3. **Database Row-Level Security** - Multi-tenant data isolation

## Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    PyAirtable Security Stack                │
├─────────────────────────────────────────────────────────────┤
│  Application Layer (Go/Python Services)                     │
│  ├── mTLS Client Libraries                                  │
│  ├── Vault Client Integration                               │
│  └── RLS Database Clients                                   │
├─────────────────────────────────────────────────────────────┤
│  Security Layer                                             │
│  ├── Certificate Authority (CFSSL)                          │
│  ├── HashiCorp Vault (Secrets Management)                   │
│  └── Service Mesh (Istio/Envoy)                            │
├─────────────────────────────────────────────────────────────┤
│  Data Layer                                                 │
│  ├── PostgreSQL with RLS                                    │
│  ├── Encrypted Storage                                      │
│  └── Audit Logging                                          │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### System Requirements
- Kubernetes cluster (v1.24+)
- PostgreSQL 13+ with SSL support
- Docker/Podman for container builds
- kubectl configured for cluster access
- OpenSSL or CFSSL for certificate generation

### Security Prerequisites
- Dedicated namespace: `pyairtable-system`
- Vault namespace: `vault-system`
- Service accounts with appropriate RBAC
- Network policies support in cluster

## Implementation Steps

### Phase 1: Certificate Infrastructure (mTLS)

#### Step 1: Create Security Namespace
```bash
kubectl create namespace pyairtable-system
kubectl create namespace vault-system
```

#### Step 2: Deploy Certificate Authority
```bash
# Apply CA configuration
kubectl apply -f security/mtls/certificate-authority.yaml

# Wait for CA generation
kubectl wait --for=condition=complete job/generate-ca-certificates -n pyairtable-system --timeout=300s

# Verify CA creation
kubectl get secret pyairtable-ca-key-pair -n pyairtable-system
```

#### Step 3: Generate Service Certificates
```bash
# Apply service certificate configuration
kubectl apply -f security/mtls/service-certificates.yaml

# Wait for certificate generation
kubectl wait --for=condition=complete job/generate-service-certificates -n pyairtable-system --timeout=600s

# Verify service certificates
kubectl get secrets -n pyairtable-system | grep -E "(api-gateway|auth-service|user-service)-tls"
```

#### Step 4: Configure mTLS in Services

**For Go Services:**
```go
// Add to main.go
import "path/to/security/mtls"

func main() {
    logger, _ := zap.NewProduction()
    config := mtls.DefaultMTLSConfig(logger)
    
    // Load TLS configuration
    tlsConfig, err := config.LoadTLSConfig()
    if err != nil {
        logger.Fatal("Failed to load TLS config", zap.Error(err))
    }
    
    // Create Fiber app with mTLS middleware
    app := fiber.New()
    app.Use(config.MTLSMiddleware())
    
    // Start server with TLS
    logger.Fatal("Server failed", zap.Error(app.ListenTLS(":8080", "", "")))
}
```

**For Python Services:**
```python
# Add to main.py
from security.mtls.python_mtls_client import MTLSConfig, MTLSClient

# Configure mTLS client
config = MTLSConfig()
client = MTLSClient(config)

# Make secure service calls
response = client.get("https://auth-service.pyairtable-system.svc.cluster.local/health")
```

### Phase 2: HashiCorp Vault Deployment

#### Step 1: Deploy Vault
```bash
# Apply Vault deployment
kubectl apply -f security/vault/vault-deployment.yaml

# Wait for Vault pods to be ready
kubectl wait --for=condition=ready pod -l app=vault -n vault-system --timeout=300s

# Check Vault status
kubectl exec vault-0 -n vault-system -- vault status
```

#### Step 2: Initialize and Unseal Vault
```bash
# Run initialization job
kubectl apply -f security/vault/vault-config-job.yaml

# Monitor initialization
kubectl logs job/vault-init -n vault-system -f

# Verify unsealing
kubectl exec vault-0 -n vault-system -- vault status | grep Sealed
```

#### Step 3: Configure Vault Policies and Auth
```bash
# Wait for configuration job
kubectl wait --for=condition=complete job/vault-configuration -n vault-system --timeout=600s

# Verify policies created
kubectl exec vault-0 -n vault-system -- vault policy list

# Test Kubernetes authentication
kubectl exec vault-0 -n vault-system -- vault auth list
```

#### Step 4: Integration in Services

**Go Service Integration:**
```go
// Add to service initialization
import "path/to/security/vault"

func initializeSecrets() {
    config := vault.DefaultConfig("auth-service")
    vaultClient, err := vault.NewVaultClient(config, logger)
    if err != nil {
        logger.Fatal("Failed to create Vault client", zap.Error(err))
    }
    
    // Get JWT secret
    jwtSecret, err := vaultClient.GetSecretString("pyairtable/data/jwt", "secret")
    if err != nil {
        logger.Fatal("Failed to get JWT secret", zap.Error(err))
    }
    
    // Use secret in application
    os.Setenv("JWT_SECRET", jwtSecret)
}
```

**Python Service Integration:**
```python
# Add to service initialization
from security.vault.python_vault_client import VaultSecretManager

# Initialize secret manager
with VaultSecretManager("llm-orchestrator") as secret_manager:
    # Get database URL with dynamic credentials
    db_url = secret_manager.get_database_url()
    
    # Get external API keys
    openai_key = secret_manager.get_external_api_key("openai")
    
    # Initialize application with secrets
    app.config['DATABASE_URL'] = db_url
    app.config['OPENAI_API_KEY'] = openai_key
```

### Phase 3: Database Row-Level Security

#### Step 1: Initialize Database Schema
```bash
# Connect to PostgreSQL as superuser
kubectl exec -it postgres-0 -n pyairtable-system -- psql -U postgres -d pyairtable

# Execute RLS schema
\i /path/to/security/database/row-level-security.sql

# Verify RLS policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE schemaname IN ('public', 'tenant_management');
```

#### Step 2: Create Application Database User
```sql
-- Create application role
CREATE ROLE pyairtable_app WITH LOGIN PASSWORD 'secure_generated_password';

-- Grant necessary permissions
GRANT pyairtable_app TO postgres;
GRANT CONNECT ON DATABASE pyairtable TO pyairtable_app;
GRANT USAGE ON SCHEMA public, tenant_management, security_audit TO pyairtable_app;

-- Set RLS enforcement
ALTER ROLE pyairtable_app SET row_security = on;
```

#### Step 3: Integration in Services

**Go Service Integration:**
```go
// Add to database initialization
import "path/to/security/database"

func initializeDatabase() {
    config := database.Config{
        ConnectionString: "postgres://pyairtable_app:password@postgres:5432/pyairtable?sslmode=require",
    }
    
    dbManager, err := database.NewDatabaseManager(config.ConnectionString, logger)
    if err != nil {
        logger.Fatal("Failed to initialize database", zap.Error(err))
    }
    
    // Create services with RLS
    userService := database.NewUserService(dbManager)
    workspaceService := database.NewWorkspaceService(dbManager)
}

// In request handlers
func getUsersHandler(c *fiber.Ctx) error {
    // Extract tenant context from JWT
    tenantID := extractTenantID(c)
    userID := extractUserID(c)
    role := extractRole(c)
    ip := c.IP()
    
    // Create tenant context
    ctx := database.WithTenantContext(c.Context(), tenantID, userID, role, ip)
    
    // Get users (automatically filtered by tenant)
    users, err := userService.GetUsers(ctx, 50, 0)
    if err != nil {
        return c.Status(500).JSON(fiber.Map{"error": err.Error()})
    }
    
    return c.JSON(users)
}
```

**Python Service Integration:**
```python
# Add to database initialization
from security.database.python_rls_client import DatabaseManager, UserService, TenantContext

# Initialize database manager
connection_params = {
    'host': 'postgres.pyairtable-system.svc.cluster.local',
    'database': 'pyairtable',
    'user': 'pyairtable_app',
    'password': vault_client.get_secret_value('pyairtable/data/database', 'password'),
    'sslmode': 'require'
}

db_manager = DatabaseManager(connection_params)
user_service = UserService(db_manager)

# In request handlers
@app.route('/users')
@jwt_required()
def get_users():
    # Extract tenant context from JWT
    claims = get_jwt()
    tenant_ctx = TenantContext(
        tenant_id=uuid.UUID(claims['tenant_id']),
        user_id=uuid.UUID(claims['user_id']),
        role=claims['role'],
        ip_address=request.remote_addr
    )
    
    # Get users (automatically filtered by tenant)
    users = user_service.get_users(tenant_ctx, limit=50)
    return jsonify([asdict(user) for user in users])
```

## Deployment Configuration

### Kubernetes Manifests Updates

#### Service Deployment with mTLS
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: pyairtable-system
spec:
  template:
    spec:
      containers:
      - name: auth-service
        image: pyairtable/auth-service:latest
        ports:
        - containerPort: 8081
          name: https
        env:
        - name: TLS_CERT_FILE
          value: "/etc/certs/tls.crt"
        - name: TLS_KEY_FILE
          value: "/etc/certs/tls.key"
        - name: CA_CERT_FILE
          value: "/etc/certs/ca.crt"
        volumeMounts:
        - name: service-certs
          mountPath: /etc/certs
          readOnly: true
        - name: vault-token
          mountPath: /var/run/secrets/vault
          readOnly: true
      volumes:
      - name: service-certs
        secret:
          secretName: auth-service-tls
      - name: vault-token
        projected:
          sources:
          - serviceAccountToken:
              path: token
              audience: vault
```

#### Service with Vault Integration
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: auth-service
  namespace: pyairtable-system
---
apiVersion: v1
kind: Service
metadata:
  name: auth-service
  namespace: pyairtable-system
spec:
  ports:
  - port: 443
    targetPort: 8081
    name: https
  selector:
    app: auth-service
  type: ClusterIP
```

### Docker Configuration

#### Dockerfile with Security Features
```dockerfile
FROM golang:1.21-alpine AS builder

# Install security tools
RUN apk add --no-cache ca-certificates git

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

FROM alpine:3.18

# Security: Create non-root user
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -s /bin/sh -D appuser

# Install CA certificates
RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy binary and set ownership
COPY --from=builder /app/main .
RUN chown appuser:appgroup main

# Switch to non-root user
USER appuser

EXPOSE 8080

CMD ["./main"]
```

## Security Validation

### Step 1: Test mTLS Connectivity
```bash
# Test service-to-service mTLS
kubectl exec -it api-gateway-0 -n pyairtable-system -- \
  curl --cert /etc/certs/tls.crt \
       --key /etc/certs/tls.key \
       --cacert /etc/certs/ca.crt \
       https://auth-service.pyairtable-system.svc.cluster.local/health
```

### Step 2: Validate Vault Integration
```bash
# Test Vault connectivity from service
kubectl exec -it auth-service-0 -n pyairtable-system -- \
  curl --cert /etc/certs/tls.crt \
       --key /etc/certs/tls.key \
       --cacert /etc/certs/ca.crt \
       https://vault.vault-system.svc.cluster.local:8200/v1/sys/health
```

### Step 3: Test RLS Isolation
```sql
-- Test tenant isolation
SELECT security.validate_tenant_isolation('tenant-uuid-here');

-- Verify audit logging
SELECT event_type, action, result, created_at 
FROM security_audit.audit_log 
WHERE tenant_id = 'tenant-uuid-here' 
ORDER BY created_at DESC 
LIMIT 10;
```

### Step 4: Security Monitoring
```bash
# Check security metrics
kubectl exec vault-0 -n vault-system -- \
  vault read sys/metrics

# Monitor audit logs
kubectl logs -l app=vault -n vault-system --tail=100 | grep audit

# Check database audit
kubectl exec postgres-0 -n pyairtable-system -- \
  psql -U postgres -d pyairtable -c "SELECT COUNT(*) FROM security_audit.audit_log WHERE created_at > NOW() - INTERVAL '1 hour';"
```

## Monitoring and Alerting

### Grafana Dashboards
- mTLS certificate expiration monitoring
- Vault health and token usage
- Database RLS policy violations
- Security event rates and patterns

### Prometheus Metrics
```yaml
# Example metrics to monitor
- vault_token_expiry_time
- tls_certificate_expiry_days
- database_connection_pool_active
- rls_policy_violations_total
- security_audit_events_total
```

### Alerting Rules
```yaml
groups:
- name: security-alerts
  rules:
  - alert: TLS Certificate Expiring
    expr: tls_certificate_expiry_days < 30
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "TLS certificate expiring soon"
      
  - alert: Vault Sealed
    expr: vault_sealed == 1
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Vault is sealed"
      
  - alert: RLS Policy Violation
    expr: increase(rls_policy_violations_total[5m]) > 0
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Row-Level Security policy violation detected"
```

## Maintenance and Operations

### Certificate Rotation
```bash
# Automated certificate rotation (monthly)
kubectl create job --from=cronjob/cert-rotation cert-rotation-$(date +%Y%m%d) -n pyairtable-system
```

### Vault Maintenance
```bash
# Backup Vault data
kubectl exec vault-0 -n vault-system -- vault operator raft snapshot save /tmp/backup.snap

# Rotate Vault tokens
kubectl exec vault-0 -n vault-system -- vault token renew -increment=2764800  # 32 days
```

### Database Maintenance
```sql
-- Archive old audit logs (weekly)
DELETE FROM security_audit.audit_log 
WHERE created_at < NOW() - INTERVAL '90 days';

-- Analyze RLS performance
ANALYZE public.users, public.workspaces, public.tables, public.records;
```

## Troubleshooting

### Common Issues

#### mTLS Connection Failures
```bash
# Check certificate validity
openssl x509 -in /etc/certs/tls.crt -text -noout

# Verify CA trust chain
openssl verify -CAfile /etc/certs/ca.crt /etc/certs/tls.crt
```

#### Vault Authentication Issues
```bash
# Check Kubernetes auth configuration
kubectl exec vault-0 -n vault-system -- vault auth list

# Test service account token
kubectl exec vault-0 -n vault-system -- vault write auth/kubernetes/login \
  role=auth-service \
  jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
```

#### RLS Policy Issues
```sql
-- Check current session variables
SELECT current_setting('app.current_tenant_id'), 
       current_setting('app.current_user_id'),
       current_setting('app.current_user_role');

-- Test RLS policies
SET app.current_tenant_id = 'test-tenant-id';
SELECT * FROM public.users;  -- Should only show tenant's users
```

## Security Compliance

This implementation addresses:

- **SOC 2 Type II**: Audit logging, access controls, encryption
- **GDPR**: Data isolation, audit trails, data encryption
- **HIPAA**: Encryption in transit/rest, access controls, audit logs
- **ISO 27001**: Risk management, security monitoring, incident response

## Support and Documentation

- **Repository**: `/Users/kg/IdeaProjects/pyairtable-compose/security/`
- **Monitoring**: Grafana dashboards in `/monitoring/`
- **Runbooks**: Located in `/docs/runbooks/`
- **Security Policies**: Available in `/security/policies/`

## Next Steps

1. **Implement** all three security components following this guide
2. **Test** thoroughly in staging environment
3. **Monitor** security metrics and audit logs
4. **Train** development teams on secure coding practices
5. **Schedule** regular security reviews and penetration testing

---

**Implementation Status**: Ready for Production Deployment  
**Security Level**: Enterprise-Grade  
**Compliance**: SOC 2, GDPR, HIPAA Ready  
**Deployment Target**: 3vantage Organization