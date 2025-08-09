package middleware

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// RedisRateLimiter implements Redis-based rate limiting as specified in AUTHENTICATION_ARCHITECTURE.md
type RedisRateLimiter struct {
	redisClient *redis.Client
	logger      *zap.Logger
}

// RateLimitConfig holds configuration for different types of rate limits
type RateLimitConfig struct {
	// Authentication endpoints: 5 attempts per IP per 15 minutes
	AuthLimit    int           `default:"5"`
	AuthWindow   time.Duration `default:"15m"`
	
	// Registration: 3 attempts per IP per hour  
	RegisterLimit int           `default:"3"`
	RegisterWindow time.Duration `default:"1h"`
	
	// General protected endpoints: 1000 requests per user per hour
	GeneralLimit  int           `default:"1000"`
	GeneralWindow time.Duration `default:"1h"`
	
	// Sensitive endpoints: 100 requests per user per hour
	SensitiveLimit  int           `default:"100"`
	SensitiveWindow time.Duration `default:"1h"`
}

// NewRedisRateLimiter creates a new Redis-based rate limiter
func NewRedisRateLimiter(redisClient *redis.Client, logger *zap.Logger) *RedisRateLimiter {
	return &RedisRateLimiter{
		redisClient: redisClient,
		logger:      logger,
	}
}

// AuthEndpointsLimiter applies rate limiting to authentication endpoints
func (r *RedisRateLimiter) AuthEndpointsLimiter() fiber.Handler {
	return func(c *fiber.Ctx) error {
		path := c.Path()
		
		// Apply rate limiting only to auth endpoints
		if !r.isAuthEndpoint(path) {
			return c.Next()
		}
		
		var limit int
		var window time.Duration
		
		// Different limits for different auth endpoints
		switch {
		case strings.Contains(path, "/login"):
			limit = 5  // 5 attempts per 15 minutes
			window = 15 * time.Minute
		case strings.Contains(path, "/register"):
			limit = 3  // 3 attempts per hour
			window = 1 * time.Hour
		case strings.Contains(path, "/refresh"):
			limit = 10 // 10 attempts per 15 minutes
			window = 15 * time.Minute
		default:
			limit = 5
			window = 15 * time.Minute
		}
		
		key := fmt.Sprintf("rate_limit:auth:%s:%s", c.IP(), path)
		
		allowed, remaining, resetTime, err := r.checkRateLimit(key, limit, window)
		if err != nil {
			r.logger.Error("Rate limit check failed", 
				zap.Error(err),
				zap.String("key", key))
			// Allow request on Redis failure (fail-open)
			return c.Next()
		}
		
		// Add rate limit headers
		c.Set("X-RateLimit-Limit", strconv.Itoa(limit))
		c.Set("X-RateLimit-Remaining", strconv.Itoa(remaining))
		c.Set("X-RateLimit-Reset", strconv.FormatInt(resetTime, 10))
		
		if !allowed {
			r.logger.Warn("Rate limit exceeded for auth endpoint",
				zap.String("ip", c.IP()),
				zap.String("path", path),
				zap.Int("limit", limit),
				zap.Duration("window", window))
				
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error":     "RATE_LIMIT_EXCEEDED",
				"message":   "Too many requests. Please try again later.",
				"timestamp": time.Now().Unix(),
				"retry_after": resetTime - time.Now().Unix(),
			})
		}
		
		return c.Next()
	}
}

