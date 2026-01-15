package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/hamishgilbert/notes-app/backend/internal/config"
	"github.com/hamishgilbert/notes-app/backend/internal/database"
	"github.com/hamishgilbert/notes-app/backend/internal/handlers"
	"github.com/hamishgilbert/notes-app/backend/internal/middleware"
	"github.com/hamishgilbert/notes-app/backend/internal/models"
	"github.com/hamishgilbert/notes-app/backend/internal/repository"
	"github.com/hamishgilbert/notes-app/backend/internal/services"
	"github.com/hamishgilbert/notes-app/backend/internal/websocket"
	"github.com/joho/godotenv"
	"golang.org/x/crypto/bcrypt"
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

	// Seed demo account
	if err := seedDemoAccount(context.Background(), userRepo, noteRepo); err != nil {
		log.Printf("[WARN] Failed to seed demo account: %v", err)
	}
	tokenBlacklistRepo := repository.NewTokenBlacklistRepository(db.Pool)

	// Initialize services
	authService := services.NewAuthService(userRepo, tokenBlacklistRepo, cfg.JWTSecret, cfg.JWTExpiry, cfg.RefreshExpiry)
	syncService := services.NewSyncService(noteRepo)

	// Initialize WebSocket hub
	wsHub := websocket.NewHub()
	go wsHub.Run()
	log.Println("WebSocket hub started")

	// Start token blacklist cleanup goroutine (runs every hour)
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			count, err := authService.CleanupExpiredTokens(context.Background())
			if err != nil {
				log.Printf("[ERROR] Failed to cleanup expired tokens: %v", err)
			} else if count > 0 {
				log.Printf("[INFO] Cleaned up %d expired tokens from blacklist", count)
			}
		}
	}()

	// Initialize rate limiters
	generalRateLimiter := middleware.NewRateLimiter(cfg.RateLimitRequests, time.Minute, cfg.RateLimitBurst)
	authRateLimiter := middleware.NewAuthRateLimiter()

	// Initialize CSRF middleware
	csrfConfig := middleware.DefaultCSRFConfig(cfg.IsProduction())
	csrfMiddleware := middleware.NewCSRFMiddleware(csrfConfig)

	// Initialize audit logger
	auditLogger := middleware.NewAuditLogger(true) // Enable audit logging

	// Initialize handlers
	authHandler := handlers.NewAuthHandler(authService)
	notesHandler := handlers.NewNotesHandler(noteRepo, syncService, wsHub)
	syncHandler := handlers.NewSyncHandler(syncService, wsHub)
	wsHandler := handlers.NewWebSocketHandler(wsHub, authService, cfg.AllowedOrigins)

	// Setup router
	router := gin.Default()

	// Configure trusted proxies for accurate client IP detection
	// In production behind a load balancer/reverse proxy, set TRUSTED_PROXIES env var
	// Example: TRUSTED_PROXIES=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
	if trustedProxies := os.Getenv("TRUSTED_PROXIES"); trustedProxies != "" {
		proxies := []string{}
		for _, p := range splitAndTrim(trustedProxies, ",") {
			if p != "" {
				proxies = append(proxies, p)
			}
		}
		if len(proxies) > 0 {
			if err := router.SetTrustedProxies(proxies); err != nil {
				log.Printf("[WARN] Failed to set trusted proxies: %v", err)
			} else {
				log.Printf("[INFO] Configured trusted proxies: %v", proxies)
			}
		}
	} else if cfg.IsProduction() {
		// In production without explicit config, trust no proxies (use direct connection IP)
		router.SetTrustedProxies(nil)
		log.Println("[WARN] No TRUSTED_PROXIES configured - using direct connection IP only")
	}

	// Set max request body size
	router.MaxMultipartMemory = int64(cfg.MaxRequestBodyMB) << 20

	// Global middleware
	router.Use(middleware.SecurityHeaders())
	router.Use(middleware.CORSMiddleware(cfg.AllowedOrigins))
	router.Use(middleware.RateLimitMiddleware(generalRateLimiter))
	router.Use(csrfMiddleware.Handler())

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
			auth.POST("/logout", authHandler.Logout)   // Revokes current tokens
			auth.POST("/logout-all", middleware.AuthMiddleware(authService), authHandler.LogoutAll) // Requires auth, revokes all user tokens
			auth.POST("/change-password", middleware.AuthMiddleware(authService), authHandler.ChangePassword) // Requires auth
			auth.GET("/me", middleware.AuthMiddleware(authService), authHandler.Me)
		}

		// Notes routes (protected with audit logging)
		notes := api.Group("/notes")
		notes.Use(middleware.AuthMiddleware(authService))
		notes.Use(middleware.AuditMiddleware(auditLogger, "notes"))
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

