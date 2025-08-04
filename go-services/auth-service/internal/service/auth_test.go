package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/golang/mock/gomock"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/pyairtable/go-services/auth-service/internal/models"
	"github.com/pyairtable/go-services/auth-service/internal/repository/mocks"
	"github.com/pyairtable/go-services/pkg/auth"
	"github.com/pyairtable/go-services/pkg/errors"
)

// AuthServiceTestSuite provides a test suite for AuthService
type AuthServiceTestSuite struct {
	suite.Suite
	ctrl           *gomock.Controller
	mockUserRepo   *mocks.MockUserRepository
	mockTokenRepo  *mocks.MockTokenRepository
	mockHasher     *mocks.MockPasswordHasher
	authService    *AuthService
	ctx            context.Context
}

// SetupTest runs before each test
func (suite *AuthServiceTestSuite) SetupTest() {
	suite.ctrl = gomock.NewController(suite.T())
	suite.mockUserRepo = mocks.NewMockUserRepository(suite.ctrl)
	suite.mockTokenRepo = mocks.NewMockTokenRepository(suite.ctrl)
	suite.mockHasher = mocks.NewMockPasswordHasher(suite.ctrl)
	suite.ctx = context.Background()

	// Create AuthService with mocked dependencies
	suite.authService = &AuthService{
		userRepo:                 suite.mockUserRepo,
		tokenRepo:               suite.mockTokenRepo,
		hasher:                  suite.mockHasher,
		jwtSecret:              "test-secret",
		accessTokenExpiration:   time.Hour,
		refreshTokenExpiration:  24 * time.Hour,
		maxLoginAttempts:        5,
		lockoutDuration:         15 * time.Minute,
	}
}

// TearDownTest runs after each test
func (suite *AuthServiceTestSuite) TearDownTest() {
	suite.ctrl.Finish()
}

// TestAuthService runs the test suite
func TestAuthService(t *testing.T) {
	suite.Run(t, new(AuthServiceTestSuite))
}

// Test user registration
func (suite *AuthServiceTestSuite) TestRegisterUser_Success() {
	// Test data
	userReq := &auth.RegisterRequest{
		Email:    "test@example.com",
		Password: "SecurePassword123!",
		Name:     "Test User",
		TenantID: "tenant-123",
	}

	expectedUser := &models.User{
		ID:       "user-123",
		Email:    userReq.Email,
		Name:     userReq.Name,
		TenantID: userReq.TenantID,
		IsActive: true,
		Role:     "user",
	}

	// Mock expectations
	suite.mockUserRepo.EXPECT().
		GetByEmail(suite.ctx, userReq.Email).
		Return(nil, nil) // User doesn't exist

	suite.mockHasher.EXPECT().
		HashPassword(userReq.Password).
		Return("hashed-password", nil)

	suite.mockUserRepo.EXPECT().
		Create(suite.ctx, gomock.Any()).
		Return(expectedUser, nil)

	// Execute
	user, err := suite.authService.RegisterUser(suite.ctx, userReq)

	// Verify
	require.NoError(suite.T(), err)
	assert.Equal(suite.T(), expectedUser.Email, user.Email)
	assert.Equal(suite.T(), expectedUser.Name, user.Name)
	assert.Equal(suite.T(), expectedUser.TenantID, user.TenantID)
	assert.True(suite.T(), user.IsActive)
}

func (suite *AuthServiceTestSuite) TestRegisterUser_EmailAlreadyExists() {
	// Test data
	userReq := &auth.RegisterRequest{
		Email:    "existing@example.com",
		Password: "SecurePassword123!",
		Name:     "Test User",
		TenantID: "tenant-123",
	}

	existingUser := &models.User{
		ID:    "existing-user-id",
		Email: userReq.Email,
	}

	// Mock expectations
	suite.mockUserRepo.EXPECT().
		GetByEmail(suite.ctx, userReq.Email).
		Return(existingUser, nil)

	// Execute
	user, err := suite.authService.RegisterUser(suite.ctx, userReq)

	// Verify
	assert.Nil(suite.T(), user)
	assert.Error(suite.T(), err)
	assert.Contains(suite.T(), err.Error(), "email already registered")
}

