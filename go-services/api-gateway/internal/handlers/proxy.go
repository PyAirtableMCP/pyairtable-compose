package handlers

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
	
	"github.com/gofiber/fiber/v2"
	"go.uber.org/zap"
)

type ProxyHandler struct {
	httpClient *http.Client
	logger     *zap.Logger
}

func NewProxyHandler(httpClient *http.Client, logger *zap.Logger) *ProxyHandler {
	return &ProxyHandler{
		httpClient: httpClient,
		logger:     logger,
	}
}

func (p *ProxyHandler) ProxyRequest(c *fiber.Ctx, targetURL string) error {
	// Create request
	req, err := http.NewRequest(c.Method(), targetURL, bytes.NewReader(c.Body()))
	if err != nil {
		p.logger.Error("Failed to create proxy request", zap.Error(err))
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to create request",
		})
	}
	
	// Copy headers
	c.Request().Header.VisitAll(func(key, value []byte) {
		keyStr := string(key)
		// Skip hop-by-hop headers
		if isHopByHopHeader(keyStr) {
			return
		}
		req.Header.Set(keyStr, string(value))
	})
	
	// Add request ID for tracing
	if requestID := c.Locals("requestid"); requestID != nil {
		req.Header.Set("X-Request-ID", requestID.(string))
	}
	
	// Add user context
	if userID := c.Locals("user_id"); userID != nil {
		req.Header.Set("X-User-ID", fmt.Sprintf("%v", userID))
	}
	if tenantID := c.Locals("tenant_id"); tenantID != nil {
		req.Header.Set("X-Tenant-ID", fmt.Sprintf("%v", tenantID))
	}
	
	// Make request
	start := time.Now()
	resp, err := p.httpClient.Do(req)
	duration := time.Since(start)
	
	if err != nil {
		p.logger.Error("Proxy request failed", 
			zap.Error(err),
			zap.String("target", targetURL),
			zap.Duration("duration", duration))
		return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{
			"error": "Service unavailable",
		})
	}
	defer resp.Body.Close()
	
	// Log request
	p.logger.Info("Proxy request completed",
		zap.String("method", c.Method()),
		zap.String("target", targetURL),
		zap.Int("status", resp.StatusCode),
		zap.Duration("duration", duration))
	
	// Copy response headers
	for key, values := range resp.Header {
		if isHopByHopHeader(key) {
			continue
		}
		for _, value := range values {
			c.Set(key, value)
		}
	}
	
	// Copy response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		p.logger.Error("Failed to read response body", zap.Error(err))
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to read response",
		})
	}
	
	// Set status code and body
	c.Status(resp.StatusCode)
	return c.Send(body)
}

func isHopByHopHeader(header string) bool {
	hopByHopHeaders := []string{
		"Connection",
		"Keep-Alive",
		"Proxy-Authenticate",
		"Proxy-Authorization",
		"Te",
		"Trailers",
		"Transfer-Encoding",
		"Upgrade",
	}
	
	header = strings.ToLower(header)
	for _, h := range hopByHopHeaders {
		if strings.ToLower(h) == header {
			return true
		}
	}
	return false
}