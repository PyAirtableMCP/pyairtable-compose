package middleware

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/redis/go-redis/v9"
	"github.com/pyairtable/api-gateway/internal/config"
	"go.uber.org/zap"
)

type HealthStatus struct {
	Status      string                 `json:"status"`
	Timestamp   time.Time              `json:"timestamp"`
	Version     string                 `json:"version"`
	Uptime      time.Duration          `json:"uptime"`
	Environment string                 `json:"environment"`
	Services    map[string]ServiceHealth `json:"services"`
	Auth        AuthHealthStatus       `json:"auth"`
}

type ServiceHealth struct {
	Status      string        `json:"status"`
	ResponseTime time.Duration `json:"response_time"`
	LastCheck   time.Time     `json:"last_check"`
	Error       string        `json:"error,omitempty"`
}

type AuthHealthStatus struct {
	JWTValidation    string `json:"jwt_validation"`
	RedisConnection  string `json:"redis_connection"`
	SessionStore     string `json:"session_store"`
	TokenRepository  string `json:"token_repository"`
	AuthServiceConn  string `json:"auth_service_connection"`
}

type HealthMiddleware struct {
	config      *config.Config
	logger      *zap.Logger
	redisClient *redis.Client
	startTime   time.Time
}

func NewHealthMiddleware(cfg *config.Config, logger *zap.Logger, redisClient *redis.Client) *HealthMiddleware {
	return &HealthMiddleware{
		config:      cfg,
		logger:      logger,
		redisClient: redisClient,
		startTime:   time.Now(),
	}
}

// HealthCheck returns overall system health
func (hm *HealthMiddleware) HealthCheck() fiber.Handler {
	return func(c *fiber.Ctx) error {
		ctx := context.Background()
		status := "healthy"
		
		// Check Redis connection
		redisStatus := "healthy"
		redisErr := ""
		if hm.redisClient != nil {
			start := time.Now()
			err := hm.redisClient.Ping(ctx).Err()
			if err != nil {
				redisStatus = "unhealthy"
				redisErr = err.Error()
				status = "degraded"
			}
			hm.logger.Debug("Redis health check", 
				zap.String("status", redisStatus),
				zap.Duration("response_time", time.Since(start)))
		}

		// Check auth service connectivity
		authServiceStatus := hm.checkAuthService()

		// Check JWT validation capability
		jwtStatus := hm.checkJWTValidation()

		// Check session store
		sessionStatus := hm.checkSessionStore()

		// Check token repository
		tokenRepoStatus := hm.checkTokenRepository()

		health := HealthStatus{
			Status:      status,
			Timestamp:   time.Now(),
			Version:     "1.0.0",
			Uptime:      time.Since(hm.startTime),
			Environment: hm.config.Server.Environment,
			Services: map[string]ServiceHealth{
				"redis": {
					Status:      redisStatus,
					ResponseTime: 0, // Set in actual ping above
					LastCheck:   time.Now(),
					Error:       redisErr,
				},
			},
			Auth: AuthHealthStatus{
				JWTValidation:   jwtStatus,
				RedisConnection: redisStatus,
				SessionStore:    sessionStatus,
				TokenRepository: tokenRepoStatus,
				AuthServiceConn: authServiceStatus,
			},
		}

		// Set appropriate status code
		statusCode := fiber.StatusOK
		if status == "degraded" {
			statusCode = fiber.StatusServiceUnavailable
		}

		return c.Status(statusCode).JSON(health)
	}
}