func (suite *AuthServiceTestSuite) TestRegisterUser_WeakPassword() {
	// Test data
	userReq := &auth.RegisterRequest{
		Email:    "test@example.com",
		Password: "weak", // Too weak
		Name:     "Test User",
		TenantID: "tenant-123",
	}

	// Execute
	user, err := suite.authService.RegisterUser(suite.ctx, userReq)

	// Verify
	assert.Nil(suite.T(), user)
	assert.Error(suite.T(), err)
	assert.Contains(suite.T(), err.Error(), "password does not meet requirements")
}

// Test user authentication
func (suite *AuthServiceTestSuite) TestAuthenticate_Success() {
	// Test data
	email := "test@example.com"
	password := "SecurePassword123!"
	
	user := &models.User{
		ID:             "user-123",
		Email:          email,
		HashedPassword: "hashed-password",
		IsActive:       true,
		FailedAttempts: 0,
		LastAttempt:    time.Time{},
	}

	// Mock expectations
	suite.mockUserRepo.EXPECT().
		GetByEmail(suite.ctx, email).
		Return(user, nil)

	suite.mockHasher.EXPECT().
		VerifyPassword(password, user.HashedPassword).
		Return(true)

	suite.mockUserRepo.EXPECT().
		UpdateLoginAttempts(suite.ctx, user.ID, 0, time.Time{}).
		Return(nil)

	// Execute
	authUser, err := suite.authService.Authenticate(suite.ctx, email, password)

	// Verify
	require.NoError(suite.T(), err)
	assert.Equal(suite.T(), user.ID, authUser.ID)
	assert.Equal(suite.T(), user.Email, authUser.Email)
}

func (suite *AuthServiceTestSuite) TestAuthenticate_InvalidCredentials() {
	// Test data
	email := "test@example.com"
	password := "WrongPassword"
	
	user := &models.User{
		ID:             "user-123",
		Email:          email,
		HashedPassword: "hashed-password",
		IsActive:       true,
		FailedAttempts: 2,
		LastAttempt:    time.Now().Add(-5 * time.Minute),
	}

	// Mock expectations
	suite.mockUserRepo.EXPECT().
		GetByEmail(suite.ctx, email).
		Return(user, nil)

	suite.mockHasher.EXPECT().
		VerifyPassword(password, user.HashedPassword).
		Return(false)

	suite.mockUserRepo.EXPECT().
		UpdateLoginAttempts(suite.ctx, user.ID, 3, gomock.Any()).
		Return(nil)

	// Execute
	authUser, err := suite.authService.Authenticate(suite.ctx, email, password)

	// Verify
	assert.Nil(suite.T(), authUser)
	assert.Error(suite.T(), err)
	assert.Contains(suite.T(), err.Error(), "invalid credentials")
}

func (suite *AuthServiceTestSuite) TestAuthenticate_UserNotFound() {
	// Test data
	email := "nonexistent@example.com"
	password := "password"

	// Mock expectations
	suite.mockUserRepo.EXPECT().
		GetByEmail(suite.ctx, email).
		Return(nil, errors.ErrUserNotFound)

	// Execute
	authUser, err := suite.authService.Authenticate(suite.ctx, email, password)

	// Verify
	assert.Nil(suite.T(), authUser)
	assert.Error(suite.T(), err)
	assert.Contains(suite.T(), err.Error(), "invalid credentials")
}

func (suite *AuthServiceTestSuite) TestAuthenticate_AccountLocked() {
	// Test data
	email := "test@example.com"
	password := "password"
	
	user := &models.User{
		ID:             "user-123",
		Email:          email,
		HashedPassword: "hashed-password",
		IsActive:       true,
		FailedAttempts: 5, // Max attempts reached
		LastAttempt:    time.Now().Add(-5 * time.Minute), // Recent attempt
	}

	// Mock expectations
	suite.mockUserRepo.EXPECT().
		GetByEmail(suite.ctx, email).
		Return(user, nil)

	// Execute
	authUser, err := suite.authService.Authenticate(suite.ctx, email, password)

	// Verify
	assert.Nil(suite.T(), authUser)
	assert.Error(suite.T(), err)
	assert.Contains(suite.T(), err.Error(), "account temporarily locked")
}

