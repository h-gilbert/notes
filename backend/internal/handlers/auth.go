package handlers

import (
	"errors"

	"github.com/gin-gonic/gin"
	"github.com/hamishgilbert/notes-app/backend/internal/middleware"
	"github.com/hamishgilbert/notes-app/backend/internal/models"
	"github.com/hamishgilbert/notes-app/backend/internal/services"
	"github.com/hamishgilbert/notes-app/backend/pkg/response"
)

type AuthHandler struct {
	authService *services.AuthService
}

func NewAuthHandler(authService *services.AuthService) *AuthHandler {
	return &AuthHandler{authService: authService}
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req models.AuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request: username must be 3-50 alphanumeric characters, password must be 12-128 characters")
		return
	}

	clientIP := c.ClientIP()
	user, tokens, err := h.authService.Register(c.Request.Context(), req.Username, req.Password, clientIP)
	if err != nil {
		if errors.Is(err, services.ErrUserExists) {
			// Record failed attempt for rate limiting
			if al, exists := c.Get("authRateLimiter"); exists {
				al.(*middleware.AuthRateLimiter).RecordFailedAttempt(clientIP)
			}
			response.Conflict(c, "username already exists")
			return
		}
		if errors.Is(err, services.ErrWeakPassword) {
			response.BadRequest(c, "password does not meet complexity requirements: must be 12-128 characters with at least one uppercase letter, one lowercase letter, one digit, and one special character")
			return
		}
		response.InternalError(c, "failed to register user")
		return
	}

	response.Created(c, models.AuthResponse{
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
		ExpiresIn:    tokens.ExpiresIn,
		TokenType:    "Bearer",
		User: models.UserDTO{
			ID:       user.ID.String(),
			Username: user.Username,
		},
	})
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req models.AuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request body")
		return
	}

	clientIP := c.ClientIP()
	user, tokens, err := h.authService.Login(c.Request.Context(), req.Username, req.Password, clientIP)
	if err != nil {
		if errors.Is(err, services.ErrInvalidCredentials) {
			// Record failed attempt for rate limiting
			if al, exists := c.Get("authRateLimiter"); exists {
				al.(*middleware.AuthRateLimiter).RecordFailedAttempt(clientIP)
			}
			response.Unauthorized(c, "invalid username or password")
			return
		}
		response.InternalError(c, "failed to login")
		return
	}

	// Reset failed attempts on successful login
	if al, exists := c.Get("authRateLimiter"); exists {
		al.(*middleware.AuthRateLimiter).ResetFailedAttempts(clientIP)
	}

	response.Success(c, models.AuthResponse{
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
		ExpiresIn:    tokens.ExpiresIn,
		TokenType:    "Bearer",
		User: models.UserDTO{
			ID:       user.ID.String(),
			Username: user.Username,
		},
	})
}

func (h *AuthHandler) Me(c *gin.Context) {
	userID := middleware.GetUserID(c)

	user, err := h.authService.GetUserByID(c.Request.Context(), userID)
	if err != nil {
		response.NotFound(c, "user not found")
		return
	}

	response.Success(c, models.UserDTO{
		ID:       user.ID.String(),
		Username: user.Username,
	})
}

func (h *AuthHandler) Refresh(c *gin.Context) {
	var req models.RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "refresh_token is required")
		return
	}

	clientIP := c.ClientIP()
	tokens, err := h.authService.RefreshTokenPair(c.Request.Context(), req.RefreshToken, clientIP)
	if err != nil {
		if errors.Is(err, services.ErrInvalidToken) || errors.Is(err, services.ErrTokenExpired) || errors.Is(err, services.ErrTokenRevoked) {
			response.Unauthorized(c, "invalid or expired refresh token")
			return
		}
		response.InternalError(c, "failed to refresh token")
		return
	}

	// Get user info for the response
	userID, _ := h.authService.ValidateToken(tokens.AccessToken)
	user, err := h.authService.GetUserByID(c.Request.Context(), userID)
	if err != nil {
		response.InternalError(c, "failed to get user info")
		return
	}

	response.Success(c, models.AuthResponse{
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
		ExpiresIn:    tokens.ExpiresIn,
		TokenType:    "Bearer",
		User: models.UserDTO{
			ID:       user.ID.String(),
			Username: user.Username,
		},
	})
}

// Logout revokes the current tokens
func (h *AuthHandler) Logout(c *gin.Context) {
	var req models.LogoutRequest
	_ = c.ShouldBindJSON(&req) // Optional body

	// Get access token from Authorization header
	accessToken := ""
	authHeader := c.GetHeader("Authorization")
	if len(authHeader) > 7 && authHeader[:7] == "Bearer " {
		accessToken = authHeader[7:]
	}

	clientIP := c.ClientIP()
	if err := h.authService.Logout(c.Request.Context(), accessToken, req.RefreshToken, clientIP); err != nil {
		response.InternalError(c, "failed to logout")
		return
	}

	response.Success(c, gin.H{"message": "logged out successfully"})
}

// LogoutAll revokes all tokens for the current user (logout everywhere)
func (h *AuthHandler) LogoutAll(c *gin.Context) {
	userID := middleware.GetUserID(c)
	clientIP := c.ClientIP()

	if err := h.authService.LogoutAll(c.Request.Context(), userID, clientIP); err != nil {
		response.InternalError(c, "failed to logout from all devices")
		return
	}

	response.Success(c, gin.H{"message": "logged out from all devices successfully"})
}

// ChangePassword changes the current user's password
func (h *AuthHandler) ChangePassword(c *gin.Context) {
	var req models.ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request: current_password and new_password are required (new password must be 12-128 characters)")
		return
	}

	userID := middleware.GetUserID(c)
	clientIP := c.ClientIP()

	if err := h.authService.ChangePassword(c.Request.Context(), userID, req.CurrentPassword, req.NewPassword, clientIP); err != nil {
		if errors.Is(err, services.ErrPasswordMismatch) {
			response.Unauthorized(c, "current password is incorrect")
			return
		}
		if errors.Is(err, services.ErrWeakPassword) {
			response.BadRequest(c, "new password does not meet complexity requirements: must be 12-128 characters with at least one uppercase letter, one lowercase letter, one digit, and one special character")
			return
		}
		response.InternalError(c, "failed to change password")
		return
	}

	response.Success(c, gin.H{"message": "password changed successfully"})
}
