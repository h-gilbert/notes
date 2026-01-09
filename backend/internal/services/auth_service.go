package services

import (
	"context"
	"errors"
	"log"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/hamishgilbert/notes-app/backend/internal/models"
	"github.com/hamishgilbert/notes-app/backend/internal/repository"
	"github.com/hamishgilbert/notes-app/backend/internal/validation"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrUserExists         = errors.New("username already exists")
	ErrInvalidToken       = errors.New("invalid token")
	ErrTokenExpired       = errors.New("token expired")
	ErrTokenRevoked       = errors.New("token revoked")
	ErrPasswordMismatch   = errors.New("current password is incorrect")
	ErrWeakPassword       = errors.New("password does not meet complexity requirements")
)

// TokenType represents the type of JWT token
type TokenType string

const (
	AccessToken  TokenType = "access"
	RefreshToken TokenType = "refresh"
)

// TokenPair contains both access and refresh tokens
type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"` // seconds until access token expires
}

// Claims represents the JWT claims
type Claims struct {
	jwt.RegisteredClaims
	TokenType TokenType `json:"type"`
}

type AuthService struct {
	userRepo      *repository.UserRepository
	blacklistRepo *repository.TokenBlacklistRepository
	jwtSecret     []byte
	accessExpiry  time.Duration
	refreshExpiry time.Duration
}

func NewAuthService(userRepo *repository.UserRepository, blacklistRepo *repository.TokenBlacklistRepository, jwtSecret string, accessExpiryMinutes int, refreshExpiryHours int) *AuthService {
	return &AuthService{
		userRepo:      userRepo,
		blacklistRepo: blacklistRepo,
		jwtSecret:     []byte(jwtSecret),
		accessExpiry:  time.Duration(accessExpiryMinutes) * time.Minute,
		refreshExpiry: time.Duration(refreshExpiryHours) * time.Hour,
	}
}

func (s *AuthService) Register(ctx context.Context, username, password string, clientIP string) (*models.User, *TokenPair, error) {
	// Validate password complexity
	if err := validation.ValidatePasswordDefault(password); err != nil {
		log.Printf("[SECURITY] Registration rejected - weak password for username: %s from IP: %s - %v", username, clientIP, err)
		return nil, nil, ErrWeakPassword
	}

	// Check if user exists
	_, err := s.userRepo.GetByUsername(ctx, username)
	if err == nil {
		log.Printf("[SECURITY] Registration attempt with existing username: %s from IP: %s", username, clientIP)
		return nil, nil, ErrUserExists
	}
	if !errors.Is(err, repository.ErrUserNotFound) {
		return nil, nil, err
	}

	// Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, nil, err
	}

	// Create user
	now := time.Now()
	user := &models.User{
		ID:           uuid.New(),
		Username:     username,
		PasswordHash: string(hashedPassword),
		CreatedAt:    now,
		UpdatedAt:    now,
	}

	if err := s.userRepo.Create(ctx, user); err != nil {
		if errors.Is(err, repository.ErrUserExists) {
			return nil, nil, ErrUserExists
		}
		return nil, nil, err
	}

	// Generate token pair
	tokens, err := s.generateTokenPair(user.ID)
	if err != nil {
		return nil, nil, err
	}

	log.Printf("[SECURITY] User registered successfully: %s from IP: %s", username, clientIP)
	return user, tokens, nil
}

func (s *AuthService) Login(ctx context.Context, username, password string, clientIP string) (*models.User, *TokenPair, error) {
	user, err := s.userRepo.GetByUsername(ctx, username)
	if err != nil {
		if errors.Is(err, repository.ErrUserNotFound) {
			log.Printf("[SECURITY] Failed login attempt - user not found: %s from IP: %s", username, clientIP)
			return nil, nil, ErrInvalidCredentials
		}
		return nil, nil, err
	}

	// Compare password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		log.Printf("[SECURITY] Failed login attempt - invalid password for user: %s from IP: %s", username, clientIP)
		return nil, nil, ErrInvalidCredentials
	}

	// Generate token pair
	tokens, err := s.generateTokenPair(user.ID)
	if err != nil {
		return nil, nil, err
	}

	log.Printf("[SECURITY] Successful login: %s from IP: %s", username, clientIP)
	return user, tokens, nil
}

// ValidateToken validates an access token and returns the user ID
func (s *AuthService) ValidateToken(tokenString string) (uuid.UUID, error) {
	return s.ValidateTokenWithContext(context.Background(), tokenString)
}