func (suite *AuthServiceTestSuite) TestAuthenticate_InactiveUser() {
	// Test data
	email := "test@example.com"
	password := "password"
	
	user := &models.User{
		ID:             "user-123",
		Email:          email,
		HashedPassword: "hashed-password",
		IsActive:       false, // Inactive user
		FailedAttempts: 0,
	}

	// Mock expectations
	suite.mockUserRepo.EXPECT().
		GetByEmail(suite.ctx, email).
		Return(user, nil)

	// Execute
	authUser, err := suite.authService.Authenticate(suite.ctx, email, password)

	// Verify
	assert.Nil(suite.T(), authUser)
	assert.Error(suite.T(), err)
	assert.Contains(suite.T(), err.Error(), "account is inactive")
}

// Test token generation
func (suite *AuthServiceTestSuite) TestGenerateTokens_Success() {
	// Test data
	user := &models.User{
		ID:       "user-123",
		Email:    "test@example.com",
		TenantID: "tenant-123",
		Role:     "user",
	}

	// Execute
	tokens, err := suite.authService.GenerateTokens(user)

	// Verify
	require.NoError(suite.T(), err)
	assert.NotEmpty(suite.T(), tokens.AccessToken)
	assert.NotEmpty(suite.T(), tokens.RefreshToken)
	assert.Equal(suite.T(), "Bearer", tokens.TokenType)
	assert.Equal(suite.T(), int64(3600), tokens.ExpiresIn) // 1 hour in seconds
}

// Test token validation
func (suite *AuthServiceTestSuite) TestValidateToken_Success() {
	// Test data
	user := &models.User{
		ID:       "user-123",
		Email:    "test@example.com",
		TenantID: "tenant-123",
		Role:     "user",
	}

	// Generate a valid token
	tokens, err := suite.authService.GenerateTokens(user)
	require.NoError(suite.T(), err)

	// Mock expectations for token validation
	suite.mockTokenRepo.EXPECT().
		IsBlacklisted(suite.ctx, gomock.Any()).
		Return(false, nil)

	// Execute
	claims, err := suite.authService.ValidateAccessToken(suite.ctx, tokens.AccessToken)

	// Verify
	require.NoError(suite.T(), err)
	assert.Equal(suite.T(), user.ID, claims.UserID)
	assert.Equal(suite.T(), user.Email, claims.Email)
	assert.Equal(suite.T(), user.TenantID, claims.TenantID)
	assert.Equal(suite.T(), user.Role, claims.Role)
}

func (suite *AuthServiceTestSuite) TestValidateToken_InvalidToken() {
	// Test data
	invalidToken := "invalid.jwt.token"

	// Execute
	claims, err := suite.authService.ValidateAccessToken(suite.ctx, invalidToken)

	// Verify
	assert.Nil(suite.T(), claims)
	assert.Error(suite.T(), err)
	assert.Contains(suite.T(), err.Error(), "invalid token")
}

func (suite *AuthServiceTestSuite) TestValidateToken_BlacklistedToken() {
	// Test data
	user := &models.User{
		ID:       "user-123",
		Email:    "test@example.com",
		TenantID: "tenant-123",
		Role:     "user",
	}

	// Generate a valid token
	tokens, err := suite.authService.GenerateTokens(user)
	require.NoError(suite.T(), err)

	// Mock expectations for blacklisted token
	suite.mockTokenRepo.EXPECT().
		IsBlacklisted(suite.ctx, gomock.Any()).
		Return(true, nil)

	// Execute
	claims, err := suite.authService.ValidateAccessToken(suite.ctx, tokens.AccessToken)

	// Verify
	assert.Nil(suite.T(), claims)
	assert.Error(suite.T(), err)
	assert.Contains(suite.T(), err.Error(), "token has been revoked")
}

// Test token refresh
func (suite *AuthServiceTestSuite) TestRefreshToken_Success() {
	// Test data
	user := &models.User{
		ID:       "user-123",
		Email:    "test@example.com",
		TenantID: "tenant-123",
		Role:     "user",
		IsActive: true,
	}

	// Generate initial tokens
	tokens, err := suite.authService.GenerateTokens(user)
	require.NoError(suite.T(), err)

	// Mock expectations
	suite.mockTokenRepo.EXPECT().
		IsBlacklisted(suite.ctx, gomock.Any()).
		Return(false, nil)

	suite.mockUserRepo.EXPECT().
		GetByID(suite.ctx, user.ID).
		Return(user, nil)

	suite.mockTokenRepo.EXPECT().
		BlacklistToken(suite.ctx, gomock.Any(), gomock.Any()).
		Return(nil)

	// Execute
	newTokens, err := suite.authService.RefreshToken(suite.ctx, tokens.RefreshToken)

	// Verify
	require.NoError(suite.T(), err)
	assert.NotEmpty(suite.T(), newTokens.AccessToken)
	assert.NotEmpty(suite.T(), newTokens.RefreshToken)
	assert.NotEqual(suite.T(), tokens.AccessToken, newTokens.AccessToken)
	assert.NotEqual(suite.T(), tokens.RefreshToken, newTokens.RefreshToken)
}

