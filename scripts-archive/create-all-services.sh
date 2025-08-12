#!/bin/bash

# Create All 22 Microservices Script
# This script creates all microservices with proper structure

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ROOT="/Users/kg/IdeaProjects/pyairtable-compose"
GO_SERVICES_DIR="$PROJECT_ROOT/go-services"
PYTHON_SERVICES_DIR="$PROJECT_ROOT/python-services"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create directories
mkdir -p "$GO_SERVICES_DIR"
mkdir -p "$PYTHON_SERVICES_DIR"

# Go service template function
create_go_service() {
    local service_name=$1
    local port=$2
    local description=$3
    
    log_info "Creating Go service: $service_name on port $port"
    
    local service_dir="$GO_SERVICES_DIR/$service_name"
    mkdir -p "$service_dir"
    
    # Create go.mod with local replace
    cat > "$service_dir/go.mod" << EOF
module github.com/Reg-Kris/pyairtable-$service_name

go 1.21

require (
    github.com/Reg-Kris/pyairtable-go-shared v0.1.0
    github.com/gofiber/fiber/v3 v3.0.0-beta.2
    github.com/spf13/viper v1.16.0
    go.uber.org/zap v1.25.0
)

replace github.com/Reg-Kris/pyairtable-go-shared => ../../pyairtable-infrastructure/pyairtable-go-shared
EOF

    # Create main.go
    mkdir -p "$service_dir/cmd/$service_name"
    cat > "$service_dir/cmd/$service_name/main.go" << EOF
package main

import (
    "fmt"
    "log"
    "os"
    "os/signal"
    "syscall"
    
    "github.com/gofiber/fiber/v3"
    "github.com/gofiber/fiber/v3/middleware/cors"
    "github.com/gofiber/fiber/v3/middleware/logger"
    "github.com/gofiber/fiber/v3/middleware/recover"
    "github.com/Reg-Kris/pyairtable-go-shared/config"
    "github.com/Reg-Kris/pyairtable-go-shared/health"
    "github.com/Reg-Kris/pyairtable-go-shared/logger"
    "github.com/Reg-Kris/pyairtable-go-shared/middleware"
)

func main() {
    // Initialize logger
    log := logger.NewLogger()
    
    // Initialize config
    cfg := config.LoadConfig()
    
    // Create Fiber app
    app := fiber.New(fiber.Config{
        AppName: "$service_name",
        ErrorHandler: func(c fiber.Ctx, err error) error {
            code := fiber.StatusInternalServerError
            if e, ok := err.(*fiber.Error); ok {
                code = e.Code
            }
            
            return c.Status(code).JSON(fiber.Map{
                "error": err.Error(),
            })
        },
    })
    
    // Middleware
    app.Use(recover.New())
    app.Use(logger.New())
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
    
    // TODO: Add service-specific endpoints
    api.Get("/info", func(c fiber.Ctx) error {
        return c.JSON(fiber.Map{
            "service": "$service_name",
            "version": "1.0.0",
            "description": "$description",
        })
    })
    
    // Graceful shutdown
    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt, syscall.SIGTERM)
    
    go func() {
        <-c
        log.Info("Shutting down $service_name...")
        _ = app.Shutdown()
    }()
    
    // Start server
    port := os.Getenv("PORT")
    if port == "" {
        port = "$port"
    }
    
    log.Info(fmt.Sprintf("Starting $service_name on port %s", port))
    if err := app.Listen(":" + port); err != nil {
        log.Fatal("Failed to start server", err)
    }
}
EOF

    # Create Dockerfile
    cat > "$service_dir/Dockerfile" << EOF
FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o $service_name ./cmd/$service_name

FROM alpine:latest

RUN apk --no-cache add ca-certificates
WORKDIR /root/

COPY --from=builder /app/$service_name .

EXPOSE $port
CMD ["./$service_name"]
EOF

    # Create Makefile
    cat > "$service_dir/Makefile" << EOF
.PHONY: build run test clean docker-build docker-run

SERVICE_NAME=$service_name
PORT=$port

