package middleware

import (
	"fmt"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
	"go.uber.org/zap"
)

// JWTClaims represents the structure of JWT claims as per AUTHENTICATION_ARCHITECTURE.md
type JWTClaims struct {
	UserID   string `json:"user_id"`
	Email    string `json:"email"`
	Role     string `json:"role"`
	TenantID string `json:"tenant_id"`
	jwt.RegisteredClaims
}

// JWTMiddleware handles JWT token validation with strict HS256 algorithm enforcement
type JWTMiddleware struct {
	jwtSecret []byte
	logger    *zap.Logger
}

// NewJWTMiddleware creates a new JWT middleware instance
func NewJWTMiddleware(jwtSecret string, logger *zap.Logger) *JWTMiddleware {
	if jwtSecret == "" {
		logger.Fatal("JWT_SECRET environment variable is required")
	}
	return &JWTMiddleware{
		jwtSecret: []byte(jwtSecret),
		logger:    logger,
	}
}

// ValidateToken validates JWT tokens with strict security requirements
func (j *JWTMiddleware) ValidateToken() fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Skip authentication for public routes
		if j.isPublicRoute(c.Path()) {
			return c.Next()
		}

		// Get Authorization header
		authHeader := c.Get("Authorization")
		if authHeader == "" {
			j.logger.Debug("Missing Authorization header", 
				zap.String("path", c.Path()),
				zap.String("ip", c.IP()))
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error":     "MISSING_AUTH_HEADER",
				"message":   "Authorization header required",
				"timestamp": time.Now().Unix(),
				"path":      c.Path(),
			})
		}

		// Extract Bearer token
		tokenString := strings.TrimPrefix(authHeader, "Bearer ")
		if tokenString == authHeader {
			j.logger.Debug("Invalid Authorization header format", 
				zap.String("path", c.Path()),
				zap.String("ip", c.IP()))
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error":     "INVALID_AUTH_FORMAT",
				"message":   "Bearer token required",
				"timestamp": time.Now().Unix(),
				"path":      c.Path(),
			})
		}

		// Parse and validate token with strict HS256 enforcement
		token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
			// Prevent algorithm confusion attacks - only allow HS256
			if token.Method != jwt.SigningMethodHS256 {
				j.logger.Warn("Unexpected signing method detected",
					zap.String("method", fmt.Sprintf("%v", token.Header["alg"])),
					zap.String("ip", c.IP()))
				return nil, fmt.Errorf("unexpected signing method: only HS256 allowed")
			}
			return j.jwtSecret, nil
		})

		if err != nil {
			j.logger.Debug("Token validation failed",
				zap.String("path", c.Path()),
				zap.String("ip", c.IP()),
				zap.Error(err))
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error":     "INVALID_TOKEN",
				"message":   "Invalid or expired token",
				"timestamp": time.Now().Unix(),
				"path":      c.Path(),
			})
		}

		// Extract and validate claims
		claims, ok := token.Claims.(*JWTClaims)
		if !ok || !token.Valid {
			j.logger.Debug("Invalid token claims",
				zap.String("path", c.Path()),
				zap.String("ip", c.IP()))
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error":     "INVALID_CLAIMS",
				"message":   "Invalid token claims",
				"timestamp": time.Now().Unix(),
				"path":      c.Path(),
			})
		}

		// Explicit expiration check (defense in depth)
		if time.Now().Unix() > claims.ExpiresAt.Unix() {
			j.logger.Debug("Token expired",
				zap.String("path", c.Path()),
				zap.String("user_id", claims.UserID),
				zap.Int64("expired_at", claims.ExpiresAt.Unix()))
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error":     "TOKEN_EXPIRED",
				"message":   "Token expired",
				"timestamp": time.Now().Unix(),
				"path":      c.Path(),
			})
		}

		// Store user information in request context
		c.Locals("user_id", claims.UserID)
		c.Locals("email", claims.Email)
		c.Locals("role", claims.Role)
		c.Locals("tenant_id", claims.TenantID)
		c.Locals("jwt_claims", claims)

		// Add user context headers for backend services
		c.Set("X-User-ID", claims.UserID)
		c.Set("X-User-Email", claims.Email)
		c.Set("X-User-Role", claims.Role)
		if claims.TenantID != "" {
			c.Set("X-Tenant-ID", claims.TenantID)
		}

		j.logger.Debug("JWT authentication successful",
			zap.String("user_id", claims.UserID),
			zap.String("email", claims.Email),
			zap.String("path", c.Path()))

		return c.Next()
	}
}

// RequireRole middleware ensures the user has the required role
func (j *JWTMiddleware) RequireRole(role string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		userRole := c.Locals("role")
		if userRole == nil {
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
				"error":     "NO_ROLE",
				"message":   "No role found in token",
				"timestamp": time.Now().Unix(),
				"path":      c.Path(),
			})
		}

		if userRole.(string) != role {
			j.logger.Warn("Insufficient permissions",
				zap.String("user_id", c.Locals("user_id").(string)),
				zap.String("user_role", userRole.(string)),
				zap.String("required_role", role),
				zap.String("path", c.Path()))
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
				"error":     "INSUFFICIENT_PERMISSIONS",
				"message":   "Insufficient permissions",
				"timestamp": time.Now().Unix(),
				"path":      c.Path(),
			})
		}

		return c.Next()
	}
}

// isPublicRoute determines if authentication should be skipped for a path
func (j *JWTMiddleware) isPublicRoute(path string) bool {
	// Public routes as specified in AUTHENTICATION_ARCHITECTURE.md
	publicPaths := []string{
		"/api/auth/login",
		"/api/auth/register",
		"/api/v1/auth/login",
		"/api/v1/auth/register",
		"/api/v1/auth/refresh",
		"/health",
		"/ready",
		"/live",
		"/metrics",
	}

	for _, publicPath := range publicPaths {
		if strings.HasPrefix(path, publicPath) {
			return true
		}
	}

	return false
}

// GetJWTClaimsFromContext extracts JWT claims from fiber context
func GetJWTClaimsFromContext(c *fiber.Ctx) (*JWTClaims, bool) {
	claims, ok := c.Locals("jwt_claims").(*JWTClaims)
	return claims, ok
}
