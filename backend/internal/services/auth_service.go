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
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrUserExists         = errors.New("username already exists")
	ErrInvalidToken       = errors.New("invalid token")
	ErrTokenExpired       = errors.New("token expired")
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
	jwtSecret     []byte
	accessExpiry  time.Duration
	refreshExpiry time.Duration
}

func NewAuthService(userRepo *repository.UserRepository, jwtSecret string, accessExpiryMinutes int, refreshExpiryHours int) *AuthService {
	return &AuthService{
		userRepo:      userRepo,
		jwtSecret:     []byte(jwtSecret),
		accessExpiry:  time.Duration(accessExpiryMinutes) * time.Minute,
		refreshExpiry: time.Duration(refreshExpiryHours) * time.Hour,
	}
}

func (s *AuthService) Register(ctx context.Context, username, password string, clientIP string) (*models.User, *TokenPair, error) {
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

	return userID, nil
}

// ValidateRefreshToken validates a refresh token and returns the user ID
func (s *AuthService) ValidateRefreshToken(tokenString string) (uuid.UUID, error) {
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

	return userID, nil
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
func (s *AuthService) RefreshTokenPair(refreshToken string, clientIP string) (*TokenPair, error) {
	userID, err := s.ValidateRefreshToken(refreshToken)
	if err != nil {
		log.Printf("[SECURITY] Failed token refresh attempt from IP: %s - %v", clientIP, err)
		return nil, err
	}

	tokens, err := s.generateTokenPair(userID)
	if err != nil {
		return nil, err
	}

	log.Printf("[SECURITY] Token refreshed for user: %s from IP: %s", userID.String(), clientIP)
	return tokens, nil
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
