package middleware

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/redis/go-redis/v9"
	"github.com/pyairtable/api-gateway/internal/config"
	"go.uber.org/zap"
)

type SessionData struct {
	UserID      string    `json:"user_id"`
	Email       string    `json:"email"`
	Role        string    `json:"role"`
	TenantID    string    `json:"tenant_id"`
	CreatedAt   time.Time `json:"created_at"`
	LastAccess  time.Time `json:"last_access"`
	IPAddress   string    `json:"ip_address"`
	UserAgent   string    `json:"user_agent"`
}

type SessionMiddleware struct {
	config      *config.Config
	logger      *zap.Logger
	redisClient *redis.Client
	ctx         context.Context
}

func NewSessionMiddleware(cfg *config.Config, logger *zap.Logger, redisClient *redis.Client) *SessionMiddleware {
	return &SessionMiddleware{
		config:      cfg,
		logger:      logger,
		redisClient: redisClient,
		ctx:         context.Background(),
	}
}

// CreateSession creates a new session in Redis
func (sm *SessionMiddleware) CreateSession(userID, email, role, tenantID, ipAddress, userAgent string) (string, error) {
	// Generate session ID
	sessionID, err := sm.generateSessionID()
	if err != nil {
		return "", fmt.Errorf("failed to generate session ID: %w", err)
	}

	// Create session data
	sessionData := SessionData{
		UserID:     userID,
		Email:      email,
		Role:       role,
		TenantID:   tenantID,
		CreatedAt:  time.Now(),
		LastAccess: time.Now(),
		IPAddress:  ipAddress,
		UserAgent:  userAgent,
	}

	// Serialize session data
	data, err := json.Marshal(sessionData)
	if err != nil {
		return "", fmt.Errorf("failed to marshal session data: %w", err)
	}

	// Store in Redis with expiration
	sessionKey := fmt.Sprintf("session:%s", sessionID)
	err = sm.redisClient.Set(sm.ctx, sessionKey, data, 24*time.Hour).Err()
	if err != nil {
		return "", fmt.Errorf("failed to store session in Redis: %w", err)
	}

	// Add to user's active sessions
	userSessionsKey := fmt.Sprintf("user_sessions:%s", userID)
	err = sm.redisClient.SAdd(sm.ctx, userSessionsKey, sessionID).Err()
	if err != nil {
		sm.logger.Error("Failed to add session to user sessions", zap.Error(err))
	}

	// Set expiration on user sessions key
	sm.redisClient.Expire(sm.ctx, userSessionsKey, 24*time.Hour)

	sm.logger.Info("Session created", 
		zap.String("session_id", sessionID),
		zap.String("user_id", userID),
		zap.String("ip_address", ipAddress))

	return sessionID, nil
}

// ValidateSession validates and refreshes a session
func (sm *SessionMiddleware) ValidateSession(sessionID string) (*SessionData, error) {
	if sessionID == "" {
		return nil, fmt.Errorf("session ID is required")
	}

	sessionKey := fmt.Sprintf("session:%s", sessionID)
	data, err := sm.redisClient.Get(sm.ctx, sessionKey).Result()
	if err == redis.Nil {
		return nil, fmt.Errorf("session not found or expired")
	}
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve session: %w", err)
	}

	var sessionData SessionData
	err = json.Unmarshal([]byte(data), &sessionData)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal session data: %w", err)
	}

	// Update last access time
	sessionData.LastAccess = time.Now()
	updatedData, err := json.Marshal(sessionData)
	if err != nil {
		sm.logger.Error("Failed to marshal updated session data", zap.Error(err))
	} else {
		// Update in Redis with extended expiration
		err = sm.redisClient.Set(sm.ctx, sessionKey, updatedData, 24*time.Hour).Err()
		if err != nil {
			sm.logger.Error("Failed to update session in Redis", zap.Error(err))
		}
	}

	return &sessionData, nil
}

// InvalidateSession removes a session
func (sm *SessionMiddleware) InvalidateSession(sessionID string) error {
	if sessionID == "" {
		return nil
	}

	// Get session data first to find user ID
	sessionData, err := sm.ValidateSession(sessionID)
	if err != nil {
		// Session might already be expired, but continue cleanup
		sm.logger.Debug("Session not found during invalidation", zap.String("session_id", sessionID))
	}

	sessionKey := fmt.Sprintf("session:%s", sessionID)
	
	// Remove from Redis
	err = sm.redisClient.Del(sm.ctx, sessionKey).Err()
	if err != nil {
		sm.logger.Error("Failed to delete session from Redis", zap.Error(err))
	}

	// Remove from user's active sessions if we have user ID
	if sessionData != nil {
		userSessionsKey := fmt.Sprintf("user_sessions:%s", sessionData.UserID)
		err = sm.redisClient.SRem(sm.ctx, userSessionsKey, sessionID).Err()
		if err != nil {
			sm.logger.Error("Failed to remove session from user sessions", zap.Error(err))
		}

		sm.logger.Info("Session invalidated", 
			zap.String("session_id", sessionID),
			zap.String("user_id", sessionData.UserID))
	}

	return nil
}

