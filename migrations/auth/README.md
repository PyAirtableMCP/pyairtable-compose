# PyAirtable Authentication Database Migrations

This directory contains the complete database migration system for PyAirtable's authentication architecture, implemented according to the specifications in `AUTHENTICATION_ARCHITECTURE.md`.

## 🚀 Quick Start

### Prerequisites
- PostgreSQL database running (via Docker Compose)
- Docker and Docker Compose installed

### 1. Start Database
```bash
cd /Users/kg/IdeaProjects/pyairtable-compose
docker-compose -f docker-compose.minimal.yml up -d postgres
```

### 2. Apply Migrations
```bash
cd migrations/auth
./run_migrations_docker.sh up
```

### 3. Verify Schema
```bash
./verify_schema_docker.sh
```

## 📊 Migration Overview

### Applied Migrations

| Version | Description | Status |
|---------|-------------|---------|
| 001 | Enhanced users table with authentication fields | ✅ Applied |
| 002 | Created user sessions table for JWT management | ✅ Applied |
| 003 | Created password reset tokens table | ✅ Applied |
| 004 | Created audit logs table for security events | ✅ Applied |
| 005 | Fixed audit trigger for existing schema compatibility | ✅ Applied |

## 🗄️ Database Schema

### Core Tables Created/Modified

#### 1. `users` (Enhanced existing table)
- **Purpose**: User accounts with authentication security features
- **Key Fields**: 
  - `failed_login_attempts` - Track failed login attempts
  - `account_locked_until` - Account lockout timestamp
  - `password_changed_at` - Password change tracking
- **Security Features**: Email validation, password requirements, account locking

#### 2. `user_sessions` 
- **Purpose**: JWT refresh token management and session tracking
- **Key Fields**:
  - `token_hash` - SHA256 hash of refresh token
  - `expires_at` - Session expiration
  - `revoked_at` - Manual session termination
  - `device_info` - Client device metadata
- **Features**: Automatic cleanup, concurrent session limits

#### 3. `password_reset_tokens`
- **Purpose**: Secure password recovery system  
- **Key Fields**:
  - `token_hash` - SHA256 hash of reset token
  - `attempts_count` - Prevent brute force attacks
  - `max_attempts` - Configurable attempt limits
- **Security**: Rate limiting, automatic expiration

#### 4. `audit_logs`
- **Purpose**: Comprehensive security event logging
- **Key Fields**:
  - `event_type` / `event_category` - Event classification
  - `risk_level` - Security risk assessment
  - `anomaly_score` - ML-ready anomaly detection
  - `metadata` - Flexible JSON event data
- **Features**: Automatic user change tracking, suspicious activity detection

## 🔧 Available Tools

### Migration Management
- `run_migrations_docker.sh` - Apply/rollback migrations via Docker
- `run_migrations.sh` - Direct PostgreSQL connection (requires psql client)
- `verify_schema_docker.sh` - Comprehensive schema verification

### User Management  
- `create_admin_user.sh` - Create initial admin users

### Commands
```bash
# Apply all migrations
./run_migrations_docker.sh up

# Apply specific migration
./run_migrations_docker.sh up 001

# Rollback migration
./run_migrations_docker.sh down 001

# Check status
./run_migrations_docker.sh status

# Verify schema
./verify_schema_docker.sh

# Create admin user
./create_admin_user.sh
```

## 🔐 Security Features Implemented

### Authentication Security
- ✅ Bcrypt password hashing (cost factor 12)
- ✅ Failed login attempt tracking
- ✅ Account lockout mechanism (5 attempts, 15-minute lockout)
- ✅ Password change timestamp tracking
- ✅ Email format validation constraints

### Session Security  
- ✅ JWT refresh token management via Redis-like table storage
- ✅ Session expiration and revocation
- ✅ Device and location tracking
- ✅ Concurrent session limits (10 per user)
- ✅ Automatic cleanup of expired sessions

### Password Recovery Security
- ✅ Secure token generation and hashing
- ✅ Rate limiting (3 attempts per user)
- ✅ Short expiration windows (1 hour max)
- ✅ Automatic token invalidation after use

