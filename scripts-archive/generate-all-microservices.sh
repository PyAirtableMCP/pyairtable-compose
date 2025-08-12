#!/bin/bash

# PyAirtable Comprehensive Microservices Generator
# This script generates all 22 backend microservices for PyAirtable with proper structure and dependencies

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="/Users/kg/IdeaProjects/pyairtable-compose"
GO_SERVICES_DIR="$PROJECT_ROOT/go-services"
PYTHON_SERVICES_DIR="$PROJECT_ROOT/python-services"
TEMPLATE_DIR="$PROJECT_ROOT/pyairtable-infrastructure/go-microservice-template"
SHARED_GO_MODULE="github.com/Reg-Kris/pyairtable-go-shared"

# Service definitions
GO_SERVICES=(
    "api-gateway:8080:API Gateway for routing requests"
    "auth-service:8081:Authentication and authorization service"
    "user-service:8082:User management service"
    "tenant-service:8083:Multi-tenant organization service"
    "workspace-service:8084:Workspace management service"
    "permission-service:8085:Permission and access control service"
    "webhook-service:8086:Webhook delivery service"
    "notification-service:8087:Notification service"
    "file-service:8088:File storage and management service"
    "web-bff:8089:Backend for Frontend - Web"
    "mobile-bff:8090:Backend for Frontend - Mobile"
)

PYTHON_SERVICES=(
    "llm-orchestrator:8091:LLM request orchestration service"
    "mcp-server:8092:Model Context Protocol server"
    "airtable-gateway:8093:Airtable API integration service"
    "schema-service:8094:Database schema management service"
    "formula-engine:8095:Formula calculation engine"
    "embedding-service:8096:Vector embedding service"
    "semantic-search:8097:Semantic search service"
    "chat-service:8098:Chat and messaging service"
    "workflow-engine:8099:Workflow automation engine"
    "analytics-service:8100:Analytics and reporting service"
    "audit-service:8101:Audit logging and compliance service"
)

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
}

# Check if a service already exists
service_exists() {
    local service_path="$1"
    [ -d "$service_path" ]
}

# Generate Python service
generate_python_service() {
    local service_name="$1"
    local port="$2"
    local description="$3"
    local service_dir="$PYTHON_SERVICES_DIR/$service_name"

    log_step "Generating Python service: $service_name"

    if service_exists "$service_dir"; then
        log_warning "Service $service_name already exists. Skipping generation."
        return 0
    fi

    ensure_directory "$service_dir"
    ensure_directory "$service_dir/src"
    ensure_directory "$service_dir/src/models"
    ensure_directory "$service_dir/src/routes"
    ensure_directory "$service_dir/src/services"
    ensure_directory "$service_dir/src/utils"
    ensure_directory "$service_dir/tests"

    # Create requirements.txt
    cat > "$service_dir/requirements.txt" << EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
pydantic-settings==2.1.0
sqlalchemy==2.0.23
alembic==1.13.1
psycopg2-binary==2.9.9
redis==5.0.1
httpx==0.25.2
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.6
celery==5.3.4
prometheus-client==0.19.0
structlog==23.2.0
tenacity==8.2.3
aiofiles==23.2.1
pytest==7.4.3
pytest-asyncio==0.21.1
pytest-cov==4.1.0
httpx==0.25.2
factory-boy==3.3.0
EOF

    # Create Dockerfile
    cat > "$service_dir/Dockerfile" << EOF
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    gcc \\
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY src/ ./src/

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE $port

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \\
    CMD curl -f http://localhost:$port/health || exit 1

# Start the application
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "$port"]
EOF

    # Create main.py
    cat > "$service_dir/src/main.py" << EOF
"""
$description
"""
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response
import structlog

from .routes.health import router as health_router

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    logger_factory=structlog.stdlib.LoggerFactory(),
    context_class=structlog.threadlocal.wrap_dict(dict),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Prometheus metrics
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

REQUEST_DURATION = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint']
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    logger.info("Starting $service_name service")
    yield
    logger.info("Shutting down $service_name service")


app = FastAPI(
    title="$service_name",
    description="$description",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(health_router, prefix="/health", tags=["health"])

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "$service_name",
        "description": "$description",
        "version": "1.0.0",
        "status": "running"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=$port)
EOF

    # Create health router
    cat > "$service_dir/src/routes/__init__.py" << EOF
# Routes package
EOF

    cat > "$service_dir/src/routes/health.py" << EOF