// InvalidateAllUserSessions removes all sessions for a user
func (sm *SessionMiddleware) InvalidateAllUserSessions(userID string) error {
	userSessionsKey := fmt.Sprintf("user_sessions:%s", userID)
	
	// Get all session IDs for the user
	sessionIDs, err := sm.redisClient.SMembers(sm.ctx, userSessionsKey).Result()
	if err != nil {
		return fmt.Errorf("failed to get user sessions: %w", err)
	}

	// Remove each session
	for _, sessionID := range sessionIDs {
		sessionKey := fmt.Sprintf("session:%s", sessionID)
		err = sm.redisClient.Del(sm.ctx, sessionKey).Err()
		if err != nil {
			sm.logger.Error("Failed to delete user session", 
				zap.String("session_id", sessionID), 
				zap.Error(err))
		}
	}

	// Remove the user sessions set
	err = sm.redisClient.Del(sm.ctx, userSessionsKey).Err()
	if err != nil {
		return fmt.Errorf("failed to delete user sessions set: %w", err)
	}

	sm.logger.Info("All user sessions invalidated", 
		zap.String("user_id", userID),
		zap.Int("session_count", len(sessionIDs)))

	return nil
}

// SessionHandler middleware that injects session data into context
func (sm *SessionMiddleware) SessionHandler() fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Try to get session ID from various sources
		sessionID := sm.getSessionID(c)
		
		if sessionID != "" {
			sessionData, err := sm.ValidateSession(sessionID)
			if err != nil {
				sm.logger.Debug("Session validation failed", 
					zap.String("session_id", sessionID),
					zap.Error(err))
			} else {
				// Store session data in context
				c.Locals("session_id", sessionID)
				c.Locals("session_data", sessionData)
				c.Locals("session_user_id", sessionData.UserID)
				c.Locals("session_valid", true)

				// Add session headers for backend services
				c.Set("X-Session-ID", sessionID)
				c.Set("X-Session-User-ID", sessionData.UserID)
			}
		}

		return c.Next()
	}
}

// RequireSession ensures a valid session exists
func (sm *SessionMiddleware) RequireSession() fiber.Handler {
	return func(c *fiber.Ctx) error {
		sessionValid, ok := c.Locals("session_valid").(bool)
		if !ok || !sessionValid {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Valid session required",
			})
		}
		return c.Next()
	}
}

// generateSessionID generates a cryptographically secure session ID
func (sm *SessionMiddleware) generateSessionID() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.URLEncoding.EncodeToString(bytes), nil
}

// getSessionID extracts session ID from various sources
func (sm *SessionMiddleware) getSessionID(c *fiber.Ctx) string {
	// Try Authorization header first (Bearer token might contain session info)
	auth := c.Get("Authorization")
	if auth != "" {
		// Extract from JWT claims if available
		if claims, ok := c.Locals("user").(*Claims); ok {
			// Generate deterministic session ID from user ID and issued time
			if claims.IssuedAt != nil {
				sessionSeed := fmt.Sprintf("%s:%d", claims.UserID, claims.IssuedAt.Unix())
				hash := fmt.Sprintf("%x", sessionSeed)
				return hash[:32] // Use first 32 chars as session ID
			}
		}
	}

	// Try session cookie
	sessionID := c.Cookies("session_id")
	if sessionID != "" {
		return sessionID
	}

	// Try custom header
	sessionID = c.Get("X-Session-ID")
	if sessionID != "" {
		return sessionID
	}

	return ""
}

// CleanupExpiredSessions removes expired sessions (should be called periodically)
func (sm *SessionMiddleware) CleanupExpiredSessions() error {
	// This is handled automatically by Redis TTL, but we can implement
	// additional cleanup logic here if needed
	sm.logger.Debug("Session cleanup completed (handled by Redis TTL)")
	return nil
}

// GetActiveSessionCount returns the number of active sessions for a user
func (sm *SessionMiddleware) GetActiveSessionCount(userID string) (int, error) {
	userSessionsKey := fmt.Sprintf("user_sessions:%s", userID)
	count, err := sm.redisClient.SCard(sm.ctx, userSessionsKey).Result()
	return int(count), err
}