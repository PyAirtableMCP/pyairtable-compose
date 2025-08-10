# API Gateway Authentication Implementation

This document describes the JWT middleware implementation for the PyAirtable API Gateway, based on the requirements in `AUTHENTICATION_ARCHITECTURE.md`.

## Implementation Summary

### ✅ Completed Features

1. **JWT Middleware** (`internal/middleware/jwt.go`)
   - Strict HS256 algorithm enforcement (prevents algorithm confusion attacks)
   - Proper token validation and expiration checking
   - Request context population with user information
   - Comprehensive error handling with structured responses

2. **CORS Configuration** (`internal/middleware/cors.go`)
   - Configured to allow frontend access from `localhost:5173` (Vite dev server)
   - Supports multiple origins including production domains
   - Proper preflight request handling
   - Credentials support enabled for authentication

3. **Redis-based Rate Limiting** (`internal/middleware/ratelimit_redis.go`)
   - Authentication endpoints: 5 attempts per IP per 15 minutes
   - Registration: 3 attempts per IP per hour
   - Protected endpoints: 1000 requests per user per hour
   - Sensitive endpoints: 100 requests per user per hour
   - Sliding window implementation using Redis

4. **Public Routes Whitelist**
   - `/api/auth/login`, `/api/auth/register`, `/api/v1/auth/*`
   - Health check endpoints: `/health`, `/ready`, `/live`, `/metrics`
   - Automatic bypass for public routes

5. **Error Response Format**
   - Consistent error structure with error codes, messages, timestamps
   - HTTP status codes: 401 (Unauthorized), 403 (Forbidden), 429 (Rate Limited)
   - Detailed logging for security monitoring

6. **Environment Configuration**
   - `.env.example` template with all required variables
   - JWT secret management from environment variables
   - Automatic JWT secret generation script

## File Structure

```
internal/middleware/
├── jwt.go              # Main JWT validation middleware
├── jwt_test.go         # Comprehensive test suite
├── cors.go             # CORS configuration
└── ratelimit_redis.go  # Redis-based rate limiting

scripts/
└── generate-jwt-secret.sh  # JWT secret generation utility

.env.example            # Environment configuration template
```

## Usage

### 1. Environment Setup

```bash
# Copy the environment template
cp .env.example .env

# Generate a secure JWT secret
./scripts/generate-jwt-secret.sh

# Update other configuration as needed
```

### 2. Middleware Integration

The middleware is automatically integrated in `main.go`:

```go
// Initialize JWT middleware
jwtMiddleware := middleware.NewJWTMiddleware(cfg.Auth.JWTSecret, logger)

// Apply to protected routes
protected := v1.Group("", jwtMiddleware.ValidateToken())
```

### 3. Public vs Protected Routes

**Public Routes (no authentication required):**
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/register` 
- `POST /api/v1/auth/refresh`
- `GET /health`, `/ready`, `/live`, `/metrics`

**Protected Routes (JWT required):**
- All other `/api/v1/*` endpoints
- User context automatically populated in request

### 4. Rate Limiting

Rate limits are automatically applied based on endpoint type:

- **Auth endpoints**: IP-based limiting
- **Protected endpoints**: User-based limiting
- **Redis required**: Falls back to no limiting if Redis unavailable

## Security Features

### JWT Token Validation
- **Algorithm**: Strict HS256 enforcement
- **Expiration**: Checked both by JWT library and explicitly
- **Secret**: Must be 256-bit cryptographically secure
- **Context**: User information stored in request context

### CORS Protection
- **Origins**: Whitelist-based origin validation
- **Credentials**: Enabled for authentication flows
- **Headers**: Restricted to required headers only

### Rate Limiting
- **Sliding Window**: Redis-based implementation
- **Differentiated**: Different limits for different endpoint types
- **Headers**: Rate limit information in response headers
- **Resilience**: Fail-open if Redis unavailable

### Error Handling
- **Structured**: Consistent JSON error format
- **Logging**: Detailed security event logging
- **Status Codes**: Appropriate HTTP status codes
- **Information Disclosure**: Minimal error information to prevent enumeration

## Testing

Run the test suite:

```bash
go test ./internal/middleware/ -v
```

Tests cover:
- Valid and invalid JWT tokens
- Public route bypassing
- Role-based authorization
- Error response formats
- Security boundary conditions

## Configuration

### Required Environment Variables

```bash
JWT_SECRET=your_256_bit_secret_here    # REQUIRED
REDIS_URL=redis://localhost:6379       # For rate limiting
CORS_ORIGINS=http://localhost:5173,... # Frontend URLs
```

### Optional Configuration

```bash
GATEWAY_SECURITY_RATE_LIMIT_ENABLED=true
GATEWAY_OBSERVABILITY_LOGGING_REQUEST_LOG=true
GATEWAY_FEATURES_GRACEFUL_SHUTDOWN=true
```

## Production Deployment

### Security Checklist

- [ ] Generate unique JWT secret per environment
- [ ] Set up secure Redis instance with authentication
- [ ] Configure proper CORS origins for production domains
- [ ] Enable request logging and monitoring
- [ ] Set up log aggregation for security events
- [ ] Configure rate limiting based on expected traffic
- [ ] Test authentication flow end-to-end

### Monitoring

Key metrics to monitor:
- Authentication success/failure rates
- Rate limiting trigger frequency
- JWT validation errors
- Redis connection health
- Response times for auth endpoints

## Integration with Auth Service

The API Gateway validates JWTs but delegates authentication to the Auth Service:

1. **Login Flow**: `POST /api/v1/auth/login` → Auth Service
2. **Token Validation**: API Gateway validates JWT locally
3. **User Context**: User information extracted from JWT claims
4. **Refresh**: `POST /api/v1/auth/refresh` → Auth Service

## Troubleshooting

### Common Issues

1. **"JWT_SECRET environment variable is required"**
   - Solution: Set JWT_SECRET in .env file

2. **"CORS error in browser"**
   - Solution: Verify CORS_ORIGINS includes frontend URL

3. **"Rate limit exceeded"**  
   - Solution: Check Redis connection and rate limit configuration

4. **"Invalid token"**
   - Solution: Ensure Auth Service uses same JWT secret and algorithm

### Debug Mode

Enable debug logging:
```bash
LOG_LEVEL=debug
```

This will log all authentication events for troubleshooting.

---

## Implementation Status: ✅ COMPLETE

All requirements from `AUTHENTICATION_ARCHITECTURE.md` have been implemented and tested:

- ✅ JWT middleware with HS256 validation
- ✅ CORS configuration for localhost:5173
- ✅ Redis-based rate limiting
- ✅ Public routes whitelist
- ✅ Structured error responses
- ✅ Environment-based secret management
- ✅ Comprehensive test coverage

The API Gateway is now ready for integration with the Auth Service and frontend applications.