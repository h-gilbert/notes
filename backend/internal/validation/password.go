package validation

import (
	"errors"
	"strings"
	"unicode"
)

// Password validation errors
var (
	ErrPasswordTooShort     = errors.New("password must be at least 12 characters")
	ErrPasswordTooLong      = errors.New("password must be at most 128 characters")
	ErrPasswordNoUppercase  = errors.New("password must contain at least one uppercase letter")
	ErrPasswordNoLowercase  = errors.New("password must contain at least one lowercase letter")
	ErrPasswordNoDigit      = errors.New("password must contain at least one digit")
	ErrPasswordNoSpecial    = errors.New("password must contain at least one special character")
)

// PasswordRequirements holds the password policy requirements
type PasswordRequirements struct {
	MinLength        int
	MaxLength        int
	RequireUppercase bool
	RequireLowercase bool
	RequireDigit     bool
	RequireSpecial   bool
}

// DefaultPasswordRequirements returns the default password policy
func DefaultPasswordRequirements() PasswordRequirements {
	return PasswordRequirements{
		MinLength:        12,
		MaxLength:        128,
		RequireUppercase: true,
		RequireLowercase: true,
		RequireDigit:     true,
		RequireSpecial:   true,
	}
}

// ValidatePassword validates a password against the requirements
func ValidatePassword(password string, req PasswordRequirements) error {
	// Check length
	if len(password) < req.MinLength {
		return ErrPasswordTooShort
	}
	if len(password) > req.MaxLength {
		return ErrPasswordTooLong
	}

	var (
		hasUppercase bool
		hasLowercase bool
		hasDigit     bool
		hasSpecial   bool
	)

	for _, char := range password {
		switch {
		case unicode.IsUpper(char):
			hasUppercase = true
		case unicode.IsLower(char):
			hasLowercase = true
		case unicode.IsDigit(char):
			hasDigit = true
		case isSpecialChar(char):
			hasSpecial = true
		}
	}

	if req.RequireUppercase && !hasUppercase {
		return ErrPasswordNoUppercase
	}
	if req.RequireLowercase && !hasLowercase {
		return ErrPasswordNoLowercase
	}
	if req.RequireDigit && !hasDigit {
		return ErrPasswordNoDigit
	}
	if req.RequireSpecial && !hasSpecial {
		return ErrPasswordNoSpecial
	}

	return nil
}

// ValidatePasswordDefault validates using default requirements
func ValidatePasswordDefault(password string) error {
	return ValidatePassword(password, DefaultPasswordRequirements())
}

// isSpecialChar checks if a character is a special character
func isSpecialChar(char rune) bool {
	specialChars := "!@#$%^&*()_+-=[]{}|;':\",./<>?`~"
	return strings.ContainsRune(specialChars, char)
}

// PasswordRequirementsMessage returns a human-readable description of password requirements
func PasswordRequirementsMessage() string {
	return "Password must be 12-128 characters and contain at least one uppercase letter, one lowercase letter, one digit, and one special character (!@#$%^&*()_+-=[]{}|;':\",./<>?`~)"
}
