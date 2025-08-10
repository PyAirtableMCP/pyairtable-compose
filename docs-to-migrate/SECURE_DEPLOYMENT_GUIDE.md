# PyAirtable Secure Deployment Guide

## 🔒 Security-First Authentication System Deployment

This guide provides comprehensive instructions for deploying the PyAirtable authentication system with enterprise-grade security configurations.

## 📋 Quick Start Checklist

- [ ] Generate secure environment variables using `./generate-secure-env.sh`
- [ ] Validate configuration using `./validate-environment.sh`
- [ ] Review security settings in docker-compose.yml
- [ ] Test service connectivity
- [ ] Deploy with monitoring

## 🛡️ Security Overview

### Implemented Security Features

1. **256-bit Encryption Standards**
   - JWT secrets: 256-bit base64 encoded
   - API keys: 256-bit hex encoded
   - Database passwords: 256-bit secure strings
   - Redis authentication: 128-bit passwords

2. **Database Security**
   - PostgreSQL with SCRAM-SHA-256 authentication
   - Connection timeouts and SSL support
   - Audit logging enabled
   - Row-level security ready

3. **Redis Security**
   - Password authentication required
   - Custom port (6380) instead of default (6379)
   - Memory limits and eviction policies
   - Persistence with encryption at rest

4. **Network Security**
   - Internal Docker networking only
   - No exposed database ports in production
   - CORS restrictions per environment
   - Health check authentication

5. **Application Security**
   - JWT tokens with short expiration times
   - Session management with Redis
   - Password hashing with bcrypt (12+ rounds)
   - API key validation on all endpoints

## 🚀 Deployment Steps

### 1. Environment Setup

```bash
# Clone the repository
git clone <repository-url>
cd pyairtable-compose

# Generate secure environment variables
./generate-secure-env.sh --all

# This creates:
# - .env (development)
# - .env.production (production)
# - .env.staging (staging)
```

### 2. Configure External API Credentials

Edit the generated environment files and replace placeholder values:

```bash
# Edit .env for development
nano .env

# Replace these placeholders:
AIRTABLE_TOKEN=your_actual_airtable_token_here
AIRTABLE_BASE=your_actual_base_id_here
GEMINI_API_KEY=your_actual_gemini_api_key_here
```

### 3. Validate Configuration

```bash
# Validate all environment variables
./validate-environment.sh

# Should show all green checkmarks for required variables
```

### 4. Security Review

Verify security settings in your environment:

```bash
# Check password strength
echo "JWT Secret length: ${#JWT_SECRET}"
echo "API Key length: ${#API_KEY}"
echo "Database Password length: ${#POSTGRES_PASSWORD}"

# Verify Redis authentication
docker-compose config | grep -A 5 "redis:"
```

### 5. Deploy Services

```bash
# Start all services
docker-compose up -d

# Monitor startup logs
docker-compose logs -f

# Check service health
docker-compose ps
```

## 🔐 Environment-Specific Configurations

### Development Environment

**File:** `.env`

```bash
# Security settings (relaxed for development)
REQUIRE_API_KEY=true
REQUIRE_HTTPS=false
PASSWORD_MIN_LENGTH=8
PASSWORD_HASH_ROUNDS=10
JWT_EXPIRES_IN=24h
SESSION_TIMEOUT=86400

# CORS (permissive for local development)
CORS_ORIGINS=http://localhost:3000,http://localhost:5173,http://localhost:7000
```

### Staging Environment

**File:** `.env.staging`

```bash
# Security settings (balanced)
REQUIRE_API_KEY=true
REQUIRE_HTTPS=true
PASSWORD_MIN_LENGTH=10
PASSWORD_HASH_ROUNDS=12
JWT_EXPIRES_IN=2h
SESSION_TIMEOUT=7200

# CORS (restricted to staging domains)
CORS_ORIGINS=https://staging.yourdomain.com,https://staging-api.yourdomain.com
```

### Production Environment

**File:** `.env.production`

```bash
# Security settings (maximum security)
REQUIRE_API_KEY=true
REQUIRE_HTTPS=true
PASSWORD_MIN_LENGTH=12
PASSWORD_HASH_ROUNDS=14
JWT_EXPIRES_IN=1h
SESSION_TIMEOUT=3600

# CORS (strict whitelist)
CORS_ORIGINS=https://yourdomain.com,https://api.yourdomain.com
```

## 🗄️ Database Security

### PostgreSQL Configuration

The deployment includes hardened PostgreSQL settings:

```yaml
# Secure authentication
POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256 --auth-local=scram-sha-256 --data-checksums"

# Performance and security tuning
command: >
  postgres
  -c shared_preload_libraries=pg_stat_statements
  -c max_connections=200
  -c log_connections=on
  -c log_statement=mod
  -c ssl=off  # Enable SSL in production
```

### Redis Configuration

Redis is configured with enhanced security:

```yaml
command: >
  redis-server
  --requirepass ${REDIS_PASSWORD}
  --port 6380                    # Non-default port
  --protected-mode yes           # Security enabled
  --maxmemory 256mb             # Memory limit
  --maxmemory-policy allkeys-lru # Eviction policy
  --appendonly yes              # Persistence
```

