# PyAirtable Authentication Architecture
## Sprint 1 Priority: P0-S1-001 - End-to-End Authentication Flow

### Executive Summary
This document defines the comprehensive authentication architecture for PyAirtable, addressing the critical end-to-end authentication flow issue (P0-S1-001). The solution provides secure JWT-based authentication with Redis session management, proper CORS configuration, and seamless frontend-backend integration.

## 1. Current State Analysis

### Existing Components
- **Auth Service** (Go): Port 8001 - Basic JWT/bcrypt implementation ✅
- **API Gateway** (Go): Port 7000 - Route handling with middleware ✅
- **Platform Services** (Go): Port 7007 - User management endpoints ✅
- **Frontend** (React/TypeScript): Port 5173 - Login/Register UI components ✅
- **Database**: PostgreSQL with users table schema ✅
- **Redis**: Session storage ready ✅

### Critical Gaps Identified
1. **Frontend-Backend Disconnection**: Frontend API calls not connecting to auth endpoints
2. **CORS Misconfiguration**: Frontend (5173) → Backend (7000/7007) blocked
3. **JWT Secret Management**: Using placeholder secrets
4. **Session Management**: Redis integration incomplete
5. **Token Refresh Flow**: Not implemented in frontend
6. **Error Handling**: Inconsistent across services
7. **Route Protection**: Missing middleware integration

## 2. Authentication Flow Architecture

```mermaid
sequenceDiagram
    participant F as Frontend (5173)
    participant AG as API Gateway (7000)
    participant AS as Auth Service (8001)
    participant PS as Platform Services (7007)
    participant DB as PostgreSQL
    participant R as Redis

    %% Login Flow
    F->>AG: POST /api/v1/auth/login
    AG->>AS: POST /auth/login
    AS->>DB: Validate credentials
    AS->>R: Store refresh token
    AS->>AG: JWT + Refresh Token
    AG->>F: Auth response

    %% Protected Request Flow
    F->>AG: GET /api/v1/users/me (Bearer JWT)
    AG->>AG: Validate JWT middleware
    AG->>PS: Forward request
    PS->>DB: Get user data
    PS->>AG: User response
    AG->>F: Protected data

    %% Token Refresh Flow
    F->>AG: POST /api/v1/auth/refresh
    AG->>AS: POST /auth/refresh
    AS->>R: Validate refresh token
    AS->>R: Store new refresh token
    AS->>AG: New JWT + Refresh Token
    AG->>F: Refreshed tokens
```

## 3. JWT Token Strategy

### Token Structure
```json
{
  "access_token": {
    "user_id": "uuid",
    "email": "user@example.com",
    "role": "user|admin",
    "tenant_id": "uuid",
    "iat": 1734567890,
    "exp": 1734654290
  },
  "refresh_token": "base64_encoded_random_32_bytes"
}
```

### Token Lifecycle
- **Access Token TTL**: 24 hours (configurable)
- **Refresh Token TTL**: 7 days (configurable)
- **Algorithm**: HS256 (validated strictly)
- **Storage**: Access token in memory, Refresh token in Redis

### Secret Management
```yaml
Environment Variables Required:
- JWT_SECRET: 256-bit cryptographically secure key
- JWT_ACCESS_TTL: "24h"
- JWT_REFRESH_TTL: "168h"
```

## 4. Session Management with Redis

### Redis Schema
```redis
# Refresh tokens
refresh_token:{token_hash} -> user_id (TTL: 7 days)

# Active sessions (optional)
user_sessions:{user_id} -> SET of refresh_token_hashes (TTL: 7 days)

# Rate limiting
rate_limit:auth:{ip} -> count (TTL: 1 hour)
```

### Session Operations
1. **Store Refresh Token**: SHA256 hash as key, user_id as value
2. **Validate Refresh Token**: Check existence and TTL
3. **Invalidate Session**: Remove refresh token from Redis
4. **Cleanup**: Redis TTL handles automatic expiration

## 5. CORS Configuration

### API Gateway CORS Settings
```go
cors.Config{
    AllowOrigins: []string{
        "http://localhost:5173",    // Vite dev server
        "http://localhost:3000",    // Production frontend
        "https://pyairtable.app",   // Production domain
    },
    AllowMethods: []string{
        "GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH",
    },
    AllowHeaders: []string{
        "Origin", "Content-Type", "Accept", 
        "Authorization", "X-Request-ID", "X-API-Key",
    },
    AllowCredentials: true,
    MaxAge: 86400, // 24 hours preflight cache
}
```

