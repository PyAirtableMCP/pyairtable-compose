package main

import (
	"fmt"

	"github.com/pyairtable-compose/auth-service/internal/models"
)


func main() {
	fmt.Println("Running auth service tests...")
	
	// Run password policy tests
	fmt.Println("Testing password policy...")
	policy := models.DefaultPasswordPolicy()
	
	tests := []struct {
		password string
		valid    bool
	}{
		{"short", false},
		{"nouppercase123", false},
		{"NOLOWERCASE123", false},
		{"NoDigitsHere", false},
		{"SecurePass123", true},
		{"AnotherGood1", true},
	}
	
	for _, test := range tests {
		err := policy.ValidatePassword(test.password)
		if (err == nil) != test.valid {
			fmt.Printf("FAIL: Password '%s' expected valid=%v but got err=%v\n", test.password, test.valid, err)
		} else {
			fmt.Printf("PASS: Password '%s' validation correct\n", test.password)
		}
	}
	
	// Test password hashing
	fmt.Println("Testing password hashing...")
	password := "TestPass123"
	hash, err := models.HashPassword(password)
	if err != nil {
		fmt.Printf("FAIL: Error hashing password: %v\n", err)
		return
	}
	
	if models.CheckPassword(password, hash) {
		fmt.Println("PASS: Password hashing and verification works")
	} else {
		fmt.Println("FAIL: Password verification failed")
	}
	
	if models.CheckPassword("wrongpassword", hash) {
		fmt.Println("FAIL: Wrong password verification passed (should fail)")
	} else {
		fmt.Println("PASS: Wrong password correctly rejected")
	}
	
	fmt.Println("Basic auth service tests completed!")
}