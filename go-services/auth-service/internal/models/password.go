package models

import (
	"github.com/gofiber/fiber/v2"
	"golang.org/x/crypto/bcrypt"
)

// PasswordPolicy defines password complexity requirements
type PasswordPolicy struct {
	MinLength     int
	RequireUpper  bool
	RequireLower  bool
	RequireDigit  bool
	RequireSymbol bool
}

// DefaultPasswordPolicy returns a secure default password policy
func DefaultPasswordPolicy() *PasswordPolicy {
	return &PasswordPolicy{
		MinLength:     8,
		RequireUpper:  true,
		RequireLower:  true,
		RequireDigit:  true,
		RequireSymbol: false, // Optional for better UX
	}
}

// ValidatePassword checks if password meets policy requirements
func (pp *PasswordPolicy) ValidatePassword(password string) error {
	if len(password) < pp.MinLength {
		return fiber.NewError(fiber.StatusBadRequest,
			"Password must be at least 8 characters long")
	}

	hasUpper := false
	hasLower := false
	hasDigit := false
	hasSymbol := false

	for _, char := range password {
		switch {
		case char >= 'A' && char <= 'Z':
			hasUpper = true
		case char >= 'a' && char <= 'z':
			hasLower = true
		case char >= '0' && char <= '9':
			hasDigit = true
		case !((char >= 'A' && char <= 'Z') || (char >= 'a' && char <= 'z') || (char >= '0' && char <= '9')):
			hasSymbol = true
		}
	}

	if pp.RequireUpper && !hasUpper {
		return fiber.NewError(fiber.StatusBadRequest,
			"Password must contain at least one uppercase letter")
	}

	if pp.RequireLower && !hasLower {
		return fiber.NewError(fiber.StatusBadRequest,
			"Password must contain at least one lowercase letter")
	}

	if pp.RequireDigit && !hasDigit {
		return fiber.NewError(fiber.StatusBadRequest,
			"Password must contain at least one digit")
	}

	if pp.RequireSymbol && !hasSymbol {
		return fiber.NewError(fiber.StatusBadRequest,
			"Password must contain at least one special character")
	}

	return nil
}

// HashPasswordWithPolicy validates and hashes a password
func (pp *PasswordPolicy) HashPasswordWithPolicy(password string) (string, error) {
	if err := pp.ValidatePassword(password); err != nil {
		return "", err
	}

	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(bytes), err
}