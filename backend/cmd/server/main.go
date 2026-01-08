package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/hamishgilbert/notes-app/backend/internal/config"
	"github.com/hamishgilbert/notes-app/backend/internal/database"
	"github.com/hamishgilbert/notes-app/backend/internal/handlers"
	"github.com/hamishgilbert/notes-app/backend/internal/middleware"
	"github.com/hamishgilbert/notes-app/backend/internal/repository"
	"github.com/hamishgilbert/notes-app/backend/internal/services"
	"github.com/hamishgilbert/notes-app/backend/internal/websocket"
	"github.com/joho/godotenv"
)

func main() {
	// Load .env file if it exists
	_ = godotenv.Load()

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Set Gin mode based on environment
	if cfg.IsProduction() {
		gin.SetMode(gin.ReleaseMode)
	}

	// Connect to database
	db, err := database.New(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	// Run migrations
	if err := db.RunMigrations(context.Background()); err != nil {
		log.Fatalf("Failed to run migrations: %v", err)
	}
	log.Println("Database migrations completed")

	// Initialize repositories
	userRepo := repository.NewUserRepository(db.Pool)
	noteRepo := repository.NewNoteRepository(db.Pool)

	// Initialize services
	authService := services.NewAuthService(userRepo, cfg.JWTSecret, cfg.JWTExpiry, cfg.RefreshExpiry)
	syncService := services.NewSyncService(noteRepo)

	// Initialize WebSocket hub
	wsHub := websocket.NewHub()
	go wsHub.Run()
	log.Println("WebSocket hub started")

	// Initialize rate limiters
	generalRateLimiter := middleware.NewRateLimiter(cfg.RateLimitRequests, time.Minute, cfg.RateLimitBurst)
	authRateLimiter := middleware.NewAuthRateLimiter()

	// Initialize handlers
	authHandler := handlers.NewAuthHandler(authService)
	notesHandler := handlers.NewNotesHandler(noteRepo, syncService, wsHub)
	syncHandler := handlers.NewSyncHandler(syncService, wsHub)
	wsHandler := handlers.NewWebSocketHandler(wsHub, authService, cfg.AllowedOrigins)

	// Setup router
	router := gin.Default()

	// Set max request body size
	router.MaxMultipartMemory = int64(cfg.MaxRequestBodyMB) << 20

	// Global middleware
	router.Use(middleware.SecurityHeaders())
	router.Use(middleware.CORSMiddleware(cfg.AllowedOrigins))
	router.Use(middleware.RateLimitMiddleware(generalRateLimiter))

	// Health check (no rate limit)
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "version": "1.0.2"})
	})

	// API routes
	api := router.Group("/api")
	{
		// Auth routes with stricter rate limiting
		auth := api.Group("/auth")
		auth.Use(middleware.AuthRateLimitMiddleware(authRateLimiter))
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/refresh", authHandler.Refresh) // Uses refresh token, not access token
			auth.GET("/me", middleware.AuthMiddleware(authService), authHandler.Me)
		}

		// Notes routes (protected)
		notes := api.Group("/notes")
		notes.Use(middleware.AuthMiddleware(authService))
		{
			notes.GET("", notesHandler.List)
			notes.POST("", notesHandler.Create)
			notes.GET("/:id", notesHandler.Get)
			notes.PUT("/:id", notesHandler.Update)
			notes.DELETE("/:id", notesHandler.Delete)
			notes.POST("/sync", syncHandler.Sync)
		}

		// WebSocket route (authentication handled in handler)
		api.GET("/ws", wsHandler.HandleWebSocket)
	}

	// Create server
	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: router,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Server starting on port %s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	// Graceful shutdown with 5 second timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}