### Frontend API Configuration
```typescript
const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:7000/api/v1'

// Axios instance with interceptors
axios.defaults.withCredentials = true
axios.interceptors.request.use(config => {
  const token = localStorage.getItem('auth_token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})
```

## 6. Database Schema Requirements

### Enhanced Users Table
```sql
-- Additional fields for security
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_attempts INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP WITH TIME ZONE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- Session tracking
CREATE TABLE IF NOT EXISTS user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_user_sessions_token_hash ON user_sessions(token_hash);
CREATE INDEX idx_user_sessions_expires_at ON user_sessions(expires_at);
```

### Migration Strategy
```sql
-- Migration script for existing data
UPDATE users SET 
    password_changed_at = created_at 
WHERE password_changed_at IS NULL;
```

## 7. API Endpoint Specifications

### Authentication Endpoints
```yaml
POST /api/v1/auth/login:
  description: User login
  request:
    email: string (required)
    password: string (required)
  response:
    access_token: string
    refresh_token: string
    token_type: "Bearer"
    expires_in: number
    user: UserObject
  errors:
    401: Invalid credentials
    423: Account locked
    500: Internal error

POST /api/v1/auth/register:
  description: User registration
  request:
    email: string (required)
    password: string (required, min 8 chars)
    first_name: string (required)
    last_name: string (required)
    tenant_id: string (optional)
  response:
    message: string
    user: UserObject
  errors:
    400: Validation error
    409: Email already exists

POST /api/v1/auth/refresh:
  description: Refresh access token
  request:
    refresh_token: string (required)
  response:
    access_token: string
    refresh_token: string
    expires_in: number
  errors:
    401: Invalid refresh token
    403: Token expired

POST /api/v1/auth/logout:
  description: Logout user
  headers:
    Authorization: Bearer {token}
  request:
    refresh_token: string (required)
  response:
    message: "Logged out successfully"
  errors:
    401: Invalid token

GET /api/v1/auth/me:
  description: Get current user
  headers:
    Authorization: Bearer {token}
  response:
    user: UserObject
  errors:
    401: Invalid or expired token
```

### Protected Endpoints Pattern
```yaml
All protected endpoints require:
  headers:
    Authorization: Bearer {access_token}
  middleware:
    - JWT validation
    - User existence check
    - Rate limiting
    - Request logging
```

## 8. Security Best Practices

### Password Security
```go
// bcrypt with cost 12 (recommended for 2024)
hash, err := bcrypt.GenerateFromPassword([]byte(password), 12)

// Password requirements
var passwordRegex = regexp.MustCompile(`^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$`)
```

### Rate Limiting Strategy
```yaml
Authentication endpoints:
  - Login: 5 attempts per IP per 15 minutes
  - Register: 3 attempts per IP per hour
  - Password reset: 3 attempts per email per hour

Protected endpoints:
  - General: 1000 requests per user per hour
  - Sensitive: 100 requests per user per hour
```

### JWT Security
```go
// Prevent algorithm confusion attacks
if token.Method != jwt.SigningMethodHS256 {
    return nil, errors.New("unexpected signing method: only HS256 allowed")
}

// Always validate expiration
if time.Now().Unix() > int64(exp) {
    return nil, ErrTokenExpired
}

// Secure secret generation
secret := make([]byte, 32)
rand.Read(secret)
jwtSecret := base64.StdEncoding.EncodeToString(secret)
```

### Session Security
```go
// Secure refresh token generation
func generateSecureToken() (string, error) {
    b := make([]byte, 32)
    _, err := rand.Read(b)
    if err != nil {
        return "", err
    }
    return base64.URLEncoding.EncodeToString(b), nil
}
```

## 9. Error Handling Strategy

### Standard Error Response Format
```json
{
  "error": "error_code",
  "message": "Human readable message",
  "details": "Additional context",
  "timestamp": "2024-01-15T10:30:00Z",
  "request_id": "uuid"
}
```

### Error Categories
```yaml
Authentication Errors:
  INVALID_CREDENTIALS: 401
  TOKEN_EXPIRED: 401
  TOKEN_INVALID: 401
  ACCOUNT_LOCKED: 423
  INSUFFICIENT_PERMISSIONS: 403

Validation Errors:
  MISSING_FIELD: 400
  INVALID_FORMAT: 400
  DUPLICATE_EMAIL: 409

System Errors:
  DATABASE_ERROR: 500
  REDIS_ERROR: 500
  RATE_LIMIT_EXCEEDED: 429
```

