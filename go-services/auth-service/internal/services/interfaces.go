package services

import "github.com/pyairtable-compose/auth-service/internal/models"

// AuthServiceInterface defines the interface for authentication services
type AuthServiceInterface interface {
	Register(req *models.RegisterRequest) (*models.User, error)
	Login(req *models.LoginRequest) (*models.TokenResponse, error)
	RefreshToken(refreshToken string) (*models.TokenResponse, error)
	ValidateToken(tokenString string) (*models.Claims, error)
	Logout(refreshToken string) error
	GetUserByID(userID string) (*models.User, error)
	UpdateUserProfile(userID string, req *models.UpdateProfileRequest) (*models.User, error)
	ChangePassword(userID string, req *models.ChangePasswordRequest) error
}