### Audit & Monitoring
- ✅ Comprehensive security event logging
- ✅ Automatic user change tracking
- ✅ Risk level assessment
- ✅ Anomaly score tracking
- ✅ Suspicious activity detection functions

## 👨‍💼 Test Users Created

| Email | Password | Purpose |
|-------|----------|---------|
| admin@example.com | (existing) | Pre-existing admin user |
| test-admin@pyairtable.local | password123 | Testing authentication flows |

## 🔍 Database Functions Available

### Authentication Functions
- `handle_failed_login(email)` - Process failed login attempts
- `reset_failed_login_attempts(email)` - Clear failed attempts on success  
- `is_account_locked(email)` - Check account lock status

### Session Management Functions
- `create_user_session(...)` - Create new user session
- `validate_session(token_hash)` - Validate and refresh session
- `revoke_session(token_hash)` - Revoke specific session
- `revoke_all_user_sessions(user_id)` - Revoke all user sessions
- `cleanup_expired_sessions()` - Remove old sessions

### Password Reset Functions  
- `create_password_reset_token(...)` - Generate reset token
- `validate_password_reset_token(token_hash)` - Validate reset token
- `use_password_reset_token(token_hash, new_password)` - Reset password
- `revoke_user_reset_tokens(user_id)` - Cancel reset tokens

### Security & Audit Functions
- `log_security_event(...)` - Log security events
- `get_user_security_events(user_id)` - Get user's security history
- `detect_suspicious_activity()` - Find suspicious patterns
- `cleanup_old_audit_logs()` - Remove old audit data

## 📈 Performance Optimizations

### Indexes Created
- Email lookups: `idx_users_email`
- Failed login tracking: `idx_users_failed_attempts` 
- Session management: `idx_user_sessions_token_hash`, `idx_user_sessions_active`
- Audit queries: `idx_audit_logs_user_event_time`, `idx_audit_logs_security_events`
- Password reset: `idx_password_reset_tokens_active`

### Query Optimization
- Partial indexes for active records only
- Composite indexes for common query patterns  
- JSONB indexes for metadata searches
- Time-based indexes for cleanup operations

## 🛠️ Troubleshooting

### Common Issues

**Migration Fails**: 
```bash
# Check database connection
docker ps | grep postgres
# Verify logs
docker logs pyairtable-compose-postgres-1
```

**Schema Mismatch**:
```bash
# Check current schema
./verify_schema_docker.sh --detailed
# Compare with expected structure in migration files
```

**Permission Issues**:
```bash
# Ensure scripts are executable  
chmod +x *.sh
```

## 📋 Production Checklist

Before deploying to production:

- [ ] Change default admin passwords
- [ ] Generate secure JWT secrets (256-bit)
- [ ] Configure proper CORS origins  
- [ ] Set up log rotation for audit_logs table
- [ ] Configure monitoring alerts for high-risk events
- [ ] Test authentication flows end-to-end
- [ ] Verify backup and recovery procedures
- [ ] Review and adjust rate limiting thresholds
- [ ] Set up automated cleanup jobs for old tokens/sessions

## 🎯 Next Steps

1. **Frontend Integration**: Connect React components to authentication endpoints
2. **API Gateway**: Implement JWT middleware validation
3. **Rate Limiting**: Add Redis-based request rate limiting  
4. **Monitoring**: Set up alerts for security events
5. **Testing**: Create comprehensive authentication test suite

## 📚 References

- [AUTHENTICATION_ARCHITECTURE.md](../AUTHENTICATION_ARCHITECTURE.md) - Complete specification
- [PyAirtable Sprint 1 Requirements](../PYAIRTABLE_AGILE_SPRINT_PLAN.md)
- PostgreSQL 16 Documentation
- JWT Best Practices (RFC 7519)
- OWASP Authentication Guidelines

---

**Database Engineer**: Created for PyAirtable Sprint 1 Authentication Flow (P0-S1-001)
**Status**: ✅ Complete - Ready for backend service integration
**Next Phase**: Frontend-Backend Authentication Flow Testing