### Frontend Error Handling
```typescript
interface ApiError {
  error: string
  message: string
  details?: string
  timestamp: string
  request_id?: string
}

function handleAuthError(error: ApiError): void {
  switch (error.error) {
    case 'TOKEN_EXPIRED':
      // Attempt token refresh
      return refreshToken()
    case 'INVALID_CREDENTIALS':
      // Show login form error
      setError('Invalid email or password')
      break
    case 'ACCOUNT_LOCKED':
      // Show account locked message
      setError('Account temporarily locked. Please try again later.')
      break
    default:
      // Generic error handling
      setError(error.message || 'An error occurred')
  }
}
```

## 10. Testing Strategy

### Unit Tests Required
```yaml
Auth Service:
  - Password hashing/validation
  - JWT generation/validation
  - Refresh token operations
  - User registration/login logic

API Gateway:
  - JWT middleware functionality
  - CORS handling
  - Route protection
  - Error responses

Frontend:
  - Login/register form validation
  - Token storage/retrieval
  - API error handling
  - Route protection
```

### Integration Tests
```yaml
Authentication Flow:
  - Complete login journey
  - Token refresh cycle
  - Logout process
  - Protected route access

CORS Testing:
  - Preflight requests
  - Credential inclusion
  - Origin validation

Security Testing:
  - Invalid token handling
  - Expired token behavior
  - Rate limiting enforcement
  - SQL injection prevention
```

### Load Testing Scenarios
```yaml
Concurrent logins: 100 users/second
Token validation: 1000 requests/second
Database connection pooling under load
Redis performance with high session volume
```

## 11. Implementation Tasks for Agents

### 1. Backend Go Agent Tasks
```yaml
Priority: P0 (Critical Path)

Task 1: Fix API Gateway JWT Middleware
  - File: go-services/api-gateway/internal/middleware/auth.go
  - Action: Implement proper JWT validation
  - Integration: Connect to auth service validation endpoint

Task 2: Fix Auth Service CORS
  - File: go-services/auth-service/cmd/auth-service/main.go
  - Action: Update CORS origins to include localhost:5173
  - Config: Environment variable based configuration

Task 3: Implement Token Refresh Endpoint
  - File: go-services/auth-service/internal/handlers/auth.go
  - Action: Add RefreshToken handler
  - Redis: Implement refresh token storage/validation

Task 4: Secure JWT Secret Management
  - Files: All config.go files
  - Action: Generate and use proper JWT secrets
  - Environment: Add to docker-compose and .env files

Task 5: Implement Rate Limiting
  - File: go-services/api-gateway/internal/middleware/
  - Action: Add Redis-based rate limiting
  - Pattern: Per-IP for auth, per-user for protected routes
```

### 2. Frontend React Agent Tasks
```yaml
Priority: P0 (Critical Path)

Task 1: Connect Login Form to Backend
  - File: frontend/chat-ui/src/pages/LoginPage.tsx
  - Action: Replace mock with actual API calls
  - Integration: Use existing apiClient from lib/api.ts

Task 2: Implement Authentication Context
  - File: frontend/chat-ui/src/contexts/AuthContext.tsx (new)
  - Action: Create React context for auth state
  - Features: Login, logout, token refresh, user state

Task 3: Add Route Protection
  - File: frontend/chat-ui/src/components/ProtectedRoute.tsx (new)
  - Action: Wrapper component for protected routes
  - Redirect: Unauthenticated users to login

Task 4: Implement Token Refresh Logic
  - File: frontend/chat-ui/src/lib/api.ts
  - Action: Add axios interceptors for token refresh
  - Storage: Secure token storage with automatic cleanup

Task 5: Add Error Handling UI
  - Files: Login/Register pages
  - Action: Display authentication errors
  - UX: Toast notifications for errors
```

### 3. Database Agent Tasks
```yaml
Priority: P1 (Supporting)

Task 1: Run Security Migrations
  - File: migrations/auth/002_add_security_fields.sql (new)
  - Action: Add failed_login_attempts, locked_until columns
  - Safety: Backwards compatible changes only

Task 2: Create Sessions Table
  - File: migrations/auth/003_create_sessions_table.sql (new)
  - Action: User sessions tracking for security
  - Indexes: Performance optimization for lookups

Task 3: Add Data Validation Constraints
  - File: migrations/auth/004_add_constraints.sql (new)
  - Action: Email format, password requirements
  - Security: Prevent invalid data insertion
```

### 4. DevOps Agent Tasks
```yaml
Priority: P1 (Supporting)

Task 1: Generate Secure JWT Secrets
  - Files: .env, docker-compose.yml
  - Action: Generate 256-bit random secrets
  - Rotation: Document secret rotation process

Task 2: Update Docker Compose Networking
  - File: docker-compose.yml
  - Action: Ensure proper service communication
  - Ports: Verify port mappings for all services

Task 3: Add Health Checks
  - Files: All service Dockerfiles
  - Action: Implement comprehensive health checks
  - Monitoring: Ready for production deployment
```