## 🔍 Health Monitoring

### Service Health Checks

All services include comprehensive health checks:

```yaml
healthcheck:
  test: [
    "CMD-SHELL",
    "curl -f -H 'Accept: application/json' -H 'X-API-Key: ${API_KEY}' http://localhost:7007/health"
  ]
  interval: 30s
  timeout: 15s
  retries: 3
  start_period: 60s
```

### Monitor Service Status

```bash
# Check all service health
docker-compose ps

# View detailed health status
docker inspect $(docker-compose ps -q) | jq '.[].State.Health'

# Monitor logs for security events
docker-compose logs -f | grep -i "auth\|security\|error"
```

## 🛠️ Troubleshooting

### Common Issues

1. **Service Won't Start**
   ```bash
   # Check logs
   docker-compose logs [service-name]
   
   # Verify environment variables
   ./validate-environment.sh
   ```

2. **Authentication Failures**
   ```bash
   # Check JWT secret configuration
   echo $JWT_SECRET | base64 -d | wc -c  # Should be 32+ bytes
   
   # Verify API key format
   echo $API_KEY | grep -E "^pya_[a-f0-9]{64}$"
   ```

3. **Database Connection Issues**
   ```bash
   # Test PostgreSQL connection
   docker-compose exec postgres pg_isready -U $POSTGRES_USER
   
   # Check Redis authentication
   docker-compose exec redis redis-cli -a $REDIS_PASSWORD ping
   ```

4. **Network Connectivity**
   ```bash
   # Test internal networking
   docker-compose exec api-gateway curl -f http://postgres:5432
   docker-compose exec api-gateway curl -f http://redis:6380
   ```

### Security Validation

```bash
# Validate password strength
./scripts/validate-passwords.sh

# Check for exposed ports
netstat -tulpn | grep -E "(5432|6379|6380)"

# Audit environment files for secrets
grep -r "your_actual_" .env*
```

## 🚨 Security Checklist

### Pre-Deployment

- [ ] All placeholder credentials replaced with real values
- [ ] JWT secrets are 256-bit (32+ characters base64)
- [ ] Database passwords are 256-bit (64+ characters hex)
- [ ] Redis authentication enabled
- [ ] CORS origins restricted to known domains
- [ ] HTTPS enabled for staging/production
- [ ] Audit logging enabled

### Post-Deployment

- [ ] All services healthy and responding
- [ ] Authentication endpoints working
- [ ] Database connections secure
- [ ] Redis authentication working
- [ ] Health checks passing
- [ ] Logs show no security warnings
- [ ] API keys validated on all endpoints

### Production-Specific

- [ ] SSL certificates configured
- [ ] Database backups scheduled
- [ ] Monitoring alerts configured
- [ ] Log aggregation set up
- [ ] Security scanning scheduled
- [ ] Incident response plan ready

## 📊 Performance Tuning

### Database Optimization

```sql
-- Create indexes for authentication queries
CREATE INDEX idx_users_email_hash ON users USING hash (email);
CREATE INDEX idx_sessions_token_hash ON sessions USING hash (token);
CREATE INDEX idx_audit_logs_timestamp ON audit_logs (timestamp);
```

### Redis Optimization

```bash
# Memory usage monitoring
redis-cli -a $REDIS_PASSWORD info memory

# Session cleanup
redis-cli -a $REDIS_PASSWORD eval "return redis.call('del', unpack(redis.call('keys', 'session:*')))" 0
```

## 🔄 Backup and Recovery

### Database Backups

```bash
# Create backup
docker-compose exec postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB > backup.sql

# Restore from backup
docker-compose exec -T postgres psql -U $POSTGRES_USER $POSTGRES_DB < backup.sql
```

### Redis Backups

```bash
# Save Redis snapshot
docker-compose exec redis redis-cli -a $REDIS_PASSWORD bgsave

# Copy backup file
docker cp $(docker-compose ps -q redis):/data/dump.rdb ./redis-backup.rdb
```

## 📞 Support and Maintenance

### Log Locations

- **Application Logs:** `docker-compose logs -f [service]`
- **PostgreSQL Logs:** Inside container at `/var/log/postgresql/`
- **Redis Logs:** Available via `docker-compose logs redis`

### Regular Maintenance

1. **Weekly:**
   - Review security logs
   - Check service health
   - Update dependencies

2. **Monthly:**
   - Rotate secrets (if required)
   - Performance analysis
   - Security audit

3. **Quarterly:**
   - Penetration testing
   - Infrastructure review
   - Disaster recovery test

## 🔗 Additional Resources

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [PostgreSQL Security](https://www.postgresql.org/docs/current/security.html)
- [Redis Security](https://redis.io/topics/security)
- [JWT Best Practices](https://tools.ietf.org/html/rfc8725)

---

**⚠️ Important Security Notes:**

1. Never commit `.env` files containing real credentials to version control
2. Use different secrets for each environment
3. Regularly rotate API keys and passwords
4. Monitor logs for suspicious activity
5. Keep all components updated with security patches

For questions or issues, please refer to the troubleshooting section or contact the development team.