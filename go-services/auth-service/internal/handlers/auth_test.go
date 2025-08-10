package handlers

import (
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/pyairtable-compose/auth-service/internal/models"
	"github.com/pyairtable-compose/auth-service/internal/services"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"go.uber.org/zap"
)

// MockAuthService for testing
type MockAuthService struct {
	mock.Mock
}

func (m *MockAuthService) Register(req *models.RegisterRequest) (*models.User, error) {
	args := m.Called(req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.User), args.Error(1)
}

func (m *MockAuthService) Login(req *models.LoginRequest) (*models.TokenResponse, error) {
	args := m.Called(req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.TokenResponse), args.Error(1)
}

func (m *MockAuthService) RefreshToken(refreshToken string) (*models.TokenResponse, error) {
	args := m.Called(refreshToken)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.TokenResponse), args.Error(1)
}

func (m *MockAuthService) ValidateToken(token string) (*models.Claims, error) {
	args := m.Called(token)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.Claims), args.Error(1)
}

func (m *MockAuthService) Logout(refreshToken string) error {
	args := m.Called(refreshToken)
	return args.Error(0)
}

func (m *MockAuthService) GetUserByID(userID string) (*models.User, error) {
	args := m.Called(userID)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.User), args.Error(1)
}

func (m *MockAuthService) UpdateUserProfile(userID string, req *models.UpdateProfileRequest) (*models.User, error) {
	args := m.Called(userID, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*models.User), args.Error(1)
}

func (m *MockAuthService) ChangePassword(userID string, req *models.ChangePasswordRequest) error {
	args := m.Called(userID, req)
	return args.Error(0)
}

func setupTestApp() (*fiber.App, *MockAuthService) {
	logger, _ := zap.NewDevelopment()
	mockService := &MockAuthService{}
	var authService services.AuthServiceInterface = mockService
	handler := NewAuthHandler(logger, authService)

	app := fiber.New()
	auth := app.Group("/auth")
	auth.Post("/register", handler.Register)
	auth.Post("/login", handler.Login)
	auth.Post("/refresh", handler.RefreshToken)
	auth.Post("/logout", handler.Logout)
	auth.Post("/validate", handler.ValidateToken)

	return app, mockService
}

