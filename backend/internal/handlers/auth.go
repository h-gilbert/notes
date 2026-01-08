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
	tokens, err := h.authService.RefreshTokenPair(req.RefreshToken, clientIP)
	if err != nil {
		if errors.Is(err, services.ErrInvalidToken) || errors.Is(err, services.ErrTokenExpired) {
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
