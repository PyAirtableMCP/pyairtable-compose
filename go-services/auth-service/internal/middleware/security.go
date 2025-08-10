package middleware

import (
	"sync"
	"time"

	"github.com/gofiber/fiber/v2"
)

// SecurityHeadersMiddleware adds security headers to responses
func SecurityHeadersMiddleware() fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Set security headers
		c.Set("X-Content-Type-Options", "nosniff")
		c.Set("X-Frame-Options", "DENY")
		c.Set("X-XSS-Protection", "1; mode=block")
		c.Set("Referrer-Policy", "strict-origin-when-cross-origin")
		c.Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'")
		c.Set("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
		c.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		
		return c.Next()
	}
}

// InputSizeMiddleware limits request body size and validates input
func InputSizeMiddleware(maxSize int) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Check Content-Length header
		contentLength := c.Get("Content-Length")
		if contentLength != "" {
			if len(contentLength) > 10 { // Basic validation for extremely large values
				return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
					"error": "Content-Length header is invalid",
				})
			}
		}

		// The actual body size limiting is handled by Fiber's BodyLimit config
		// This middleware can be used for additional validation
		return c.Next()
	}
}

// RateLimiter implements a token bucket rate limiter
type RateLimiter struct {
	requests map[string]*bucketInfo
	mutex    sync.RWMutex
	limit    int
	window   time.Duration
	cleanup  time.Duration
}

type bucketInfo struct {
	tokens    int
	lastRefill time.Time
}

// NewRateLimiter creates a new rate limiter
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	rl := &RateLimiter{
		requests: make(map[string]*bucketInfo),
		limit:    limit,
		window:   window,
		cleanup:  window * 2, // Cleanup old entries every 2 windows
	}
	
	// Start cleanup goroutine
	go rl.cleanupOldEntries()
	
	return rl
}

// Allow checks if a request should be allowed
func (rl *RateLimiter) Allow(key string) bool {
	rl.mutex.Lock()
	defer rl.mutex.Unlock()
	
	now := time.Now()
	
	// Get or create bucket info
	bucket, exists := rl.requests[key]
	if !exists {
		bucket = &bucketInfo{
			tokens:    rl.limit - 1, // Use one token
			lastRefill: now,
		}
		rl.requests[key] = bucket
		return true
	}
	
	// Refill tokens based on time passed
	timePassed := now.Sub(bucket.lastRefill)
	tokensToAdd := int(timePassed / rl.window)
	
	if tokensToAdd > 0 {
		bucket.tokens += tokensToAdd
		if bucket.tokens > rl.limit {
			bucket.tokens = rl.limit
		}
		bucket.lastRefill = now
	}
	
	// Check if tokens available
	if bucket.tokens > 0 {
		bucket.tokens--
		return true
	}
	
	return false
}

// cleanupOldEntries removes old entries from the rate limiter
func (rl *RateLimiter) cleanupOldEntries() {
	ticker := time.NewTicker(rl.cleanup)
	defer ticker.Stop()
	
	for {
		select {
		case <-ticker.C:
			rl.mutex.Lock()
			now := time.Now()
			for key, bucket := range rl.requests {
				if now.Sub(bucket.lastRefill) > rl.cleanup {
					delete(rl.requests, key)
				}
			}
			rl.mutex.Unlock()
		}
	}
}

// RateLimitMiddleware creates a Fiber middleware for rate limiting
func RateLimitMiddleware(limiter *RateLimiter) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Use IP address as the key for rate limiting
		key := c.IP()
		
		if !limiter.Allow(key) {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Too many requests. Please try again later.",
			})
		}
		
		return c.Next()
	}
}