build:
	go build -o \$(SERVICE_NAME) ./cmd/\$(SERVICE_NAME)

run: build
	./\$(SERVICE_NAME)

test:
	go test -v ./...

clean:
	rm -f \$(SERVICE_NAME)

docker-build:
	docker build -t \$(SERVICE_NAME):latest .

docker-run: docker-build
	docker run -p \$(PORT):\$(PORT) \$(SERVICE_NAME):latest

tidy:
	go mod tidy

dev:
	air -c .air.toml
EOF

    # Create .gitignore
    cat > "$service_dir/.gitignore" << EOF
# Binaries
$service_name
*.exe
*.dll
*.so
*.dylib

# Test binary, built with go test -c
*.test

# Output of the go coverage tool
*.out

# Dependency directories
vendor/

# Go workspace file
go.work

# Environment files
.env
.env.local

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
EOF

    # Create README
    cat > "$service_dir/README.md" << EOF
# $service_name

$description

## Port
- Default: $port

## Development

\`\`\`bash
# Install dependencies
go mod download

# Run locally
make run

# Run with hot reload
make dev

# Build Docker image
make docker-build

# Run tests
make test
\`\`\`

## API Endpoints

- \`GET /health\` - Health check
- \`GET /api/v1/info\` - Service information

## Environment Variables

- \`PORT\` - Service port (default: $port)
- \`LOG_LEVEL\` - Logging level (default: info)
EOF

    log_success "Created Go service: $service_name"
}

# Python service template function
create_python_service() {
    local service_name=$1
    local port=$2
    local description=$3
    
    log_info "Creating Python service: $service_name on port $port"
    
    local service_dir="$PYTHON_SERVICES_DIR/$service_name"
    mkdir -p "$service_dir/src/routes"
    mkdir -p "$service_dir/src/models"
    mkdir -p "$service_dir/src/services"
    mkdir -p "$service_dir/src/utils"
    mkdir -p "$service_dir/tests"
    
    # Create requirements.txt
    cat > "$service_dir/requirements.txt" << EOF
fastapi==0.104.1
uvicorn==0.24.0
python-dotenv==1.0.0
pydantic==2.5.0
pydantic-settings==2.1.0
httpx==0.25.2
redis==5.0.1
prometheus-client==0.19.0
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
sqlalchemy==2.0.23
asyncpg==0.29.0
alembic==1.13.0
pytest==7.4.3
pytest-asyncio==0.21.1
pytest-cov==4.1.0
EOF

    # Create main.py
    cat > "$service_dir/src/main.py" << EOF
"""
$service_name - $description
"""
import os
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn

from routes import health

# App lifespan
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print(f"Starting $service_name...")
    yield
    # Shutdown
    print(f"Shutting down $service_name...")

# Create FastAPI app
app = FastAPI(
    title="$service_name",
    description="$description",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={"detail": str(exc)}
    )

# Include routers
app.include_router(health.router, tags=["health"])

# Root endpoint
@app.get("/")
async def root():
    return {
        "service": "$service_name",
        "version": "1.0.0",
        "description": "$description"
    }

# Service info endpoint
@app.get("/api/v1/info")
async def info():
    return {
        "service": "$service_name",
        "version": "1.0.0",
        "description": "$description",
        "port": $port
    }

if __name__ == "__main__":
    port = int(os.getenv("PORT", "$port"))
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        reload=os.getenv("ENV", "production") == "development"
    )
EOF

    # Create health route
    cat > "$service_dir/src/routes/__init__.py" << EOF
"""Routes package for $service_name"""
EOF

    cat > "$service_dir/src/routes/health.py" << EOF
"""Health check routes"""
from fastapi import APIRouter
from datetime import datetime

router = APIRouter()

@router.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "$service_name",
        "timestamp": datetime.utcnow().isoformat()
    }

@router.get("/ready")
async def readiness_check():
    """Readiness check endpoint"""
    # TODO: Add actual readiness checks (DB connection, etc.)
    return {
        "status": "ready",
        "service": "$service_name",
        "timestamp": datetime.utcnow().isoformat()
    }
EOF

    # Create Dockerfile
    cat > "$service_dir/Dockerfile" << EOF
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY src/ ./src/

# Set Python path
ENV PYTHONPATH=/app/src

EXPOSE $port

CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "$port"]
EOF

    # Create .gitignore
    cat > "$service_dir/.gitignore" << EOF
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Virtual Environment
venv/
ENV/
env/

# IDE
.idea/
.vscode/
*.swp
*.swo

# Environment
.env
.env.local

# Testing
.coverage
.pytest_cache/
htmlcov/

# OS
.DS_Store
EOF

    # Create README
    cat > "$service_dir/README.md" << EOF
# $service_name

$description

## Port
- Default: $port

## Development

\`\`\`bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run locally
python -m uvicorn src.main:app --reload --port $port

# Run tests
pytest

# Build Docker image
docker build -t $service_name .
\`\`\`

## API Endpoints

- \`GET /health\` - Health check
- \`GET /ready\` - Readiness check
- \`GET /api/v1/info\` - Service information

## Environment Variables

- \`PORT\` - Service port (default: $port)
- \`ENV\` - Environment (development/production)
EOF

    # Create tests
    cat > "$service_dir/tests/__init__.py" << EOF
"""Tests for $service_name"""
EOF

    cat > "$service_dir/tests/test_health.py" << EOF
"""Test health endpoints"""
from fastapi.testclient import TestClient
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.main import app

client = TestClient(app)

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
    assert response.json()["service"] == "$service_name"

def test_readiness_check():
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "ready"

def test_info():
    response = client.get("/api/v1/info")
    assert response.status_code == 200
    assert response.json()["service"] == "$service_name"
    assert response.json()["port"] == $port
EOF

    log_success "Created Python service: $service_name"
}

# Main execution
main() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}Creating All 22 PyAirtable Services${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
    
    # Create Go services
    log_info "Creating Go Services (11 total)..."
    create_go_service "api-gateway" "8080" "Central API Gateway with routing and load balancing"
    create_go_service "auth-service" "8081" "Authentication and authorization service"
    create_go_service "user-service" "8082" "User management and profiles"
    create_go_service "tenant-service" "8083" "Multi-tenancy management"
    create_go_service "workspace-service" "8084" "Workspace and project management"
    create_go_service "permission-service" "8085" "RBAC and permissions management"
    create_go_service "webhook-service" "8086" "Webhook management and delivery"
    create_go_service "notification-service" "8087" "Real-time notifications"
    create_go_service "file-service" "8088" "File upload and management"
    create_go_service "web-bff" "8089" "Backend for Frontend - Web"
    create_go_service "mobile-bff" "8090" "Backend for Frontend - Mobile"
    
    echo ""
    log_info "Creating Python Services (11 total)..."
    create_python_service "llm-orchestrator" "8091" "LLM orchestration with Gemini integration"
    create_python_service "mcp-server" "8092" "Model Context Protocol server"
    create_python_service "airtable-gateway" "8093" "Airtable API integration gateway"
    create_python_service "schema-service" "8094" "Schema management and migrations"
    create_python_service "formula-engine" "8095" "Formula parsing and execution"
    create_python_service "embedding-service" "8096" "Text embedding generation"
    create_python_service "semantic-search" "8097" "Semantic search capabilities"
    create_python_service "chat-service" "8098" "Chat and conversation management"
    create_python_service "workflow-engine" "8099" "Workflow automation engine"
    create_python_service "analytics-service" "8100" "Analytics and reporting"
    create_python_service "audit-service" "8101" "Audit logging and compliance"
    
    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}✅ All 22 Services Created!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo ""
    echo "Go Services: $GO_SERVICES_DIR/"
    echo "Python Services: $PYTHON_SERVICES_DIR/"
    echo ""
    echo "Next steps:"
    echo "1. Run: ./fix-go-dependencies.sh"
    echo "2. Run: ./verify-all-services.sh"
    echo "3. Start services: docker-compose up -d"
}

# Check if running from correct directory
if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
    log_error "Please run this script from the pyairtable-compose project root"
    exit 1
fi

# Execute main
main "$@"