func TestAuthHandler_Register_Success(t *testing.T) {
	app, mockService := setupTestApp()

	// Mock successful registration
	expectedUser := &models.User{
		ID:        "test-id",
		Email:     "test@example.com",
		FirstName: "Test",
		LastName:  "User",
		Role:      "user",
		CreatedAt: time.Now(),
	}

	mockService.On("Register", mock.AnythingOfType("*models.RegisterRequest")).Return(expectedUser, nil)

	// Create request
	reqBody := models.RegisterRequest{
		Email:     "test@example.com",
		Password:  "SecurePass123",
		FirstName: "Test",
		LastName:  "User",
	}
	body, _ := json.Marshal(reqBody)

	req := httptest.NewRequest("POST", "/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)

	mockService.AssertExpectations(t)
}

func TestAuthHandler_Register_InvalidRequest(t *testing.T) {
	app, _ := setupTestApp()

	// Create invalid request (missing required fields)
	reqBody := models.RegisterRequest{
		Email: "test@example.com",
		// Missing password, first_name, last_name
	}
	body, _ := json.Marshal(reqBody)

	req := httptest.NewRequest("POST", "/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestAuthHandler_Register_EmailAlreadyExists(t *testing.T) {
	app, mockService := setupTestApp()

	// Mock email already exists error
	mockService.On("Register", mock.AnythingOfType("*models.RegisterRequest")).Return(nil, 
		fiber.NewError(fiber.StatusConflict, "email already registered"))

	reqBody := models.RegisterRequest{
		Email:     "existing@example.com",
		Password:  "SecurePass123",
		FirstName: "Test",
		LastName:  "User",
	}
	body, _ := json.Marshal(reqBody)

	req := httptest.NewRequest("POST", "/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)

	mockService.AssertExpectations(t)
}

func TestAuthHandler_Login_Success(t *testing.T) {
	app, mockService := setupTestApp()

	// Mock successful login
	expectedTokens := &models.TokenResponse{
		AccessToken:  "access-token",
		RefreshToken: "refresh-token",
		TokenType:    "Bearer",
		ExpiresIn:    3600,
	}

	mockService.On("Login", mock.AnythingOfType("*models.LoginRequest")).Return(expectedTokens, nil)

	reqBody := models.LoginRequest{
		Email:    "test@example.com",
		Password: "SecurePass123",
	}
	body, _ := json.Marshal(reqBody)

	req := httptest.NewRequest("POST", "/auth/login", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	mockService.AssertExpectations(t)
}

func TestAuthHandler_Login_InvalidCredentials(t *testing.T) {
	app, mockService := setupTestApp()

	// Mock invalid credentials
	mockService.On("Login", mock.AnythingOfType("*models.LoginRequest")).Return(nil, services.ErrInvalidCredentials)

	reqBody := models.LoginRequest{
		Email:    "test@example.com",
		Password: "wrongpassword",
	}
	body, _ := json.Marshal(reqBody)

	req := httptest.NewRequest("POST", "/auth/login", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)

	mockService.AssertExpectations(t)
}

func TestAuthHandler_RefreshToken_Success(t *testing.T) {
	app, mockService := setupTestApp()

	// Mock successful token refresh
	expectedTokens := &models.TokenResponse{
		AccessToken:  "new-access-token",
		RefreshToken: "new-refresh-token",
		TokenType:    "Bearer",
		ExpiresIn:    3600,
	}

	mockService.On("RefreshToken", "valid-refresh-token").Return(expectedTokens, nil)

	reqBody := models.RefreshRequest{
		RefreshToken: "valid-refresh-token",
	}
	body, _ := json.Marshal(reqBody)

	req := httptest.NewRequest("POST", "/auth/refresh", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	mockService.AssertExpectations(t)
}

func TestAuthHandler_RefreshToken_InvalidToken(t *testing.T) {
	app, mockService := setupTestApp()

	// Mock invalid refresh token
	mockService.On("RefreshToken", "invalid-token").Return(nil, services.ErrInvalidToken)

	reqBody := models.RefreshRequest{
		RefreshToken: "invalid-token",
	}
	body, _ := json.Marshal(reqBody)

	req := httptest.NewRequest("POST", "/auth/refresh", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)

	mockService.AssertExpectations(t)
}

func TestAuthHandler_ValidateToken_Success(t *testing.T) {
	app, mockService := setupTestApp()

	// Mock successful token validation
	expectedClaims := &models.Claims{
		UserID:   "user-id",
		Email:    "test@example.com",
		Role:     "user",
		TenantID: "tenant-id",
		Exp:      time.Now().Add(time.Hour).Unix(),
		Iat:      time.Now().Unix(),
	}

	mockService.On("ValidateToken", "valid-token").Return(expectedClaims, nil)

	req := httptest.NewRequest("POST", "/auth/validate", nil)
	req.Header.Set("Authorization", "Bearer valid-token")

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	mockService.AssertExpectations(t)
}

func TestAuthHandler_ValidateToken_MissingHeader(t *testing.T) {
	app, _ := setupTestApp()

	req := httptest.NewRequest("POST", "/auth/validate", nil)
	// Missing Authorization header

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestAuthHandler_ValidateToken_InvalidFormat(t *testing.T) {
	app, _ := setupTestApp()

	req := httptest.NewRequest("POST", "/auth/validate", nil)
	req.Header.Set("Authorization", "invalid-format")

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestAuthHandler_Logout_Success(t *testing.T) {
	app, mockService := setupTestApp()

	// Mock successful logout
	mockService.On("Logout", "valid-refresh-token").Return(nil)

	reqBody := models.RefreshRequest{
		RefreshToken: "valid-refresh-token",
	}
	body, _ := json.Marshal(reqBody)

	req := httptest.NewRequest("POST", "/auth/logout", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	assert.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	mockService.AssertExpectations(t)
}