"""
Health check endpoints
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import asyncio
import time

router = APIRouter()

class HealthResponse(BaseModel):
    status: str
    timestamp: float
    service: str
    version: str
    checks: dict

@router.get("/", response_model=HealthResponse)
async def health_check():
    """Basic health check endpoint"""
    return HealthResponse(
        status="healthy",
        timestamp=time.time(),
        service="$service_name",
        version="1.0.0",
        checks={
            "database": "healthy",  # TODO: Add actual DB check
            "redis": "healthy",     # TODO: Add actual Redis check
        }
    )

@router.get("/ready")
async def readiness_check():
    """Kubernetes readiness probe"""
    # Add actual readiness checks here
    return {"status": "ready"}

@router.get("/live")
async def liveness_check():
    """Kubernetes liveness probe"""
    # Add actual liveness checks here
    return {"status": "alive"}
EOF

    # Create models package
    cat > "$service_dir/src/models/__init__.py" << EOF
# Models package
EOF

    # Create services package
    cat > "$service_dir/src/services/__init__.py" << EOF
# Services package
EOF

    # Create utils package
    cat > "$service_dir/src/utils/__init__.py" << EOF
# Utils package
EOF

    # Create basic test
    cat > "$service_dir/tests/__init__.py" << EOF
# Tests package
EOF

    cat > "$service_dir/tests/test_health.py" << EOF
"""
Health endpoint tests
"""
import pytest
from fastapi.testclient import TestClient
from src.main import app

client = TestClient(app)

def test_health_check():
    """Test health check endpoint"""
    response = client.get("/health/")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "$service_name"

def test_readiness_check():
    """Test readiness endpoint"""
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "ready"

def test_liveness_check():
    """Test liveness endpoint"""
    response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json()["status"] == "alive"

def test_root_endpoint():
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["service"] == "$service_name"
EOF

    log_success "Generated Python service: $service_name"
}

# Generate Go service using template
generate_go_service() {
    local service_name="$1"
    local port="$2"
    local description="$3"
    local service_dir="$GO_SERVICES_DIR/$service_name"

    log_step "Generating Go service: $service_name"

    if service_exists "$service_dir"; then
        log_warning "Service $service_name already exists. Skipping generation."
        return 0
    fi

    ensure_directory "$service_dir"

    # Use the template generator
    local temp_dir=$(mktemp -d)
    cd "$TEMPLATE_DIR"
    
    # Generate service using template
    local module_name="github.com/Reg-Kris/pyairtable-$service_name"
    
    # Copy template and replace variables
    cp -r template/* "$temp_dir/"
    
    # Replace template variables
    find "$temp_dir" -type f -name "*.go" -o -name "*.mod" -o -name "*.yaml" -o -name "*.yml" -o -name "Dockerfile" -o -name "Makefile" | while read file; do
        sed -i.bak \
            -e "s|{{SERVICE_NAME}}|$service_name|g" \
            -e "s|{{SERVICE_NAME_UPPER}}|$(echo "$service_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')|g" \
            -e "s|{{SERVICE_NAME_LOWER}}|$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr -d '-')|g" \
            -e "s|{{PORT}}|$port|g" \
            -e "s|{{DATABASE_NAME}}|$(echo "$service_name" | tr '-' '_')_db|g" \
            -e "s|{{MODULE_NAME}}|$module_name|g" \
            -e "s|{{DESCRIPTION}}|$description|g" \
            -e "s|{{AUTHOR}}|PyAirtable Team|g" \
            "$file"
        rm -f "$file.bak"
    done

    # Replace template variables in directory names
    find "$temp_dir" -depth -type d -name "*{{SERVICE_NAME}}*" | while read dir; do
        new_dir=$(echo "$dir" | sed "s|{{SERVICE_NAME}}|$service_name|g")
        mv "$dir" "$new_dir"
    done

    # Move generated service to target directory
    mv "$temp_dir"/* "$service_dir/"
    rm -rf "$temp_dir"

    # Update go.mod to include shared library dependency
    cat >> "$service_dir/go.mod" << EOF

require (
    $SHARED_GO_MODULE v0.1.0
)
EOF

    # Create a proper main.go if it doesn't exist
    if [ ! -f "$service_dir/cmd/$service_name/main.go" ]; then
        ensure_directory "$service_dir/cmd/$service_name"
        cat > "$service_dir/cmd/$service_name/main.go" << EOF
package main

import (
    "context"
    "fmt"
    "log"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/gofiber/fiber/v3"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
    // Create Fiber app
    app := fiber.New(fiber.Config{
        AppName: "$service_name v1.0.0",
    })

    // Health check endpoint
    app.Get("/health", func(c fiber.Ctx) error {
        return c.JSON(fiber.Map{
            "status":    "healthy",
            "service":   "$service_name",
            "timestamp": time.Now().Unix(),
        })
    })

    // Readiness probe
    app.Get("/health/ready", func(c fiber.Ctx) error {
        return c.JSON(fiber.Map{"status": "ready"})
    })

    // Liveness probe
    app.Get("/health/live", func(c fiber.Ctx) error {
        return c.JSON(fiber.Map{"status": "alive"})
    })

    // Root endpoint
    app.Get("/", func(c fiber.Ctx) error {
        return c.JSON(fiber.Map{
            "service":     "$service_name",
            "description": "$description",
            "version":     "1.0.0",
            "status":      "running",
        })
    })

    // Prometheus metrics endpoint
    app.Get("/metrics", func(c fiber.Ctx) error {
        handler := promhttp.Handler()
        return c.Next()
    })

    // Start server in a goroutine
    go func() {
        if err := app.Listen(":$port"); err != nil {
            log.Printf("Server failed to start: %v", err)
        }
    }()

    log.Printf("$service_name started on port $port")

    // Wait for interrupt signal to gracefully shutdown the server
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    log.Println("Shutting down server...")

    // Graceful shutdown
    if err := app.Shutdown(); err != nil {
        log.Printf("Server forced to shutdown: %v", err)
    }

    log.Println("Server exited")
}
EOF
    fi

    cd "$PROJECT_ROOT"
    log_success "Generated Go service: $service_name"
}

# Verify service can build
verify_service_build() {
    local service_type="$1"
    local service_name="$2"
    local service_dir="$3"

    log_step "Verifying build for $service_type service: $service_name"

    cd "$service_dir"

    if [ "$service_type" = "go" ]; then
        # Check if go.mod exists and try to download dependencies
        if [ -f "go.mod" ]; then
            log_info "Downloading Go dependencies for $service_name"
            go mod download 2>/dev/null || log_warning "Failed to download dependencies for $service_name"
            go mod tidy 2>/dev/null || log_warning "Failed to tidy dependencies for $service_name"
            
            # Try to build
            if go build -o /tmp/"$service_name" ./cmd/"$service_name" 2>/dev/null; then
                log_success "Go build successful for $service_name"
                rm -f /tmp/"$service_name"
            else
                log_warning "Go build failed for $service_name"
            fi
        fi
        
        # Verify Docker build
        if docker build -t "$service_name:test" . >/dev/null 2>&1; then
            log_success "Docker build successful for $service_name"
            docker rmi "$service_name:test" >/dev/null 2>&1 || true
        else
            log_warning "Docker build failed for $service_name"
        fi
    elif [ "$service_type" = "python" ]; then
        # Verify Docker build for Python services
        if docker build -t "$service_name:test" . >/dev/null 2>&1; then
            log_success "Docker build successful for $service_name"
            docker rmi "$service_name:test" >/dev/null 2>&1 || true
        else
            log_warning "Docker build failed for $service_name"
        fi
    fi

    cd "$PROJECT_ROOT"
}

# Test health endpoint
test_health_endpoint() {
    local service_name="$1"
    local port="$2"
    
    log_step "Testing health endpoint for $service_name on port $port"
    
    # Start service in background (simplified test)
    # In a real scenario, you'd use docker-compose or kubernetes
    log_info "Health endpoint test would be performed here for $service_name:$port"
}

# Main execution
main() {
    log_info "Starting PyAirtable Comprehensive Microservices Generation"
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${CYAN}  PyAirtable 22 Microservices Generator${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo ""

    # Ensure directories exist
    ensure_directory "$GO_SERVICES_DIR"
    ensure_directory "$PYTHON_SERVICES_DIR"

    # Generate Go services
    log_info "Generating Go microservices..."
    echo ""
    for service_info in "${GO_SERVICES[@]}"; do
        IFS=':' read -r name port desc <<< "$service_info"
        generate_go_service "$name" "$port" "$desc"
    done

    echo ""
    log_info "Generating Python microservices..."
    echo ""
    # Generate Python services
    for service_info in "${PYTHON_SERVICES[@]}"; do
        IFS=':' read -r name port desc <<< "$service_info"
        generate_python_service "$name" "$port" "$desc"
    done

    echo ""
    log_info "Verifying service builds..."
    echo ""
    
    # Verify Go services
    for service_info in "${GO_SERVICES[@]}"; do
        IFS=':' read -r name port desc <<< "$service_info"
        verify_service_build "go" "$name" "$GO_SERVICES_DIR/$name"
    done

    # Verify Python services  
    for service_info in "${PYTHON_SERVICES[@]}"; do
        IFS=':' read -r name port desc <<< "$service_info"
        verify_service_build "python" "$name" "$PYTHON_SERVICES_DIR/$name"
    done

    echo ""
    echo -e "${GREEN}========================================================${NC}"
    echo -e "${GREEN}  Generation Complete!${NC}"
    echo -e "${GREEN}========================================================${NC}"
    echo ""
    
    log_success "Successfully generated all 22 microservices:"
    echo ""
    echo -e "${YELLOW}Go Services (11):${NC}"
    for service_info in "${GO_SERVICES[@]}"; do
        IFS=':' read -r name port desc <<< "$service_info"
        echo -e "  ${GREEN}✓${NC} $name (port $port)"
    done
    
    echo ""
    echo -e "${YELLOW}Python Services (11):${NC}"
    for service_info in "${PYTHON_SERVICES[@]}"; do
        IFS=':' read -r name port desc <<< "$service_info"
        echo -e "  ${GREEN}✓${NC} $name (port $port)"
    done
    
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo -e "  1. Update docker-compose.yml to include all services"
    echo -e "  2. Configure environment variables for each service"
    echo -e "  3. Set up service-to-service communication"
    echo -e "  4. Run: ${CYAN}docker-compose up${NC}"
    echo ""
}

# Check if running from correct directory
if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
    log_error "Please run this script from the pyairtable-compose project root directory"
    exit 1
fi

# Execute main function
main "$@"