// ValidateTokenWithContext validates an access token with context and returns the user ID
func (s *AuthService) ValidateTokenWithContext(ctx context.Context, tokenString string) (uuid.UUID, error) {
	claims, err := s.parseAndValidateToken(tokenString)
	if err != nil {
		return uuid.Nil, err
	}

	// Ensure it's an access token
	if claims.TokenType != AccessToken {
		return uuid.Nil, ErrInvalidToken
	}

	userID, err := uuid.Parse(claims.Subject)
	if err != nil {
		return uuid.Nil, ErrInvalidToken
	}

	// Check if token is revoked
	if err := s.checkTokenRevoked(ctx, claims, userID); err != nil {
		return uuid.Nil, err
	}

	return userID, nil
}

// ValidateRefreshToken validates a refresh token and returns the user ID
func (s *AuthService) ValidateRefreshToken(tokenString string) (uuid.UUID, error) {
	return s.ValidateRefreshTokenWithContext(context.Background(), tokenString)
}

// ValidateRefreshTokenWithContext validates a refresh token with context and returns the user ID and token ID
func (s *AuthService) ValidateRefreshTokenWithContext(ctx context.Context, tokenString string) (uuid.UUID, error) {
	claims, err := s.parseAndValidateToken(tokenString)
	if err != nil {
		return uuid.Nil, err
	}

	// Ensure it's a refresh token
	if claims.TokenType != RefreshToken {
		return uuid.Nil, ErrInvalidToken
	}

	userID, err := uuid.Parse(claims.Subject)
	if err != nil {
		return uuid.Nil, ErrInvalidToken
	}

	// Check if token is revoked
	if err := s.checkTokenRevoked(ctx, claims, userID); err != nil {
		return uuid.Nil, err
	}

	return userID, nil
}

// checkTokenRevoked checks if a token has been revoked
func (s *AuthService) checkTokenRevoked(ctx context.Context, claims *Claims, userID uuid.UUID) error {
	if s.blacklistRepo == nil {
		return nil // Blacklist not configured, skip check
	}

	// Check if specific token is revoked
	if claims.ID != "" {
		revoked, err := s.blacklistRepo.IsTokenRevoked(ctx, claims.ID)
		if err != nil {
			log.Printf("[ERROR] Failed to check token blacklist: %v", err)
			// Fail open for now - in production you might want to fail closed
			return nil
		}
		if revoked {
			log.Printf("[SECURITY] Revoked token used for user: %s", userID.String())
			return ErrTokenRevoked
		}
	}

	// Check if all tokens before a certain time are revoked
	revokeAllTime, err := s.blacklistRepo.GetUserRevokeAllTime(ctx, userID)
	if err != nil {
		log.Printf("[ERROR] Failed to check revoke-all time: %v", err)
		return nil
	}
	if !revokeAllTime.IsZero() && claims.IssuedAt != nil {
		if claims.IssuedAt.Time.Before(revokeAllTime) {
			log.Printf("[SECURITY] Token issued before revoke-all time used for user: %s", userID.String())
			return ErrTokenRevoked
		}
	}

	return nil
}

func (s *AuthService) parseAndValidateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, ErrInvalidToken
		}
		return s.jwtSecret, nil
	})

	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, ErrTokenExpired
		}
		return nil, ErrInvalidToken
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	return claims, nil
}

func (s *AuthService) GetUserByID(ctx context.Context, id uuid.UUID) (*models.User, error) {
	return s.userRepo.GetByID(ctx, id)
}

// RefreshTokenPair generates a new token pair using a valid refresh token
// Implements token rotation: the old refresh token is revoked after issuing new tokens
func (s *AuthService) RefreshTokenPair(ctx context.Context, refreshToken string, clientIP string) (*TokenPair, error) {
	// Parse the refresh token to get claims (including token ID for revocation)
	claims, err := s.parseAndValidateToken(refreshToken)
	if err != nil {
		log.Printf("[SECURITY] Failed token refresh attempt from IP: %s - %v", clientIP, err)
		return nil, err
	}

	if claims.TokenType != RefreshToken {
		return nil, ErrInvalidToken
	}

	userID, err := uuid.Parse(claims.Subject)
	if err != nil {
		return nil, ErrInvalidToken
	}

	// Check if token is revoked
	if err := s.checkTokenRevoked(ctx, claims, userID); err != nil {
		log.Printf("[SECURITY] Revoked refresh token used from IP: %s", clientIP)
		return nil, err
	}

	// Generate new token pair
	tokens, err := s.generateTokenPair(userID)
	if err != nil {
		return nil, err
	}

	// Token rotation: revoke the old refresh token
	if s.blacklistRepo != nil && claims.ID != "" && claims.ExpiresAt != nil {
		if err := s.blacklistRepo.RevokeToken(ctx, claims.ID, userID, claims.ExpiresAt.Time); err != nil {
			log.Printf("[ERROR] Failed to revoke old refresh token: %v", err)
			// Don't fail the refresh, just log the error
		}
	}

	log.Printf("[SECURITY] Token refreshed for user: %s from IP: %s", userID.String(), clientIP)
	return tokens, nil
}

