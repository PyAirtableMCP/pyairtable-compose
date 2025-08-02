package routes

import (
	"github.com/Reg-Kris/pyairtable-api-gateway/internal/config"
	"github.com/Reg-Kris/pyairtable-api-gateway/internal/handlers"
	"github.com/Reg-Kris/pyairtable-api-gateway/internal/middleware"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/gofiber/fiber/v2/middleware/requestid"
	"net/http"
	"go.uber.org/zap"
)

type Router struct {
	config     *config.Config
	logger     *zap.Logger
	httpClient *http.Client
}

func NewRouter(cfg *config.Config, logger *zap.Logger, httpClient *http.Client) *Router {
	return &Router{
		config:     cfg,
		logger:     logger,
		httpClient: httpClient,
	}
}

func (r *Router) Setup(app *fiber.App) {
	// Global middleware
	app.Use(recover.New())
	app.Use(requestid.New())
	app.Use(logger.New(logger.Config{
		Format: "[${time}] ${locals:requestid} ${status} - ${method} ${path}\n",
	}))
	
	// CORS configuration
	app.Use(cors.New(cors.Config{
		AllowOrigins: r.config.CORSOrigins,
		AllowHeaders: "Origin, Content-Type, Accept, Authorization",
		AllowMethods: "GET, POST, PUT, DELETE, OPTIONS, PATCH",
	}))
	
	// Rate limiting middleware
	rateLimiter := middleware.NewRateLimiter(r.config.RateLimitPerMinute)
	app.Use(rateLimiter.Limit())
	
	// Health check
	app.Get("/health", handlers.HealthCheck)
	
	// API routes
	api := app.Group("/api/v1")
	
	// Auth routes (public)
	auth := api.Group("/auth")
	authHandler := handlers.NewAuthHandler(r.config, r.httpClient, r.logger)
	auth.Post("/login", authHandler.Login)
	auth.Post("/register", authHandler.Register)
	auth.Post("/refresh", authHandler.RefreshToken)
	auth.Post("/logout", authHandler.Logout)
	
	// Protected routes
	authConfig := &middleware.AuthConfig{
		AuthServiceURL:       r.config.AuthServiceURL,
		PermissionServiceURL: r.config.PermissionServiceURL,
		JWTSecret:           "", // TODO: Get from config
	}
	
	// Middleware to inject permission service URL into context
	permissionContext := func(c *fiber.Ctx) error {
		c.Locals("permission_service_url", r.config.PermissionServiceURL)
		return c.Next()
	}
	
	// User routes
	users := api.Group("/users", middleware.RequireAuth(authConfig), permissionContext)
	userHandler := handlers.NewUserHandler(r.config, r.httpClient, r.logger)
	users.Get("/me", userHandler.GetCurrentUser)
	users.Put("/me", userHandler.UpdateCurrentUser)
	users.Get("/:id", userHandler.GetUser)
	users.Put("/:id", middleware.RequirePermission("users.update"), userHandler.UpdateUser)
	users.Delete("/:id", middleware.RequirePermission("users.delete"), userHandler.DeleteUser)
	users.Get("/", middleware.RequirePermission("users.list"), userHandler.ListUsers)
	
	// Tenant routes
	tenants := api.Group("/tenants", middleware.RequireAuth(authConfig), permissionContext)
	tenantHandler := handlers.NewTenantHandler(r.config, r.httpClient, r.logger)
	tenants.Post("/", middleware.RequirePermission("tenants.create"), tenantHandler.CreateTenant)
	tenants.Get("/:id", tenantHandler.GetTenant)
	tenants.Put("/:id", middleware.RequirePermission("tenants.update"), tenantHandler.UpdateTenant)
	tenants.Delete("/:id", middleware.RequirePermission("tenants.delete"), tenantHandler.DeleteTenant)
	tenants.Get("/", tenantHandler.ListTenants)
	
	// Workspace routes
	workspaces := api.Group("/workspaces", middleware.RequireAuth(authConfig), permissionContext)
	workspaceHandler := handlers.NewWorkspaceHandler(r.config, r.httpClient, r.logger)
	workspaces.Post("/", middleware.RequirePermission("workspaces.create"), workspaceHandler.CreateWorkspace)
	workspaces.Get("/:id", workspaceHandler.GetWorkspace)
	workspaces.Put("/:id", middleware.RequirePermission("workspaces.update"), workspaceHandler.UpdateWorkspace)
	workspaces.Delete("/:id", middleware.RequirePermission("workspaces.delete"), workspaceHandler.DeleteWorkspace)
	workspaces.Get("/", workspaceHandler.ListWorkspaces)
	
	// Airtable routes
	airtable := api.Group("/airtable", middleware.RequireAuth(authConfig), permissionContext)
	airtableHandler := handlers.NewAirtableHandler(r.config, r.httpClient, r.logger)
	airtable.Get("/bases", airtableHandler.ListBases)
	airtable.Get("/bases/:baseId", airtableHandler.GetBase)
	airtable.Get("/bases/:baseId/tables", airtableHandler.ListTables)
	airtable.Get("/bases/:baseId/tables/:tableId", airtableHandler.GetTable)
	airtable.Get("/bases/:baseId/tables/:tableId/records", airtableHandler.ListRecords)
	airtable.Post("/bases/:baseId/tables/:tableId/records", airtableHandler.CreateRecord)
	airtable.Get("/bases/:baseId/tables/:tableId/records/:recordId", airtableHandler.GetRecord)
	airtable.Patch("/bases/:baseId/tables/:tableId/records/:recordId", airtableHandler.UpdateRecord)
	airtable.Delete("/bases/:baseId/tables/:tableId/records/:recordId", airtableHandler.DeleteRecord)
	
	// Permission routes
	permissions := api.Group("/permissions", middleware.RequireAuth(authConfig), permissionContext)
	permissionHandler := handlers.NewPermissionHandler(r.config, r.httpClient, r.logger)
	permissions.Get("/check", permissionHandler.CheckPermissions)
	permissions.Post("/grant", middleware.RequirePermission("permissions.grant"), permissionHandler.GrantPermission)
	permissions.Post("/revoke", middleware.RequirePermission("permissions.revoke"), permissionHandler.RevokePermission)
	permissions.Get("/user/:userId", permissionHandler.GetUserPermissions)
	
	// 404 handler
	app.Use(func(c *fiber.Ctx) error {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Not found",
		})
	})
}