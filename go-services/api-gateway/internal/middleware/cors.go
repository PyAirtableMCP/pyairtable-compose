package middleware

import (
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/pyairtable/api-gateway/internal/config"
	"go.uber.org/zap"
)

// CORSMiddleware handles Cross-Origin Resource Sharing
type CORSMiddleware struct {
	config *config.Config
	logger *zap.Logger
}

func NewCORSMiddleware(cfg *config.Config, logger *zap.Logger) *CORSMiddleware {
	return &CORSMiddleware{
		config: cfg,
		logger: logger,
	}
}

// Configure returns a configured CORS middleware
func (cm *CORSMiddleware) Configure() fiber.Handler {
	return cors.New(cors.Config{
		AllowOrigins: strings.Join(cm.config.Security.CORS.AllowOrigins, ","),
		AllowMethods: strings.Join(cm.config.Security.CORS.AllowMethods, ","),
		AllowHeaders: strings.Join(cm.config.Security.CORS.AllowHeaders, ","),
		AllowCredentials: cm.config.Security.CORS.AllowCredentials,
		MaxAge: cm.config.Security.CORS.MaxAge,
		
		// Handle preflight requests explicitly
		AllowOriginsFunc: func(origin string) bool {
			// Allow all origins in development
			if cm.config.Server.Environment == "development" {
				cm.logger.Debug("CORS: Allowing origin in development", zap.String("origin", origin))
				return true
			}
			
			// Check against configured origins
			for _, allowedOrigin := range cm.config.Security.CORS.AllowOrigins {
				if allowedOrigin == "*" {
					return true
				}
				if allowedOrigin == origin {
					cm.logger.Debug("CORS: Origin allowed", zap.String("origin", origin))
					return true
				}
				// Support wildcard matching for subdomains
				if strings.HasPrefix(allowedOrigin, "*.") {
					domain := strings.TrimPrefix(allowedOrigin, "*.")
					if strings.HasSuffix(origin, domain) {
						cm.logger.Debug("CORS: Origin allowed via wildcard", zap.String("origin", origin))
						return true
					}
				}
			}
			
			cm.logger.Warn("CORS: Origin rejected", zap.String("origin", origin))
			return false
		},
		
		// Custom error handler for CORS failures
		ErrorHandler: func(c *fiber.Ctx, err error) error {
			cm.logger.Warn("CORS error", 
				zap.Error(err),
				zap.String("origin", c.Get("Origin")),
				zap.String("method", c.Method()),
				zap.String("path", c.Path()))
			
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
				"error": "CORS policy violation",
			})
		},
		
		// Add timing information
		ExposeHeaders: []string{
			"X-Request-ID",
			"X-Response-Time", 
			"X-Rate-Limit-Remaining",
			"X-Rate-Limit-Reset",
		},
	})
}

// AuthCORS provides specific CORS handling for authentication endpoints
func (cm *CORSMiddleware) AuthCORS() fiber.Handler {
	return cors.New(cors.Config{
		AllowOrigins: strings.Join(cm.config.Security.CORS.AllowOrigins, ","),
		AllowMethods: "GET,POST,PUT,PATCH,DELETE,OPTIONS",
		AllowHeaders: "Content-Type,Authorization,X-API-Key,X-Requested-With,X-CSRF-Token",
		AllowCredentials: true,
		MaxAge: 600, // 10 minutes for auth endpoints
		
		AllowOriginsFunc: func(origin string) bool {
			// More restrictive for auth endpoints
			if cm.config.Server.Environment == "development" {
				// Only allow localhost in development for auth
				return strings.HasPrefix(origin, "http://localhost:") || 
				       strings.HasPrefix(origin, "https://localhost:") ||
				       origin == "http://localhost:3000" ||
				       origin == "https://localhost:3000"
			}
			
			for _, allowedOrigin := range cm.config.Security.CORS.AllowOrigins {
				if allowedOrigin == origin {
					return true
				}
			}
			return false
		},
	})
}

// Preflight handles OPTIONS requests for complex CORS scenarios
func (cm *CORSMiddleware) Preflight() fiber.Handler {
	return func(c *fiber.Ctx) error {
		if c.Method() == "OPTIONS" {
			origin := c.Get("Origin")
			
			// Log preflight requests
			cm.logger.Debug("CORS preflight request",
				zap.String("origin", origin),
				zap.String("method", c.Get("Access-Control-Request-Method")),
				zap.String("headers", c.Get("Access-Control-Request-Headers")))
			
			// Set appropriate headers
			c.Set("Access-Control-Allow-Origin", origin)
			c.Set("Access-Control-Allow-Credentials", "true")
			c.Set("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
			c.Set("Access-Control-Allow-Headers", "Content-Type,Authorization,X-API-Key,X-Requested-With,X-CSRF-Token")
			c.Set("Access-Control-Max-Age", "600")
			
			return c.SendStatus(fiber.StatusOK)
		}
		
		return c.Next()
	}
}