func (suite *AuthServiceTestSuite) TestRefreshToken_InvalidToken() {
	// Test data
	invalidRefreshToken := "invalid.refresh.token"

	// Execute
	newTokens, err := suite.authService.RefreshToken(suite.ctx, invalidRefreshToken)

	// Verify
	assert.Nil(suite.T(), newTokens)
	assert.Error(suite.T(), err)
	assert.Contains(suite.T(), err.Error(), "invalid refresh token")
}

// Test logout
func (suite *AuthServiceTestSuite) TestLogout_Success() {
	// Test data
	user := &models.User{
		ID:       "user-123",
		Email:    "test@example.com",
		TenantID: "tenant-123",
		Role:     "user",
	}

	// Generate tokens
	tokens, err := suite.authService.GenerateTokens(user)
	require.NoError(suite.T(), err)

	// Mock expectations
	suite.mockTokenRepo.EXPECT().
		BlacklistToken(suite.ctx, gomock.Any(), gomock.Any()).
		Return(nil).
		Times(2) // Both access and refresh tokens

	// Execute
	err = suite.authService.Logout(suite.ctx, tokens.AccessToken, tokens.RefreshToken)

	// Verify
	assert.NoError(suite.T(), err)
}

// Test password strength validation
func (suite *AuthServiceTestSuite) TestValidatePasswordStrength() {
	testCases := []struct {
		name     string
		password string
		valid    bool
	}{
		{"Valid strong password", "SecurePassword123!", true},
		{"Too short", "Short1!", false},
		{"No uppercase", "nouppercase123!", false},
		{"No lowercase", "NOLOWERCASE123!", false},
		{"No numbers", "NoNumbersHere!", false},
		{"No special chars", "NoSpecialChars123", false},
		{"Common password", "Password123!", false},
		{"Sequential chars", "abcd1234!", false},
	}

	for _, tc := range testCases {
		suite.T().Run(tc.name, func(t *testing.T) {
			err := suite.authService.validatePasswordStrength(tc.password)
			if tc.valid {
				assert.NoError(t, err)
			} else {
				assert.Error(t, err)
			}
		})
	}
}

// Benchmark tests
func BenchmarkAuthService_Authenticate(b *testing.B) {
	ctrl := gomock.NewController(b)
	defer ctrl.Finish()

	mockUserRepo := mocks.NewMockUserRepository(ctrl)
	mockTokenRepo := mocks.NewMockTokenRepository(ctrl)
	mockHasher := mocks.NewMockPasswordHasher(ctrl)

	authService := &AuthService{
		userRepo:                mockUserRepo,
		tokenRepo:              mockTokenRepo,
		hasher:                 mockHasher,
		jwtSecret:              "test-secret",
		accessTokenExpiration:  time.Hour,
		refreshTokenExpiration: 24 * time.Hour,
	}

	user := &models.User{
		ID:             "user-123",
		Email:          "test@example.com",
		HashedPassword: "hashed-password",
		IsActive:       true,
	}

	mockUserRepo.EXPECT().GetByEmail(gomock.Any(), gomock.Any()).Return(user, nil).AnyTimes()
	mockHasher.EXPECT().VerifyPassword(gomock.Any(), gomock.Any()).Return(true).AnyTimes()
	mockUserRepo.EXPECT().UpdateLoginAttempts(gomock.Any(), gomock.Any(), gomock.Any(), gomock.Any()).Return(nil).AnyTimes()

	ctx := context.Background()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = authService.Authenticate(ctx, "test@example.com", "password")
	}
}

func BenchmarkAuthService_GenerateTokens(b *testing.B) {
	authService := &AuthService{
		jwtSecret:              "test-secret",
		accessTokenExpiration:  time.Hour,
		refreshTokenExpiration: 24 * time.Hour,
	}

	user := &models.User{
		ID:       "user-123",
		Email:    "test@example.com",
		TenantID: "tenant-123",
		Role:     "user",
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = authService.GenerateTokens(user)
	}
}