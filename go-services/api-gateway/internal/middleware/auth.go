package middleware

import (
    "bytes"
    "encoding/json"
    "fmt"
    "io"
    "strings"
    "net/http"
    
    "github.com/gofiber/fiber/v2"
    "github.com/golang-jwt/jwt/v5"
)

type AuthConfig struct {
    AuthServiceURL       string
    PermissionServiceURL string
    JWTSecret           string
}

type PermissionCheckRequest struct {
    UserID       string `json:"user_id"`
    TenantID     string `json:"tenant_id"`
    ResourceType string `json:"resource_type"`
    ResourceID   string `json:"resource_id,omitempty"`
    Action       string `json:"action"`
}

type PermissionCheckResponse struct {
    Allowed bool   `json:"allowed"`
    Reason  string `json:"reason,omitempty"`
}

// RequireAuth validates JWT tokens and extracts user information
func RequireAuth(config *AuthConfig) fiber.Handler {
    return func(c *fiber.Ctx) error {
        // Get authorization header
        authHeader := c.Get("Authorization")
        if authHeader == "" {
            return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
                "error": "Missing authorization header",
            })
        }
        
        // Extract token
        tokenString := strings.TrimPrefix(authHeader, "Bearer ")
        if tokenString == authHeader {
            return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
                "error": "Invalid authorization format",
            })
        }
        
        // Validate token with auth service
        // For now, we'll do local validation, but this should call the auth service
        token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
            return []byte(config.JWTSecret), nil
        })
        
        if err != nil || !token.Valid {
            return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
                "error": "Invalid token",
            })
        }
        
        // Extract claims
        if claims, ok := token.Claims.(jwt.MapClaims); ok {
            c.Locals("user_id", claims["user_id"])
            c.Locals("tenant_id", claims["tenant_id"])
            c.Locals("permissions", claims["permissions"])
        }
        
        return c.Next()
    }
}

// RequirePermission checks if user has specific permission via Permission Service
func RequirePermission(permission string) fiber.Handler {
    return func(c *fiber.Ctx) error {
        // First check if we have JWT permissions (legacy mode)
        if permissions, ok := c.Locals("permissions").([]interface{}); ok {
            for _, p := range permissions {
                if pStr, ok := p.(string); ok && pStr == permission {
                    return c.Next()
                }
            }
        }
        
        // If no JWT permissions or permission not found, check with Permission Service
        userID, ok := c.Locals("user_id").(string)
        if !ok {
            return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
                "error": "User ID not found in context",
            })
        }
        
        tenantID, _ := c.Locals("tenant_id").(string)
        permissionServiceURL, _ := c.Locals("permission_service_url").(string)
        
        if permissionServiceURL == "" {
            // Fallback to original behavior if no permission service configured
            return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
                "error": "Insufficient permissions",
            })
        }
        
        // Parse permission string (format: "resource_type.action" or "resource_type:resource_id.action")
        parts := strings.Split(permission, ".")
        if len(parts) != 2 {
            return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
                "error": "Invalid permission format",
            })
        }
        
        resourceParts := strings.Split(parts[0], ":")
        resourceType := resourceParts[0]
        resourceID := ""
        if len(resourceParts) > 1 {
            resourceID = resourceParts[1]
        }
        action := parts[1]
        
        // Check permission with Permission Service
        allowed, err := checkPermissionWithService(permissionServiceURL, userID, tenantID, resourceType, resourceID, action)
        if err != nil {
            // Log error but don't fail request (fallback to deny)
            return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
                "error": "Permission check failed",
            })
        }
        
        if !allowed {
            return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
                "error": "Insufficient permissions",
            })
        }
        
        return c.Next()
    }
}

// checkPermissionWithService calls the Permission Service to check permissions
func checkPermissionWithService(serviceURL, userID, tenantID, resourceType, resourceID, action string) (bool, error) {
    reqBody := PermissionCheckRequest{
        UserID:       userID,
        TenantID:     tenantID,
        ResourceType: resourceType,
        ResourceID:   resourceID,
        Action:       action,
    }
    
    reqBytes, err := json.Marshal(reqBody)
    if err != nil {
        return false, fmt.Errorf("failed to marshal request: %w", err)
    }
    
    resp, err := http.Post(
        fmt.Sprintf("%s/api/v1/permissions/check", serviceURL),
        "application/json",
        bytes.NewBuffer(reqBytes),
    )
    if err != nil {
        return false, fmt.Errorf("failed to call permission service: %w", err)
    }
    defer resp.Body.Close()
    
    if resp.StatusCode != http.StatusOK {
        return false, fmt.Errorf("permission service returned status %d", resp.StatusCode)
    }
    
    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return false, fmt.Errorf("failed to read response: %w", err)
    }
    
    var checkResp PermissionCheckResponse
    if err := json.Unmarshal(body, &checkResp); err != nil {
        return false, fmt.Errorf("failed to unmarshal response: %w", err)
    }
    
    return checkResp.Allowed, nil
}

// ProxyAuth forwards authentication to the auth service
func ProxyAuth(authServiceURL string, httpClient *http.Client) fiber.Handler {
    return func(c *fiber.Ctx) error {
        // Create request to auth service
        req, err := http.NewRequest("GET", authServiceURL + "/validate", nil)
        if err != nil {
            return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
                "error": "Failed to create auth request",
            })
        }
        
        // Forward authorization header
        req.Header.Set("Authorization", c.Get("Authorization"))
        
        // Make request
        resp, err := httpClient.Do(req)
        if err != nil {
            return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
                "error": "Failed to validate token",
            })
        }
        defer resp.Body.Close()
        
        if resp.StatusCode != http.StatusOK {
            return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
                "error": "Invalid token",
            })
        }
        
        // TODO: Parse response and set locals
        
        return c.Next()
    }
}