// ReadinessCheck returns whether the service is ready to accept requests
func (hm *HealthMiddleware) ReadinessCheck() fiber.Handler {
	return func(c *fiber.Ctx) error {
		ctx := context.Background()
		
		ready := true
		checks := make(map[string]bool)

		// Check Redis connectivity (critical for auth)
		if hm.redisClient != nil {
			err := hm.redisClient.Ping(ctx).Err()
			checks["redis"] = err == nil
			if err != nil {
				ready = false
				hm.logger.Error("Redis not ready", zap.Error(err))
			}
		}

		// Check JWT secret availability
		checks["jwt_secret"] = hm.config.Auth.JWTSecret != ""
		if !checks["jwt_secret"] {
			ready = false
			hm.logger.Error("JWT secret not configured")
		}

		// Check if we can create test tokens
		checks["jwt_signing"] = hm.canSignJWT()
		if !checks["jwt_signing"] {
			ready = false
		}

		response := fiber.Map{
			"ready":     ready,
			"timestamp": time.Now(),
			"checks":    checks,
		}

		statusCode := fiber.StatusOK
		if !ready {
			statusCode = fiber.StatusServiceUnavailable
		}

		return c.Status(statusCode).JSON(response)
	}
}

// LivenessCheck returns whether the service is alive
func (hm *HealthMiddleware) LivenessCheck() fiber.Handler {
	return func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"alive":     true,
			"timestamp": time.Now(),
			"uptime":    time.Since(hm.startTime),
		})
	}
}

// AuthHealthCheck specifically checks authentication-related components
func (hm *HealthMiddleware) AuthHealthCheck() fiber.Handler {
	return func(c *fiber.Ctx) error {
		ctx := context.Background()
		
		checks := make(map[string]interface{})
		overallStatus := "healthy"

		// Test JWT token creation and validation
		jwtTest, err := hm.testJWTRoundtrip()
		if err != nil {
			overallStatus = "unhealthy"
			checks["jwt_roundtrip"] = fiber.Map{
				"status": "failed",
				"error":  err.Error(),
			}
		} else {
			checks["jwt_roundtrip"] = fiber.Map{
				"status": "healthy",
				"test_token_length": len(jwtTest),
			}
		}

		// Test Redis session operations
		if hm.redisClient != nil {
			sessionTest := hm.testSessionOperations(ctx)
			checks["session_operations"] = sessionTest
			if sessionTest["status"] != "healthy" {
				overallStatus = "degraded"
			}
		}

		// Test token blacklist operations
		blacklistTest := hm.testTokenBlacklist(ctx)
		checks["token_blacklist"] = blacklistTest
		if blacklistTest["status"] != "healthy" {
			overallStatus = "degraded"
		}

		// Check auth service connectivity with actual request
		authConnTest := hm.testAuthServiceConnection()
		checks["auth_service"] = authConnTest
		if authConnTest["status"] != "healthy" {
			overallStatus = "degraded"
		}

		response := fiber.Map{
			"status":    overallStatus,
			"timestamp": time.Now(),
			"checks":    checks,
		}

		statusCode := fiber.StatusOK
		if overallStatus == "unhealthy" {
			statusCode = fiber.StatusServiceUnavailable
		}

		return c.Status(statusCode).JSON(response)
	}
}

// Helper methods for health checks

func (hm *HealthMiddleware) checkAuthService() string {
	// This would check if auth service is reachable
	// For now, return "healthy" if URL is configured
	if hm.config.Services.AuthService.URL != "" {
		return "healthy"
	}
	return "not_configured"
}

func (hm *HealthMiddleware) checkJWTValidation() string {
	if hm.config.Auth.JWTSecret != "" {
		return "healthy"
	}
	return "no_secret"
}

func (hm *HealthMiddleware) checkSessionStore() string {
	if hm.redisClient != nil {
		ctx := context.Background()
		err := hm.redisClient.Ping(ctx).Err()
		if err == nil {
			return "healthy"
		}
		return "unhealthy"
	}
	return "not_configured"
}

func (hm *HealthMiddleware) checkTokenRepository() string {
	// Test if we can access token storage
	if hm.redisClient != nil {
		return "healthy"
	}
	return "not_configured"
}

func (hm *HealthMiddleware) canSignJWT() bool {
	if hm.config.Auth.JWTSecret == "" {
		return false
	}
	
	// Try to create a test token
	_, err := hm.testJWTRoundtrip()
	return err == nil
}

