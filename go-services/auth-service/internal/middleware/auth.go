package middleware

import (
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/pyairtable-compose/auth-service/internal/services"
	"go.uber.org/zap"
)

// AuthMiddleware provides JWT authentication middleware
type AuthMiddleware struct {
	logger      *zap.Logger
	authService *services.AuthService
}

// NewAuthMiddleware creates a new authentication middleware
func NewAuthMiddleware(logger *zap.Logger, authService *services.AuthService) *AuthMiddleware {
	return &AuthMiddleware{
		logger:      logger,
		authService: authService,
	}
}

// RequireAuth is middleware that validates JWT tokens
func (m *AuthMiddleware) RequireAuth(c *fiber.Ctx) error {
	// Get Authorization header
	authHeader := c.Get("Authorization")
	if authHeader == "" {
		m.logger.Warn("Missing Authorization header", zap.String("path", c.Path()))
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Missing Authorization header",
		})
	}

	// Extract token from Bearer scheme
	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 || parts[0] != "Bearer" {
		m.logger.Warn("Invalid Authorization header format", zap.String("path", c.Path()))
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Invalid Authorization header format",
		})
	}

	tokenString := parts[1]

	// Validate token
	claims, err := m.authService.ValidateToken(tokenString)
	if err != nil {
		m.logger.Warn("Token validation failed", zap.Error(err), zap.String("path", c.Path()))
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Invalid or expired token",
		})
	}

	// Store user information in context for downstream handlers
	c.Locals("userID", claims.UserID)
	c.Locals("userEmail", claims.Email)
	c.Locals("userRole", claims.Role)
	c.Locals("tenantID", claims.TenantID)
	c.Locals("claims", claims)

	return c.Next()
}

// RequireRole is middleware that validates user roles
func (m *AuthMiddleware) RequireRole(requiredRoles ...string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		userRole := c.Locals("userRole")
		if userRole == nil {
			m.logger.Error("User role not found in context - auth middleware not applied?")
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Internal server error",
			})
		}

		role := userRole.(string)
		
		// Check if user has required role
		for _, requiredRole := range requiredRoles {
			if role == requiredRole {
				return c.Next()
			}
		}

		m.logger.Warn("Insufficient permissions", 
			zap.String("userRole", role),
			zap.Strings("requiredRoles", requiredRoles),
			zap.String("path", c.Path()))

		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
			"error": "Insufficient permissions",
		})
	}
}

// RequireAdmin is middleware that requires admin role
func (m *AuthMiddleware) RequireAdmin(c *fiber.Ctx) error {
	return m.RequireRole("admin")(c)
}

// OptionalAuth is middleware that validates JWT tokens but doesn't require them
func (m *AuthMiddleware) OptionalAuth(c *fiber.Ctx) error {
	// Get Authorization header
	authHeader := c.Get("Authorization")
	if authHeader == "" {
		// No token provided, continue without setting user context
		return c.Next()
	}

	// Extract token from Bearer scheme
	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 || parts[0] != "Bearer" {
		// Invalid format, continue without setting user context
		return c.Next()
	}

	tokenString := parts[1]

	// Validate token
	claims, err := m.authService.ValidateToken(tokenString)
	if err != nil {
		// Invalid token, continue without setting user context
		return c.Next()
	}

	// Store user information in context
	c.Locals("userID", claims.UserID)
	c.Locals("userEmail", claims.Email)
	c.Locals("userRole", claims.Role)
	c.Locals("tenantID", claims.TenantID)
	c.Locals("claims", claims)

	return c.Next()
}

// GetUserFromContext retrieves user information from context
func GetUserFromContext(c *fiber.Ctx) (*services.UserContext, bool) {
	userID := c.Locals("userID")
	if userID == nil {
		return nil, false
	}

	return &services.UserContext{
		UserID:   userID.(string),
		Email:    c.Locals("userEmail").(string),
		Role:     c.Locals("userRole").(string),
		TenantID: c.Locals("tenantID").(string),
	}, true
}

// RateLimiter represents a simple rate limiter
type RateLimiter struct {
	mu       sync.Mutex
	requests map[string][]time.Time
	limit    int
	window   time.Duration
}

// NewRateLimiter creates a new rate limiter
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		requests: make(map[string][]time.Time),
		limit:    limit,
		window:   window,
	}
}

// IsAllowed checks if a request is allowed for the given key (usually IP address)
func (rl *RateLimiter) IsAllowed(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	windowStart := now.Add(-rl.window)

	// Get existing requests for this key
	requests := rl.requests[key]
	
	// Filter out old requests
	var validRequests []time.Time
	for _, reqTime := range requests {
		if reqTime.After(windowStart) {
			validRequests = append(validRequests, reqTime)
		}
	}

	// Check if we can add another request
	if len(validRequests) >= rl.limit {
		rl.requests[key] = validRequests
		return false
	}

	// Add current request
	validRequests = append(validRequests, now)
	rl.requests[key] = validRequests
	return true
}

// RateLimitMiddleware creates a rate limiting middleware
func RateLimitMiddleware(limiter *RateLimiter) fiber.Handler {
	return func(c *fiber.Ctx) error {
		key := c.IP()
		if !limiter.IsAllowed(key) {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Rate limit exceeded",
			})
		}
		return c.Next()
	}
}

// SecurityHeadersMiddleware adds security headers
func SecurityHeadersMiddleware() fiber.Handler {
	return func(c *fiber.Ctx) error {
		c.Set("X-Content-Type-Options", "nosniff")
		c.Set("X-Frame-Options", "DENY")
		c.Set("X-XSS-Protection", "1; mode=block")
		c.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		c.Set("Referrer-Policy", "strict-origin-when-cross-origin")
		return c.Next()
	}
}

// InputSizeMiddleware limits request body size
func InputSizeMiddleware(maxSize int) fiber.Handler {
	return func(c *fiber.Ctx) error {
		if int(c.Request().Header.ContentLength()) > maxSize {
			return c.Status(fiber.StatusRequestEntityTooLarge).JSON(fiber.Map{
				"error": "Request body too large",
			})
		}
		return c.Next()
	}
}