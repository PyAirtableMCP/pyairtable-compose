package middleware

import (
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"go.uber.org/zap"
)

// CORSMiddleware handles Cross-Origin Resource Sharing configuration
type CORSMiddleware struct {
	logger *zap.Logger
}

// NewCORSMiddleware creates a new CORS middleware instance
func NewCORSMiddleware(logger *zap.Logger) *CORSMiddleware {
	return &CORSMiddleware{
		logger: logger,
	}
}

// GetCORSHandler returns a configured CORS handler for the API Gateway
// This configuration matches the requirements in AUTHENTICATION_ARCHITECTURE.md
func (cm *CORSMiddleware) GetCORSHandler() fiber.Handler {
	return cors.New(cors.Config{
		AllowOrigins: strings.Join([]string{
			"http://localhost:5173",    // Vite dev server (frontend)
			"http://localhost:3000",    // Alternative frontend port
			"https://pyairtable.app",   // Production domain
			"https://*.pyairtable.app", // Subdomains
		}, ","),
		AllowMethods: strings.Join([]string{
			"GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH",
		}, ","),
		AllowHeaders: strings.Join([]string{
			"Origin",
			"Content-Type", 
			"Accept",
			"Authorization", // Required for JWT Bearer tokens
			"X-Request-ID",
			"X-API-Key",
			"X-Trace-ID",
		}, ","),
		AllowCredentials: true, // Required for cookies and authentication
		MaxAge:          86400, // 24 hours preflight cache
		Next: func(c *fiber.Ctx) bool {
			// Skip CORS for same-origin requests
			origin := c.Get("Origin")
			return origin == ""
		},
	})
}

// ValidateOrigin checks if the request origin is allowed
func (cm *CORSMiddleware) ValidateOrigin(origin string) bool {
	allowedOrigins := []string{
		"http://localhost:5173",
		"http://localhost:3000", 
		"https://pyairtable.app",
	}

	for _, allowed := range allowedOrigins {
		if origin == allowed || strings.HasSuffix(allowed, "*.pyairtable.app") {
			return true
		}
	}

	cm.logger.Warn("CORS: Origin not allowed", zap.String("origin", origin))
	return false
}

// HandlePreflight handles preflight OPTIONS requests
func (cm *CORSMiddleware) HandlePreflight() fiber.Handler {
	return func(c *fiber.Ctx) error {
		if c.Method() == "OPTIONS" {
			origin := c.Get("Origin")
			if origin != "" && cm.ValidateOrigin(origin) {
				c.Set("Access-Control-Allow-Origin", origin)
				c.Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,PATCH,OPTIONS")
				c.Set("Access-Control-Allow-Headers", "Origin,Content-Type,Accept,Authorization,X-Request-ID,X-API-Key")
				c.Set("Access-Control-Allow-Credentials", "true")
				c.Set("Access-Control-Max-Age", "86400")
				
				cm.logger.Debug("CORS preflight handled", 
					zap.String("origin", origin),
					zap.String("method", c.Get("Access-Control-Request-Method")))
				
				return c.SendStatus(fiber.StatusNoContent)
			}
			
			cm.logger.Warn("CORS preflight rejected", zap.String("origin", origin))
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
				"error":   "CORS_NOT_ALLOWED",
				"message": "Origin not allowed",
			})
		}
		
		return c.Next()
	}
}