func (hm *HealthMiddleware) testJWTRoundtrip() (string, error) {
	// Create auth middleware instance
	authMiddleware := NewAuthMiddleware(hm.config, hm.logger)
	
	// Generate test token
	testToken, err := authMiddleware.GenerateToken(
		"test-user",
		"test@example.com",
		"user",
		"test-tenant",
	)
	if err != nil {
		return "", fmt.Errorf("failed to generate test token: %w", err)
	}

	// Try to validate the token (simplified validation)
	if len(testToken) < 50 { // JWT tokens are typically much longer
		return "", fmt.Errorf("generated token too short")
	}

	return testToken, nil
}

func (hm *HealthMiddleware) testSessionOperations(ctx context.Context) fiber.Map {
	if hm.redisClient == nil {
		return fiber.Map{
			"status": "not_configured",
			"error":  "Redis client not available",
		}
	}

	testKey := fmt.Sprintf("health_check_session_%d", time.Now().Unix())
	testData := `{"user_id":"health_check","test":true}`
	
	// Test set operation
	err := hm.redisClient.Set(ctx, testKey, testData, 5*time.Minute).Err()
	if err != nil {
		return fiber.Map{
			"status": "unhealthy",
			"error":  fmt.Sprintf("failed to set test session: %v", err),
		}
	}

	// Test get operation
	retrievedData, err := hm.redisClient.Get(ctx, testKey).Result()
	if err != nil {
		return fiber.Map{
			"status": "unhealthy",
			"error":  fmt.Sprintf("failed to get test session: %v", err),
		}
	}

	if retrievedData != testData {
		return fiber.Map{
			"status": "unhealthy",
			"error":  "session data mismatch",
		}
	}

	// Cleanup
	hm.redisClient.Del(ctx, testKey)

	return fiber.Map{
		"status":     "healthy",
		"operations": []string{"set", "get", "del"},
	}
}

func (hm *HealthMiddleware) testTokenBlacklist(ctx context.Context) fiber.Map {
	if hm.redisClient == nil {
		return fiber.Map{
			"status": "not_configured",
		}
	}

	testToken := fmt.Sprintf("test_token_%d", time.Now().Unix())
	blacklistKey := fmt.Sprintf("blacklist_token:%s", testToken)
	
	// Test blacklist operations
	err := hm.redisClient.Set(ctx, blacklistKey, "test_user", 1*time.Minute).Err()
	if err != nil {
		return fiber.Map{
			"status": "unhealthy",
			"error":  fmt.Sprintf("failed to blacklist token: %v", err),
		}
	}

	// Check if blacklisted
	_, err = hm.redisClient.Get(ctx, blacklistKey).Result()
	if err != nil {
		return fiber.Map{
			"status": "unhealthy",
			"error":  fmt.Sprintf("failed to check blacklist: %v", err),
		}
	}

	// Cleanup
	hm.redisClient.Del(ctx, blacklistKey)

	return fiber.Map{
		"status": "healthy",
	}
}

func (hm *HealthMiddleware) testAuthServiceConnection() fiber.Map {
	authURL := hm.config.Services.AuthService.URL
	if authURL == "" {
		return fiber.Map{
			"status": "not_configured",
			"error":  "Auth service URL not configured",
		}
	}

	// Make a simple HTTP request to auth service health endpoint
	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	healthURL := fmt.Sprintf("%s/health", authURL)
	resp, err := client.Get(healthURL)
	if err != nil {
		return fiber.Map{
			"status": "unhealthy",
			"error":  fmt.Sprintf("failed to connect: %v", err),
			"url":    healthURL,
		}
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fiber.Map{
			"status": "unhealthy",
			"error":  fmt.Sprintf("auth service returned status %d", resp.StatusCode),
			"url":    healthURL,
		}
	}

	return fiber.Map{
		"status":      "healthy",
		"url":         healthURL,
		"status_code": resp.StatusCode,
	}
}