// Logout revokes the given access and refresh tokens
func (s *AuthService) Logout(ctx context.Context, accessToken, refreshToken string, clientIP string) error {
	if s.blacklistRepo == nil {
		return nil // Blacklist not configured
	}

	// Revoke access token
	if accessToken != "" {
		claims, err := s.parseAndValidateToken(accessToken)
		if err == nil && claims.ID != "" {
			userID, _ := uuid.Parse(claims.Subject)
			if claims.ExpiresAt != nil {
				if err := s.blacklistRepo.RevokeToken(ctx, claims.ID, userID, claims.ExpiresAt.Time); err != nil {
					log.Printf("[ERROR] Failed to revoke access token: %v", err)
				}
			}
		}
	}

	// Revoke refresh token
	if refreshToken != "" {
		claims, err := s.parseAndValidateToken(refreshToken)
		if err == nil && claims.ID != "" {
			userID, _ := uuid.Parse(claims.Subject)
			if claims.ExpiresAt != nil {
				if err := s.blacklistRepo.RevokeToken(ctx, claims.ID, userID, claims.ExpiresAt.Time); err != nil {
					log.Printf("[ERROR] Failed to revoke refresh token: %v", err)
				}
			}
			log.Printf("[SECURITY] User logged out: %s from IP: %s", userID.String(), clientIP)
		}
	}

	return nil
}

// LogoutAll revokes all tokens for a user (logout everywhere)
func (s *AuthService) LogoutAll(ctx context.Context, userID uuid.UUID, clientIP string) error {
	if s.blacklistRepo == nil {
		return nil // Blacklist not configured
	}

	if err := s.blacklistRepo.RevokeAllUserTokens(ctx, userID, time.Now()); err != nil {
		log.Printf("[ERROR] Failed to revoke all tokens for user %s: %v", userID.String(), err)
		return err
	}

	log.Printf("[SECURITY] All tokens revoked for user: %s from IP: %s", userID.String(), clientIP)
	return nil
}

// ChangePassword changes a user's password after verifying the current password
func (s *AuthService) ChangePassword(ctx context.Context, userID uuid.UUID, currentPassword, newPassword, clientIP string) error {
	// Validate new password complexity
	if err := validation.ValidatePasswordDefault(newPassword); err != nil {
		log.Printf("[SECURITY] Password change rejected - weak password for user ID: %s from IP: %s - %v", userID.String(), clientIP, err)
		return ErrWeakPassword
	}

	// Get user
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return err
	}

	// Verify current password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(currentPassword)); err != nil {
		log.Printf("[SECURITY] Failed password change attempt - invalid current password for user: %s from IP: %s", user.Username, clientIP)
		return ErrPasswordMismatch
	}

	// Hash new password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	// Update password
	if err := s.userRepo.UpdatePassword(ctx, userID, string(hashedPassword)); err != nil {
		return err
	}

	log.Printf("[SECURITY] Password changed successfully for user: %s from IP: %s", user.Username, clientIP)
	return nil
}

// CleanupExpiredTokens removes expired tokens from the blacklist
func (s *AuthService) CleanupExpiredTokens(ctx context.Context) (int64, error) {
	if s.blacklistRepo == nil {
		return 0, nil
	}
	return s.blacklistRepo.CleanupExpired(ctx)
}

// GenerateAccessToken generates only an access token (for backward compatibility)
func (s *AuthService) GenerateAccessToken(userID uuid.UUID) (string, error) {
	return s.generateToken(userID, AccessToken, s.accessExpiry)
}

func (s *AuthService) generateTokenPair(userID uuid.UUID) (*TokenPair, error) {
	accessToken, err := s.generateToken(userID, AccessToken, s.accessExpiry)
	if err != nil {
		return nil, err
	}

	refreshToken, err := s.generateToken(userID, RefreshToken, s.refreshExpiry)
	if err != nil {
		return nil, err
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int(s.accessExpiry.Seconds()),
	}, nil
}

func (s *AuthService) generateToken(userID uuid.UUID, tokenType TokenType, expiry time.Duration) (string, error) {
	now := time.Now()
	claims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID.String(),
			ExpiresAt: jwt.NewNumericDate(now.Add(expiry)),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ID:        uuid.New().String(), // Unique token ID for revocation support
		},
		TokenType: tokenType,
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.jwtSecret)
}
