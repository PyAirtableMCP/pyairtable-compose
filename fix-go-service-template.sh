#!/bin/bash

# Fix Go Service Template Issues
# Updates all Go services to use proper logger initialization

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="/Users/kg/IdeaProjects/pyairtable-compose"
GO_SERVICES_DIR="$PROJECT_ROOT/go-services"

# Fix main.go for each service
fix_service_main() {
    local service_name=$1
    local port=$2
    local description=$3
    
    cat > "$GO_SERVICES_DIR/$service_name/cmd/$service_name/main.go" << 'EOF'
package main

import (
    "fmt"
    "os"
    "os/signal"
    "syscall"
    
    "github.com/gofiber/fiber/v3"
    "github.com/gofiber/fiber/v3/middleware/cors"
    "github.com/gofiber/fiber/v3/middleware/recover"
    "github.com/Reg-Kris/pyairtable-go-shared/config"
    "github.com/Reg-Kris/pyairtable-go-shared/health"
    sharedLogger "github.com/Reg-Kris/pyairtable-go-shared/logger"
    "github.com/Reg-Kris/pyairtable-go-shared/middleware"
)

func main() {
    // Initialize config
    cfg := config.LoadConfig()
    
    // Initialize logger
    logger, err := sharedLogger.New(&config.LoggerConfig{
        Level:      cfg.LogLevel,
        Format:     "json",
        OutputPath: "stdout",
    })
    if err != nil {
        panic(fmt.Sprintf("Failed to initialize logger: %v", err))
    }
    
    // Create Fiber app
    app := fiber.New(fiber.Config{
        AppName: "SERVICE_NAME",
        ErrorHandler: func(c fiber.Ctx, err error) error {
            code := fiber.StatusInternalServerError
            if e, ok := err.(*fiber.Error); ok {
                code = e.Code
            }
            
            logger.Error("Request error", err)
            
            return c.Status(code).JSON(fiber.Map{
                "error": err.Error(),
            })
        },
    })
    
    // Middleware
    app.Use(recover.New())
    app.Use(cors.New(cors.Config{
        AllowOrigins: "*",
        AllowHeaders: "Origin, Content-Type, Accept, Authorization",
        AllowMethods: "GET, POST, PUT, DELETE, OPTIONS",
    }))
    
    // Rate limiting
    app.Use(middleware.RateLimiter())
    
    // Health check
    app.Get("/health", health.HealthHandler)
    
    // Service-specific routes
    api := app.Group("/api/v1")
    
    // Info endpoint
    api.Get("/info", func(c fiber.Ctx) error {
        return c.JSON(fiber.Map{
            "service": "SERVICE_NAME",
            "version": "1.0.0",
            "description": "DESCRIPTION",
        })
    })
    
    // Graceful shutdown
    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt, syscall.SIGTERM)
    
    go func() {
        <-c
        logger.Info("Shutting down SERVICE_NAME...")
        _ = app.Shutdown()
    }()
    
    // Start server
    port := os.Getenv("PORT")
    if port == "" {
        port = "PORT_NUMBER"
    }
    
    logger.Info(fmt.Sprintf("Starting SERVICE_NAME on port %s", port))
    if err := app.Listen(":" + port); err != nil {
        logger.Fatal("Failed to start server", err)
    }
}
EOF

    # Replace placeholders
    sed -i '' "s/SERVICE_NAME/$service_name/g" "$GO_SERVICES_DIR/$service_name/cmd/$service_name/main.go"
    sed -i '' "s/PORT_NUMBER/$port/g" "$GO_SERVICES_DIR/$service_name/cmd/$service_name/main.go"
    sed -i '' "s/DESCRIPTION/$description/g" "$GO_SERVICES_DIR/$service_name/cmd/$service_name/main.go"
}

# Main execution
echo -e "${BLUE}Fixing Go service templates...${NC}"

# Fix all services
fix_service_main "api-gateway" "8080" "Central API Gateway with routing and load balancing"
fix_service_main "auth-service" "8081" "Authentication and authorization service"
fix_service_main "user-service" "8082" "User management and profiles"
fix_service_main "tenant-service" "8083" "Multi-tenancy management"
fix_service_main "workspace-service" "8084" "Workspace and project management"
fix_service_main "permission-service" "8085" "RBAC and permissions management"
fix_service_main "webhook-service" "8086" "Webhook management and delivery"
fix_service_main "notification-service" "8087" "Real-time notifications"
fix_service_main "file-service" "8088" "File upload and management"
fix_service_main "web-bff" "8089" "Backend for Frontend - Web"
fix_service_main "mobile-bff" "8090" "Backend for Frontend - Mobile"

echo -e "${GREEN}✅ Templates fixed!${NC}"