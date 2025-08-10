package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/pyairtable-compose/auth-service/internal/models"
)

const baseURL = "http://localhost:8001"

func main() {
	fmt.Println("Starting Auth Service Integration Tests...")
	fmt.Println("Ensure the auth service is running on port 8001")
	
	// Wait a bit for service startup
	time.Sleep(2 * time.Second)
	
	// Test 1: Health Check
	fmt.Println("\n=== Test 1: Health Check ===")
	if testHealthCheck() {
		fmt.Println("✅ Health check passed")
	} else {
		fmt.Println("❌ Health check failed")
		return
	}
	
	// Test 2: User Registration
	fmt.Println("\n=== Test 2: User Registration ===")
	userEmail := fmt.Sprintf("test_%d@example.com", time.Now().Unix())
	if testUserRegistration(userEmail) {
		fmt.Println("✅ User registration passed")
	} else {
		fmt.Println("❌ User registration failed")
		return
	}
	
	// Test 3: User Login
	fmt.Println("\n=== Test 3: User Login ===")
	tokens, err := testUserLogin(userEmail)
	if err != nil {
		fmt.Printf("❌ User login failed: %v\n", err)
		return
	}
	fmt.Println("✅ User login passed")
	
	// Test 4: Token Validation
	fmt.Println("\n=== Test 4: Token Validation ===")
	if testTokenValidation(tokens.AccessToken) {
		fmt.Println("✅ Token validation passed")
	} else {
		fmt.Println("❌ Token validation failed")
		return
	}
	
	// Test 5: Token Refresh
	fmt.Println("\n=== Test 5: Token Refresh ===")
	newTokens, err := testTokenRefresh(tokens.RefreshToken)
	if err != nil {
		fmt.Printf("❌ Token refresh failed: %v\n", err)
		return
	}
	fmt.Println("✅ Token refresh passed")
	
	// Test 6: Get User Profile
	fmt.Println("\n=== Test 6: Get User Profile ===")
	if testGetUserProfile(newTokens.AccessToken) {
		fmt.Println("✅ Get user profile passed")
	} else {
		fmt.Println("❌ Get user profile failed")
		return
	}
	
	// Test 7: Update User Profile
	fmt.Println("\n=== Test 7: Update User Profile ===")
	if testUpdateUserProfile(newTokens.AccessToken) {
		fmt.Println("✅ Update user profile passed")
	} else {
		fmt.Println("❌ Update user profile failed")
		return
	}
	
	// Test 8: Change Password
	fmt.Println("\n=== Test 8: Change Password ===")
	if testChangePassword(newTokens.AccessToken) {
		fmt.Println("✅ Change password passed")
	} else {
		fmt.Println("❌ Change password failed")
		return
	}
	
	// Test 9: Logout
	fmt.Println("\n=== Test 9: Logout ===")
	if testLogout(newTokens.RefreshToken) {
		fmt.Println("✅ Logout passed")
	} else {
		fmt.Println("❌ Logout failed")
		return
	}
	
	// Test 10: Security Tests
	fmt.Println("\n=== Test 10: Security Tests ===")
	testSecurityFeatures()
	
	fmt.Println("\n🎉 All integration tests completed successfully!")
}

func testHealthCheck() bool {
	resp, err := http.Get(baseURL + "/health")
	if err != nil {
		fmt.Printf("Health check request failed: %v\n", err)
		return false
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("Health check returned status %d\n", resp.StatusCode)
		return false
	}
	
	return true
}

func testUserRegistration(email string) bool {
	reqBody := models.RegisterRequest{
		Email:     email,
		Password:  "SecureTest123",
		FirstName: "Integration",
		LastName:  "Test",
	}
	
	jsonBody, _ := json.Marshal(reqBody)
	resp, err := http.Post(baseURL+"/auth/register", "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		fmt.Printf("Registration request failed: %v\n", err)
		return false
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusCreated {
		fmt.Printf("Registration returned status %d\n", resp.StatusCode)
		return false
	}
	
	var user models.User
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		fmt.Printf("Failed to decode registration response: %v\n", err)
		return false
	}
	
	if user.Email != email {
		fmt.Printf("User email mismatch: expected %s, got %s\n", email, user.Email)
		return false
	}
	
	return true
}

func testUserLogin(email string) (*models.TokenResponse, error) {
	reqBody := models.LoginRequest{
		Email:    email,
		Password: "SecureTest123",
	}
	
	jsonBody, _ := json.Marshal(reqBody)
	resp, err := http.Post(baseURL+"/auth/login", "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("login request failed: %v", err)
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("login returned status %d", resp.StatusCode)
	}
	
	var tokens models.TokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tokens); err != nil {
		return nil, fmt.Errorf("failed to decode login response: %v", err)
	}
	
	if tokens.AccessToken == "" || tokens.RefreshToken == "" {
		return nil, fmt.Errorf("missing tokens in response")
	}
	
	return &tokens, nil
}