// splitAndTrim splits a string by separator and trims whitespace from each part
func splitAndTrim(s, sep string) []string {
	parts := []string{}
	for _, part := range strings.Split(s, sep) {
		trimmed := strings.TrimSpace(part)
		if trimmed != "" {
			parts = append(parts, trimmed)
		}
	}
	return parts
}

// seedDemoAccount creates a demo user with sample notes if it doesn't exist
func seedDemoAccount(ctx context.Context, userRepo *repository.UserRepository, noteRepo *repository.NoteRepository) error {
	demoPassword := "DemoPassword123!"

	// Check if demo user already exists
	existingUser, err := userRepo.GetByUsername(ctx, "demo")
	if err == nil {
		// Demo user exists - ensure password is correct and reset notes
		hashedPassword, hashErr := bcrypt.GenerateFromPassword([]byte(demoPassword), bcrypt.DefaultCost)
		if hashErr != nil {
			return hashErr
		}
		if updateErr := userRepo.UpdatePassword(ctx, existingUser.ID, string(hashedPassword)); updateErr != nil {
			log.Printf("[WARN] Failed to update demo password: %v", updateErr)
		} else {
			log.Println("Demo account password updated")
		}

		// Reset demo notes
		if deleteErr := noteRepo.HardDeleteAllByUserID(ctx, existingUser.ID); deleteErr != nil {
			log.Printf("[WARN] Failed to delete demo notes: %v", deleteErr)
		}
		createDemoNotes(ctx, noteRepo, existingUser.ID)
		return nil
	}
	if !errors.Is(err, repository.ErrUserNotFound) {
		return err
	}

	// Create demo user
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(demoPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	now := time.Now()
	demoUser := &models.User{
		ID:           uuid.New(),
		Username:     "demo",
		PasswordHash: string(hashedPassword),
		CreatedAt:    now,
		UpdatedAt:    now,
	}

	if err := userRepo.Create(ctx, demoUser); err != nil {
		return err
	}
	log.Println("Created demo user account")

	createDemoNotes(ctx, noteRepo, demoUser.ID)
	return nil
}

// createDemoNotes creates sample notes for the demo account
func createDemoNotes(ctx context.Context, noteRepo *repository.NoteRepository, userID uuid.UUID) {
	now := time.Now()

	// Note 1: Welcome note (pinned)
	welcomeNote := &models.Note{
		ID:        uuid.New(),
		UserID:    userID,
		Title:     "Welcome to Notes!",
		Content:   "This is your personal notes app. Create text notes or checklists, and they'll sync across all your devices in real-time.\n\nFeel free to explore - create, edit, and delete notes to see how it works!",
		NoteType:  models.NoteTypeNote,
		IsPinned:  true,
		SortOrder: 0,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := noteRepo.Create(ctx, welcomeNote); err != nil {
		log.Printf("[WARN] Failed to create welcome note: %v", err)
	}

	// Note 2: Features note
	featuresNote := &models.Note{
		ID:        uuid.New(),
		UserID:    userID,
		Title:     "Features",
		Content:   "• Real-time sync across devices\n• Text notes and checklists\n• Pin important notes to the top\n• Archive notes you're done with\n• Secure authentication",
		NoteType:  models.NoteTypeNote,
		SortOrder: 1,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := noteRepo.Create(ctx, featuresNote); err != nil {
		log.Printf("[WARN] Failed to create features note: %v", err)
	}

	// Note 3: Getting Started checklist
	checklistNote := &models.Note{
		ID:        uuid.New(),
		UserID:    userID,
		Title:     "Getting Started",
		NoteType:  models.NoteTypeChecklist,
		SortOrder: 2,
		CreatedAt: now,
		UpdatedAt: now,
		ChecklistItems: []models.ChecklistItem{
			{ID: uuid.New(), Text: "Try creating a new note", IsCompleted: false, SortOrder: 0, CreatedAt: now, UpdatedAt: now},
			{ID: uuid.New(), Text: "Pin an important note", IsCompleted: false, SortOrder: 1, CreatedAt: now, UpdatedAt: now},
			{ID: uuid.New(), Text: "Archive a note you're done with", IsCompleted: false, SortOrder: 2, CreatedAt: now, UpdatedAt: now},
			{ID: uuid.New(), Text: "Check out the settings", IsCompleted: false, SortOrder: 3, CreatedAt: now, UpdatedAt: now},
		},
	}
	if err := noteRepo.Create(ctx, checklistNote); err != nil {
		log.Printf("[WARN] Failed to create checklist note: %v", err)
	}

	log.Println("Created sample notes for demo account")
}