## 12. Blocking Issues & Dependencies

### Critical Blockers
1. **JWT Secret Configuration**: Must be resolved before any testing
2. **CORS Origins**: Frontend cannot communicate with backend
3. **Service Discovery**: API Gateway needs to properly route to auth service
4. **Database Connections**: Connection strings must be environment-specific

### Dependencies Resolution
```yaml
Order of Implementation:
1. Fix environment configuration (JWT secrets, CORS)
2. Implement backend JWT middleware
3. Connect frontend to backend APIs
4. Add token refresh mechanism
5. Implement rate limiting and security features

Parallel Development:
- Database migrations can run alongside backend fixes
- Frontend context can be developed while backend is being fixed
- Security enhancements can be added after basic flow works
```

### Risk Mitigation
```yaml
Fallback Strategies:
- Mock authentication for development if backend blocked
- Feature flags for gradual authentication rollout
- Circuit breaker pattern for external auth service dependencies
- Graceful degradation if Redis session storage unavailable
```

## 13. Code Snippets for Critical Parts

### JWT Middleware Implementation
```go
// go-services/api-gateway/internal/middleware/auth.go
package middleware

import (
    "strings"
    "github.com/gofiber/fiber/v2"
    "github.com/golang-jwt/jwt/v5"
)

func JWTAuth(secret string) fiber.Handler {
    return func(c *fiber.Ctx) error {
        authHeader := c.Get("Authorization")
        if authHeader == "" {
            return c.Status(401).JSON(fiber.Map{
                "error": "MISSING_AUTH_HEADER",
                "message": "Authorization header required",
            })
        }

        tokenString := strings.TrimPrefix(authHeader, "Bearer ")
        if tokenString == authHeader {
            return c.Status(401).JSON(fiber.Map{
                "error": "INVALID_AUTH_FORMAT",
                "message": "Bearer token required",
            })
        }

        token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
            if token.Method != jwt.SigningMethodHS256 {
                return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
            }
            return []byte(secret), nil
        })

        if err != nil || !token.Valid {
            return c.Status(401).JSON(fiber.Map{
                "error": "INVALID_TOKEN",
                "message": "Invalid or expired token",
            })
        }

        claims, ok := token.Claims.(jwt.MapClaims)
        if !ok {
            return c.Status(401).JSON(fiber.Map{
                "error": "INVALID_CLAIMS",
                "message": "Invalid token claims",
            })
        }

        // Store user info in context
        c.Locals("user_id", claims["user_id"])
        c.Locals("email", claims["email"])
        c.Locals("role", claims["role"])
        c.Locals("tenant_id", claims["tenant_id"])

        return c.Next()
    }
}
```

### Frontend Authentication Context
```typescript
// frontend/chat-ui/src/contexts/AuthContext.tsx
import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react'
import { apiClient } from '@/lib/api'

interface User {
  id: string
  email: string
  first_name: string
  last_name: string
  role: string
}

interface AuthContextType {
  user: User | null
  isLoading: boolean
  isAuthenticated: boolean
  login: (email: string, password: string) => Promise<boolean>
  logout: () => void
  refreshToken: () => Promise<boolean>
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    // Check if user is authenticated on app load
    const token = localStorage.getItem('auth_token')
    if (token) {
      validateToken()
    } else {
      setIsLoading(false)
    }
  }, [])

  const validateToken = async () => {
    try {
      const response = await apiClient.request('/auth/me')
      if (response.success && response.data) {
        setUser(response.data)
      } else {
        localStorage.removeItem('auth_token')
        localStorage.removeItem('refresh_token')
      }
    } catch (error) {
      localStorage.removeItem('auth_token')
      localStorage.removeItem('refresh_token')
    } finally {
      setIsLoading(false)
    }
  }

  const login = async (email: string, password: string): Promise<boolean> => {
    try {
      const response = await apiClient.login({ email, password })
      if (response.success && response.data) {
        const { access_token, refresh_token, user: userData } = response.data
        
        localStorage.setItem('auth_token', access_token)
        localStorage.setItem('refresh_token', refresh_token)
        apiClient.setToken(access_token)
        
        setUser(userData)
        return true
      }
      return false
    } catch (error) {
      console.error('Login failed:', error)
      return false
    }
  }

  const logout = () => {
    localStorage.removeItem('auth_token')
    localStorage.removeItem('refresh_token')
    apiClient.setToken(null)
    setUser(null)
  }

  const refreshToken = async (): Promise<boolean> => {
    try {
      const refreshToken = localStorage.getItem('refresh_token')
      if (!refreshToken) return false

      const response = await apiClient.request('/auth/refresh', {
        method: 'POST',
        body: JSON.stringify({ refresh_token: refreshToken })
      })

      if (response.success && response.data) {
        const { access_token, refresh_token: newRefreshToken } = response.data
        
        localStorage.setItem('auth_token', access_token)
        localStorage.setItem('refresh_token', newRefreshToken)
        apiClient.setToken(access_token)
        
        return true
      }
      return false
    } catch (error) {
      logout()
      return false
    }
  }

  return (
    <AuthContext.Provider value={{
      user,
      isLoading,
      isAuthenticated: !!user,
      login,
      logout,
      refreshToken
    }}>
      {children}
    </AuthContext.Provider>
  )
}

export const useAuth = () => {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
```