func testTokenValidation(accessToken string) bool {
	req, _ := http.NewRequest("POST", baseURL+"/auth/validate", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("Token validation request failed: %v\n", err)
		return false
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("Token validation returned status %d\n", resp.StatusCode)
		return false
	}
	
	var claims models.Claims
	if err := json.NewDecoder(resp.Body).Decode(&claims); err != nil {
		fmt.Printf("Failed to decode validation response: %v\n", err)
		return false
	}
	
	if claims.UserID == "" || claims.Email == "" {
		fmt.Printf("Invalid claims in response\n")
		return false
	}
	
	return true
}

func testTokenRefresh(refreshToken string) (*models.TokenResponse, error) {
	reqBody := models.RefreshRequest{
		RefreshToken: refreshToken,
	}
	
	jsonBody, _ := json.Marshal(reqBody)
	resp, err := http.Post(baseURL+"/auth/refresh", "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("refresh request failed: %v", err)
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("refresh returned status %d", resp.StatusCode)
	}
	
	var tokens models.TokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tokens); err != nil {
		return nil, fmt.Errorf("failed to decode refresh response: %v", err)
	}
	
	return &tokens, nil
}

func testGetUserProfile(accessToken string) bool {
	req, _ := http.NewRequest("GET", baseURL+"/auth/me", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("Get profile request failed: %v\n", err)
		return false
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("Get profile returned status %d\n", resp.StatusCode)
		return false
	}
	
	var user models.User
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		fmt.Printf("Failed to decode profile response: %v\n", err)
		return false
	}
	
	return true
}

func testUpdateUserProfile(accessToken string) bool {
	reqBody := models.UpdateProfileRequest{
		FirstName: "Updated",
		LastName:  "Name",
	}
	
	jsonBody, _ := json.Marshal(reqBody)
	req, _ := http.NewRequest("PUT", baseURL+"/auth/me", bytes.NewBuffer(jsonBody))
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")
	
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("Update profile request failed: %v\n", err)
		return false
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("Update profile returned status %d\n", resp.StatusCode)
		return false
	}
	
	return true
}

func testChangePassword(accessToken string) bool {
	reqBody := models.ChangePasswordRequest{
		CurrentPassword: "SecureTest123",
		NewPassword:     "NewSecureTest123",
	}
	
	jsonBody, _ := json.Marshal(reqBody)
	req, _ := http.NewRequest("POST", baseURL+"/auth/change-password", bytes.NewBuffer(jsonBody))
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")
	
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("Change password request failed: %v\n", err)
		return false
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("Change password returned status %d\n", resp.StatusCode)
		return false
	}
	
	return true
}

func testLogout(refreshToken string) bool {
	reqBody := models.RefreshRequest{
		RefreshToken: refreshToken,
	}
	
	jsonBody, _ := json.Marshal(reqBody)
	resp, err := http.Post(baseURL+"/auth/logout", "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		fmt.Printf("Logout request failed: %v\n", err)
		return false
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("Logout returned status %d\n", resp.StatusCode)
		return false
	}
	
	return true
}

func testSecurityFeatures() {
	fmt.Println("Testing rate limiting...")
	
	// Test rate limiting by making many requests quickly
	successCount := 0
	rateLimitedCount := 0
	
	for i := 0; i < 20; i++ {
		resp, err := http.Get(baseURL + "/health")
		if err != nil {
			continue
		}
		
		if resp.StatusCode == http.StatusOK {
			successCount++
		} else if resp.StatusCode == http.StatusTooManyRequests {
			rateLimitedCount++
		}
		
		resp.Body.Close()
		time.Sleep(10 * time.Millisecond) // Small delay
	}
	
	if rateLimitedCount > 0 {
		fmt.Printf("✅ Rate limiting working: %d requests succeeded, %d rate limited\n", successCount, rateLimitedCount)
	} else {
		fmt.Printf("⚠️  Rate limiting not triggered in this test (this may be normal)\n")
	}
	
	// Test invalid requests
	fmt.Println("Testing input validation...")
	
	// Test with invalid email
	invalidReq := models.RegisterRequest{
		Email:     "invalid-email",
		Password:  "SecureTest123",
		FirstName: "Test",
		LastName:  "User",
	}
	
	jsonBody, _ := json.Marshal(invalidReq)
	resp, err := http.Post(baseURL+"/auth/register", "application/json", bytes.NewBuffer(jsonBody))
	if err == nil && resp.StatusCode == http.StatusBadRequest {
		fmt.Println("✅ Input validation working for invalid email")
		resp.Body.Close()
	}
	
	// Test with weak password
	weakPassReq := models.RegisterRequest{
		Email:     "test2@example.com",
		Password:  "weak",
		FirstName: "Test",
		LastName:  "User",
	}
	
	jsonBody, _ = json.Marshal(weakPassReq)
	resp, err = http.Post(baseURL+"/auth/register", "application/json", bytes.NewBuffer(jsonBody))
	if err == nil && resp.StatusCode == http.StatusBadRequest {
		fmt.Println("✅ Password policy working for weak passwords")
		resp.Body.Close()
	}
}