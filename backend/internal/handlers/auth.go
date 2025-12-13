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
		response.BadRequest(c, "invalid request body")
		return
	}

	user, token, err := h.authService.Register(c.Request.Context(), req.Username, req.Password)
	if err != nil {
		if errors.Is(err, services.ErrUserExists) {
			response.Conflict(c, "username already exists")
			return
		}
		response.InternalError(c, "failed to register user")
		return
	}

	response.Created(c, models.AuthResponse{
		Token: token,
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

	user, token, err := h.authService.Login(c.Request.Context(), req.Username, req.Password)
	if err != nil {
		if errors.Is(err, services.ErrInvalidCredentials) {
			response.Unauthorized(c, "invalid username or password")
			return
		}
		response.InternalError(c, "failed to login")
		return
	}

	response.Success(c, models.AuthResponse{
		Token: token,
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
	userID := middleware.GetUserID(c)

	user, err := h.authService.GetUserByID(c.Request.Context(), userID)
	if err != nil {
		response.NotFound(c, "user not found")
		return
	}

	token, err := h.authService.RefreshToken(userID)
	if err != nil {
		response.InternalError(c, "failed to refresh token")
		return
	}

	response.Success(c, models.AuthResponse{
		Token: token,
		User: models.UserDTO{
			ID:       user.ID.String(),
			Username: user.Username,
		},
	})
}