### Environment Configuration Template
```bash
# .env.template
# JWT Configuration
JWT_SECRET=your_256_bit_secret_here_replace_in_production
JWT_ACCESS_TTL=24h
JWT_REFRESH_TTL=168h

# CORS Configuration
CORS_ORIGINS=http://localhost:5173,http://localhost:3000
CORS_METHODS=GET,POST,PUT,DELETE,OPTIONS,PATCH
CORS_HEADERS=Origin,Content-Type,Accept,Authorization,X-Request-ID
CORS_CREDENTIALS=true
CORS_MAX_AGE=86400

# Database
DATABASE_URL=postgres://postgres:password@localhost:5432/pyairtable_auth?sslmode=require

# Redis
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=your_redis_password

# Rate Limiting
RATE_LIMIT_AUTH_ATTEMPTS=5
RATE_LIMIT_AUTH_WINDOW=15m
RATE_LIMIT_GENERAL=1000
RATE_LIMIT_GENERAL_WINDOW=1h
```

## 14. Success Criteria & Validation

### Definition of Done
1. **Frontend Login**: User can log in from localhost:5173 ✓
2. **JWT Protection**: Protected routes require valid tokens ✓
3. **Token Refresh**: Automatic token refresh before expiration ✓
4. **CORS Resolution**: No CORS errors in browser console ✓
5. **Session Management**: Redis stores refresh tokens properly ✓
6. **Error Handling**: Graceful error messages for all failure cases ✓
7. **Rate Limiting**: Authentication endpoints protected from abuse ✓

### Testing Checklist
```yaml
Manual Testing:
- [ ] Register new user account
- [ ] Login with valid credentials
- [ ] Login with invalid credentials (error handling)
- [ ] Access protected route after login
- [ ] Token refresh when accessing protected route
- [ ] Logout functionality
- [ ] Rate limiting after multiple failed attempts

Automated Testing:
- [ ] Unit tests for JWT middleware
- [ ] Integration tests for auth flow
- [ ] CORS preflight request tests
- [ ] Database migration tests
- [ ] Performance tests under load
```

### Performance Benchmarks
```yaml
Response Times:
- Login: < 200ms (95th percentile)
- Token validation: < 50ms (95th percentile)
- Protected route access: < 100ms (95th percentile)

Throughput:
- Concurrent logins: 100/second
- Token validations: 1000/second
- Database connections: Pool of 20, max 100

Error Rates:
- Authentication errors: < 0.1% (excluding invalid credentials)
- CORS errors: 0%
- Database connection errors: < 0.01%
```

## 15. Post-Implementation Monitoring

### Key Metrics to Track
```yaml
Authentication Metrics:
- Login success/failure rates
- Token refresh frequency
- Session duration averages
- Failed login attempt patterns

Performance Metrics:
- Authentication endpoint response times
- Database query performance
- Redis operations latency
- Memory usage patterns

Security Metrics:
- Brute force attack attempts
- Invalid token frequency
- CORS violation attempts
- Rate limiting trigger events
```

### Alerting Strategy
```yaml
Critical Alerts:
- Authentication service down
- Database connection failures
- Redis unavailable
- High error rate (>5%)

Warning Alerts:
- Slow response times (>500ms)
- High memory usage (>80%)
- Rate limiting frequently triggered
- Unusual login patterns
```

---

## Implementation Priority: P0 - CRITICAL
**Sprint 1 Success depends on this architecture implementation**

**Next Steps:**
1. Generate secure JWT secrets and update environment configuration
2. Fix CORS settings in all services
3. Implement JWT middleware in API Gateway
4. Connect frontend forms to backend APIs
5. Test complete authentication flow

**Estimated Implementation Time:** 2-3 days with dedicated agent focus
**Risk Level:** Medium (well-defined architecture, clear implementation path)