// ProtectedEndpointsLimiter applies rate limiting to protected endpoints based on user
func (r *RedisRateLimiter) ProtectedEndpointsLimiter() fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Skip if not a protected route or user not authenticated
		userID := c.Locals("user_id")
		if userID == nil {
			return c.Next()
		}
		
		path := c.Path()
		
		// Skip auth endpoints (handled by AuthEndpointsLimiter)
		if r.isAuthEndpoint(path) {
			return c.Next()
		}
		
		var limit int
		var window time.Duration
		
		// Different limits for different endpoint types
		if r.isSensitiveEndpoint(path) {
			limit = 100 // 100 requests per hour for sensitive endpoints
			window = 1 * time.Hour
		} else {
			limit = 1000 // 1000 requests per hour for general endpoints
			window = 1 * time.Hour
		}
		
		key := fmt.Sprintf("rate_limit:user:%s", userID.(string))
		
		allowed, remaining, resetTime, err := r.checkRateLimit(key, limit, window)
		if err != nil {
			r.logger.Error("User rate limit check failed", 
				zap.Error(err),
				zap.String("key", key))
			// Allow request on Redis failure (fail-open)
			return c.Next()
		}
		
		// Add rate limit headers
		c.Set("X-RateLimit-Limit", strconv.Itoa(limit))
		c.Set("X-RateLimit-Remaining", strconv.Itoa(remaining))
		c.Set("X-RateLimit-Reset", strconv.FormatInt(resetTime, 10))
		
		if !allowed {
			r.logger.Warn("Rate limit exceeded for user",
				zap.String("user_id", userID.(string)),
				zap.String("path", path),
				zap.Int("limit", limit),
				zap.Duration("window", window))
				
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error":     "RATE_LIMIT_EXCEEDED",
				"message":   "Too many requests. Please try again later.",
				"timestamp": time.Now().Unix(),
				"retry_after": resetTime - time.Now().Unix(),
			})
		}
		
		return c.Next()
	}
}

// checkRateLimit implements sliding window rate limiting using Redis
func (r *RedisRateLimiter) checkRateLimit(key string, limit int, window time.Duration) (allowed bool, remaining int, resetTime int64, err error) {
	ctx := context.Background()
	now := time.Now()
	windowStart := now.Add(-window)
	
	// Use Redis pipeline for atomic operations
	pipe := r.redisClient.Pipeline()
	
	// Remove expired entries
	pipe.ZRemRangeByScore(ctx, key, "0", strconv.FormatInt(windowStart.UnixNano(), 10))
	
	// Count current requests in window
	countCmd := pipe.ZCard(ctx, key)
	
	// Add current request
	pipe.ZAdd(ctx, key, redis.Z{
		Score:  float64(now.UnixNano()),
		Member: fmt.Sprintf("%d", now.UnixNano()),
	})
	
	// Set expiration
	pipe.Expire(ctx, key, window+time.Minute) // Extra minute for cleanup
	
	_, err = pipe.Exec(ctx)
	if err != nil {
		return false, 0, 0, err
	}
	
	count := int(countCmd.Val())
	
	// Check if limit exceeded (count includes the current request)
	if count > limit {
		// Remove the request we just added since we're rejecting it
		r.redisClient.ZRem(ctx, key, fmt.Sprintf("%d", now.UnixNano()))
		return false, 0, now.Add(window).Unix(), nil
	}
	
	remaining = limit - count
	if remaining < 0 {
		remaining = 0
	}
	
	resetTime = now.Add(window).Unix()
	
	return true, remaining, resetTime, nil
}

// isAuthEndpoint checks if the path is an authentication endpoint
func (r *RedisRateLimiter) isAuthEndpoint(path string) bool {
	authPaths := []string{
		"/api/v1/auth/login",
		"/api/v1/auth/register", 
		"/api/v1/auth/refresh",
		"/api/auth/login",
		"/api/auth/register",
		"/api/auth/refresh",
	}
	
	for _, authPath := range authPaths {
		if strings.HasPrefix(path, authPath) {
			return true
		}
	}
	
	return false
}

// isSensitiveEndpoint checks if the path is a sensitive endpoint requiring stricter rate limiting
func (r *RedisRateLimiter) isSensitiveEndpoint(path string) bool {
	sensitivePaths := []string{
		"/api/v1/admin/",
		"/api/v1/users/", // User management
		"/api/v1/auth/",  // Auth endpoints (though handled separately)
		"/api/v1/files/upload", // File uploads
	}
	
	for _, sensitivePath := range sensitivePaths {
		if strings.HasPrefix(path, sensitivePath) {
			return true
		}
	}
	
	return false
}

// GetRateLimitInfo returns current rate limit status for a key
func (r *RedisRateLimiter) GetRateLimitInfo(key string, limit int, window time.Duration) (remaining int, resetTime int64, err error) {
	ctx := context.Background()
	now := time.Now()
	windowStart := now.Add(-window)
	
	// Count requests in current window
	count, err := r.redisClient.ZCount(ctx, key, 
		strconv.FormatInt(windowStart.UnixNano(), 10),
		"+inf").Result()
	if err != nil {
		return 0, 0, err
	}
	
	remaining = limit - int(count)
	if remaining < 0 {
		remaining = 0
	}
	
	resetTime = now.Add(window).Unix()
	
	return remaining, resetTime, nil
}