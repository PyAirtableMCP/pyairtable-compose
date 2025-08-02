package router

import (
    "github.com/gofiber/fiber/v2"
    "github.com/gofiber/fiber/v2/middleware/proxy"
    "github.com/Reg-Kris/pyairtable-go-shared/middleware"
    "go.uber.org/zap"
    "os"
    "strings"
)

// ServiceRoute defines a route to a backend service
type ServiceRoute struct {
    Prefix  string
    Target  string
    Rewrite bool
}

// Router handles all routing logic for the API Gateway
type Router struct {
    logger *zap.Logger
    routes map[string]ServiceRoute
}

// NewRouter creates a new router instance
func NewRouter(logger *zap.Logger) *Router {
    return &Router{
        logger: logger,
        routes: initializeRoutes(),
    }
}

// initializeRoutes sets up all service routes
func initializeRoutes() map[string]ServiceRoute {
    return map[string]ServiceRoute{
        // Auth routes
        "/auth": {
            Prefix:  "/auth",
            Target:  getServiceURL("AUTH_SERVICE_URL", "http://auth-service:8081"),
            Rewrite: true,
        },
        // User routes
        "/api/v1/users": {
            Prefix:  "/api/v1/users",
            Target:  getServiceURL("USER_SERVICE_URL", "http://user-service:8082"),
            Rewrite: true,
        },
        // Tenant routes
        "/api/v1/tenants": {
            Prefix:  "/api/v1/tenants",
            Target:  getServiceURL("TENANT_SERVICE_URL", "http://tenant-service:8083"),
            Rewrite: true,
        },
        // Workspace routes
        "/api/v1/workspaces": {
            Prefix:  "/api/v1/workspaces",
            Target:  getServiceURL("WORKSPACE_SERVICE_URL", "http://workspace-service:8084"),
            Rewrite: true,
        },
        // Airtable routes
        "/api/v1/airtable": {
            Prefix:  "/api/v1/airtable",
            Target:  getServiceURL("AIRTABLE_GATEWAY_URL", "http://airtable-gateway:8093"),
            Rewrite: true,
        },
        // LLM routes
        "/api/v1/llm": {
            Prefix:  "/api/v1/llm",
            Target:  getServiceURL("LLM_ORCHESTRATOR_URL", "http://llm-orchestrator:8091"),
            Rewrite: true,
        },
        // MCP routes
        "/api/v1/mcp": {
            Prefix:  "/api/v1/mcp",
            Target:  getServiceURL("MCP_SERVER_URL", "http://mcp-server:8092"),
            Rewrite: true,
        },
        // Chat routes
        "/api/v1/chat": {
            Prefix:  "/api/v1/chat",
            Target:  getServiceURL("CHAT_SERVICE_URL", "http://chat-service:8098"),
            Rewrite: true,
        },
        // Analytics routes
        "/api/v1/analytics": {
            Prefix:  "/api/v1/analytics",
            Target:  getServiceURL("ANALYTICS_SERVICE_URL", "http://analytics-service:8100"),
            Rewrite: true,
        },
        // Workflow routes
        "/api/v1/workflows": {
            Prefix:  "/api/v1/workflows",
            Target:  getServiceURL("WORKFLOW_ENGINE_URL", "http://workflow-engine:8099"),
            Rewrite: true,
        },
    }
}

// SetupRoutes configures all routes on the Fiber app
func (r *Router) SetupRoutes(app *fiber.App) {
    // Public routes (no auth required)
    public := app.Group("")
    public.Get("/health", healthHandler)
    public.Get("/ready", readyHandler)
    
    // Auth routes (special handling)
    auth := app.Group("/auth")
    r.setupAuthRoutes(auth)
    
    // API routes (require authentication)
    api := app.Group("/api", middleware.AuthMiddleware(os.Getenv("JWT_SECRET")))
    
    // Set up proxy routes for each service
    for prefix, route := range r.routes {
        if strings.HasPrefix(prefix, "/api/") {
            r.setupProxyRoute(api, prefix, route)
        }
    }
    
    // Web BFF routes
    webBff := app.Group("/web", middleware.AuthMiddleware(os.Getenv("JWT_SECRET")))
    webBff.All("/*", proxy.Forward(getServiceURL("WEB_BFF_URL", "http://web-bff:8089")))
    
    // Mobile BFF routes
    mobileBff := app.Group("/mobile", middleware.AuthMiddleware(os.Getenv("JWT_SECRET")))
    mobileBff.All("/*", proxy.Forward(getServiceURL("MOBILE_BFF_URL", "http://mobile-bff:8090")))
}

// setupAuthRoutes configures authentication routes
func (r *Router) setupAuthRoutes(group fiber.Router) {
    authURL := getServiceURL("AUTH_SERVICE_URL", "http://auth-service:8081")
    
    // Public auth endpoints
    group.Post("/login", proxy.Forward(authURL + "/auth/login"))
    group.Post("/register", proxy.Forward(authURL + "/auth/register"))
    group.Post("/refresh", proxy.Forward(authURL + "/auth/refresh"))
    group.Post("/logout", proxy.Forward(authURL + "/auth/logout"))
    
    // Protected auth endpoints
    group.Use(middleware.AuthMiddleware(os.Getenv("JWT_SECRET")))
    group.Get("/me", proxy.Forward(authURL + "/auth/me"))
    group.Put("/me", proxy.Forward(authURL + "/auth/me"))
    group.Post("/change-password", proxy.Forward(authURL + "/auth/change-password"))
}

// setupProxyRoute configures a proxy route to a backend service
func (r *Router) setupProxyRoute(group fiber.Router, prefix string, route ServiceRoute) {
    // Remove the /api/v1 prefix when forwarding
    trimmedPrefix := strings.TrimPrefix(prefix, "/api/v1")
    
    group.All(trimmedPrefix + "/*", func(c fiber.Ctx) error {
        // Log the request
        r.logger.Info("Proxying request",
            zap.String("method", c.Method()),
            zap.String("path", c.Path()),
            zap.String("target", route.Target),
        )
        
        // Add request ID header
        requestID := c.Locals("requestID")
        if requestID != nil {
            c.Set("X-Request-ID", requestID.(string))
        }
        
        // Forward to the target service
        return proxy.Forward(route.Target)(c)
    })
}

// healthHandler returns the health status
func healthHandler(c fiber.Ctx) error {
    return c.JSON(fiber.Map{
        "status": "healthy",
        "service": "api-gateway",
    })
}

// readyHandler returns the readiness status
func readyHandler(c fiber.Ctx) error {
    // TODO: Check dependent service health
    return c.JSON(fiber.Map{
        "status": "ready",
        "service": "api-gateway",
    })
}

// getServiceURL returns the service URL from environment or default
func getServiceURL(envVar, defaultURL string) string {
    if url := os.Getenv(envVar); url != "" {
        return url
    }
    return defaultURL
}