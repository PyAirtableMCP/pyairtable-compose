package handlers

import (
    "strings"
    
    "github.com/gofiber/fiber/v2"
    "github.com/Reg-Kris/pyairtable-auth-service/internal/models"
    "github.com/Reg-Kris/pyairtable-auth-service/internal/services"
    "go.uber.org/zap"
)

// AuthHandler handles authentication endpoints
type AuthHandler struct {
    logger      *zap.Logger
    authService *services.AuthService
}

// NewAuthHandler creates a new auth handler
func NewAuthHandler(logger *zap.Logger, authService *services.AuthService) *AuthHandler {
    return &AuthHandler{
        logger:      logger,
        authService: authService,
    }
}

// Register handles user registration
func (h *AuthHandler) Register(c *fiber.Ctx) error {
    var req models.RegisterRequest
    if err := c.BodyParser(&req); err != nil {
        return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
            "error": "Invalid request body",
        })
    }
    
    // TODO: Add validation
    
    user, err := h.authService.Register(&req)
    if err != nil {
        h.logger.Error("Registration failed", zap.Error(err))
        
        if strings.Contains(err.Error(), "already registered") {
            return c.Status(fiber.StatusConflict).JSON(fiber.Map{
                "error": "Email already registered",
            })
        }
        
        return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
            "error": "Registration failed",
        })
    }
    
    return c.Status(fiber.StatusCreated).JSON(user)
}

// Login handles user login
func (h *AuthHandler) Login(c *fiber.Ctx) error {
    var req models.LoginRequest
    if err := c.BodyParser(&req); err != nil {
        return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
            "error": "Invalid request body",
        })
    }
    
    tokens, err := h.authService.Login(&req)
    if err != nil {
        h.logger.Error("Login failed", zap.Error(err), zap.String("email", req.Email))
        
        if err == services.ErrInvalidCredentials {
            return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
                "error": "Invalid email or password",
            })
        }
        
        if err == services.ErrUserNotActive {
            return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
                "error": "Account is not active",
            })
        }
        
        return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
            "error": "Login failed",
        })
    }
    
    return c.JSON(tokens)
}

// RefreshToken handles token refresh
func (h *AuthHandler) RefreshToken(c *fiber.Ctx) error {
    var req models.RefreshRequest
    if err := c.BodyParser(&req); err != nil {
        return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
            "error": "Invalid request body",
        })
    }
    
    tokens, err := h.authService.RefreshToken(req.RefreshToken)
    if err != nil {
        h.logger.Error("Token refresh failed", zap.Error(err))
        
        if err == services.ErrInvalidToken || err == services.ErrTokenExpired {
            return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
                "error": "Invalid or expired refresh token",
            })
        }
        
        return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
            "error": "Token refresh failed",
        })
    }
    
    return c.JSON(tokens)
}

// Logout handles user logout
func (h *AuthHandler) Logout(c *fiber.Ctx) error {
    var req models.RefreshRequest
    if err := c.BodyParser(&req); err != nil {
        return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
            "error": "Invalid request body",
        })
    }
    
    if err := h.authService.Logout(req.RefreshToken); err != nil {
        h.logger.Error("Logout failed", zap.Error(err))
        // Don't return error to client for security
    }
    
    return c.JSON(fiber.Map{
        "message": "Logged out successfully",
    })
}

// GetMe returns the current user's information
func (h *AuthHandler) GetMe(c *fiber.Ctx) error {
    // Get user ID from context (set by auth middleware)
    userID := c.Locals("userID")
    if userID == nil {
        return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
            "error": "Unauthorized",
        })
    }
    
    // TODO: Get user from repository
    
    return c.JSON(fiber.Map{
        "user_id": userID,
        "message": "User profile endpoint - TODO",
    })
}

// UpdateMe updates the current user's information
func (h *AuthHandler) UpdateMe(c *fiber.Ctx) error {
    userID := c.Locals("userID")
    if userID == nil {
        return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
            "error": "Unauthorized",
        })
    }
    
    // TODO: Implement profile update
    
    return c.JSON(fiber.Map{
        "message": "Profile update endpoint - TODO",
    })
}

// ChangePassword handles password change
func (h *AuthHandler) ChangePassword(c *fiber.Ctx) error {
    userID := c.Locals("userID")
    if userID == nil {
        return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
            "error": "Unauthorized",
        })
    }
    
    var req models.ChangePasswordRequest
    if err := c.BodyParser(&req); err != nil {
        return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
            "error": "Invalid request body",
        })
    }
    
    if err := h.authService.ChangePassword(userID.(string), &req); err != nil {
        h.logger.Error("Password change failed", zap.Error(err))
        
        if strings.Contains(err.Error(), "incorrect") {
            return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
                "error": "Current password is incorrect",
            })
        }
        
        return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
            "error": "Password change failed",
        })
    }
    
    return c.JSON(fiber.Map{
        "message": "Password changed successfully",
    })
}

// ValidateToken validates a token (for internal service use)
func (h *AuthHandler) ValidateToken(c *fiber.Ctx) error {
    authHeader := c.Get("Authorization")
    if authHeader == "" {
        return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
            "error": "Missing Authorization header",
        })
    }
    
    // Extract token from Bearer scheme
    parts := strings.Split(authHeader, " ")
    if len(parts) != 2 || parts[0] != "Bearer" {
        return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
            "error": "Invalid Authorization header format",
        })
    }
    
    claims, err := h.authService.ValidateToken(parts[1])
    if err != nil {
        return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
            "error": "Invalid token",
        })
    }
    
    return c.JSON(claims)
}