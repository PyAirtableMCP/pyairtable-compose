#!/bin/bash

# PyAirtable Compose - Complete Service Setup Script
# This script sets up all 30 services (22 backend + 8 frontend microservices)

set -e

echo "🚀 PyAirtable Compose - Setting up ALL 30 Services"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT=$(pwd)
TEMPLATE_DIR="$PROJECT_ROOT/pyairtable-infrastructure/go-microservice-template"
GO_SERVICES_DIR="$PROJECT_ROOT/go-services"
PYTHON_SERVICES_DIR="$PROJECT_ROOT/python-services"
FRONTEND_SERVICES_DIR="$PROJECT_ROOT/frontend-services"

# Service definitions
GO_SERVICES=(
    "auth-service:8100"
    "user-service:8101" 
    "tenant-service:8102"
    "workspace-service:8103"
    "permission-service:8104"
    "file-service:8105"
    "notification-service:8106"
    "webhook-service:8107"
    "analytics-service:8108"
    "billing-service:8109"
    "audit-service:8110"
    "rate-limit-service:8111"
    "cache-service:8112"
    "search-service:8113"
    "backup-service:8114"
    "migration-service:8115"
)

PYTHON_SERVICES=(
    "ai-service:8200"
    "data-processing-service:8201"
    "report-service:8202"
    "integration-service:8203"
    "task-scheduler:8204"
    "email-service:8205"
)

FRONTEND_SERVICES=(
    "auth-frontend:3001"
    "dashboard-frontend:3002"
    "analytics-frontend:3003"
    "settings-frontend:3004"
    "workspace-frontend:3005"
    "file-manager-frontend:3006"
    "admin-frontend:3007"
    "chat-frontend:3008"
)

# Helper functions
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

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    mkdir -p "$GO_SERVICES_DIR"
    mkdir -p "$PYTHON_SERVICES_DIR"
    mkdir -p "$FRONTEND_SERVICES_DIR"
    mkdir -p "$PROJECT_ROOT/scripts"
    mkdir -p "$PROJECT_ROOT/monitoring"
    mkdir -p "$PROJECT_ROOT/configs"
}

# Function to generate Go service
generate_go_service() {
    local service_name=$1
    local port=$2
    local service_dir="$GO_SERVICES_DIR/$service_name"
    
    log_info "Generating Go service: $service_name (port: $port)"
    
    # Create service directory
    mkdir -p "$service_dir"
    
    # Copy template
    if [ -d "$TEMPLATE_DIR/template" ]; then
        cp -r "$TEMPLATE_DIR/template/"* "$service_dir/"
    else
        log_error "Template directory not found: $TEMPLATE_DIR/template"
        return 1
    fi
    
    # Replace template variables
    find "$service_dir" -type f -name "*.go" -o -name "*.yaml" -o -name "*.yml" -o -name "*.md" | while read -r file; do
        sed -i.bak "s/{{SERVICE_NAME}}/$service_name/g" "$file"
        sed -i.bak "s/{{SERVICE_PORT}}/$port/g" "$file"
        rm -f "$file.bak"
    done
    
    # Update go.mod
    cat > "$service_dir/go.mod" << EOF
module github.com/reg-kris/pyairtable-$service_name

go 1.21

require (
    github.com/gin-gonic/gin v1.9.1
    github.com/lib/pq v1.10.9
    github.com/redis/go-redis/v9 v9.0.5
    github.com/spf13/viper v1.16.0
    go.uber.org/zap v1.24.0
    github.com/prometheus/client_golang v1.16.0
)
EOF

    # Create main.go with service-specific logic
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

    "github.com/gin-gonic/gin"
    "github.com/reg-kris/pyairtable-$service_name/internal/config"
    "github.com/reg-kris/pyairtable-$service_name/internal/handlers"
    "github.com/reg-kris/pyairtable-$service_name/internal/middleware"
    "github.com/reg-kris/pyairtable-$service_name/pkg/database"
    "github.com/reg-kris/pyairtable-$service_name/pkg/logger"
)

func main() {
    // Load configuration
    cfg, err := config.Load()
    if err != nil {
        log.Fatalf("Failed to load config: %v", err)
    }

    // Initialize logger
    logger := logger.New(cfg.LogLevel)
    defer logger.Sync()

    // Initialize database
    db, err := database.New(cfg.DatabaseURL)
    if err != nil {
        logger.Fatal("Failed to connect to database", zap.Error(err))
    }
    defer db.Close()

    // Initialize handlers
    handler := handlers.New(db, logger)

    // Setup router
    router := gin.New()
    router.Use(gin.Recovery())
    router.Use(middleware.Logger(logger))
    router.Use(middleware.CORS())

    // Health check endpoint
    router.GET("/health", func(c *gin.Context) {
        c.JSON(http.StatusOK, gin.H{
            "status": "healthy",
            "service": "$service_name",
            "timestamp": time.Now().UTC(),
        })
    })

    // API routes
    v1 := router.Group("/api/v1")
    {
        v1.Use(middleware.Auth(cfg.JWTSecret))
        handler.RegisterRoutes(v1)
    }

    // Start server
    srv := &http.Server{
        Addr:    fmt.Sprintf(":%s", cfg.Port),
        Handler: router,
    }

    go func() {
        logger.Info("Starting $service_name server on port $port")
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            logger.Fatal("Failed to start server", zap.Error(err))
        }
    }()

    // Wait for interrupt signal to gracefully shutdown
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    logger.Info("Shutting down server...")

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    if err := srv.Shutdown(ctx); err != nil {
        logger.Fatal("Server forced to shutdown", zap.Error(err))
    }

    logger.Info("Server exited")
}
EOF

    # Create Dockerfile
    cat > "$service_dir/Dockerfile" << EOF
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main ./cmd/$service_name

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/

COPY --from=builder /app/main .

EXPOSE $port

CMD ["./main"]
EOF

    log_success "Generated Go service: $service_name"
}

# Function to generate Python service
generate_python_service() {
    local service_name=$1
    local port=$2
    local service_dir="$PYTHON_SERVICES_DIR/$service_name"
    
    log_info "Generating Python service: $service_name (port: $port)"
    
    mkdir -p "$service_dir/src"
    mkdir -p "$service_dir/tests"
    mkdir -p "$service_dir/configs"
    
    # Create requirements.txt
    cat > "$service_dir/requirements.txt" << EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
pydantic-settings==2.1.0
sqlalchemy==2.0.23
asyncpg==0.29.0
redis==5.0.1
python-multipart==0.0.6
aiofiles==23.2.1
pytest==7.4.3
pytest-asyncio==0.21.1
httpx==0.25.2
EOF

    # Create main application
    cat > "$service_dir/src/main.py" << EOF
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os
from datetime import datetime

app = FastAPI(
    title="PyAirtable ${service_name^}",
    description="Microservice for ${service_name} functionality",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "$service_name",
        "timestamp": datetime.utcnow().isoformat(),
        "port": $port
    }

@app.get("/")
async def root():
    return {"message": "PyAirtable $service_name Service", "version": "1.0.0"}

if __name__ == "__main__":
    port = int(os.getenv("PORT", $port))
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        reload=True,
        log_level="info"
    )
EOF

    # Create Dockerfile
    cat > "$service_dir/Dockerfile" << EOF
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY configs/ ./configs/

EXPOSE $port

CMD ["python", "-m", "src.main"]
EOF

    # Create docker-compose override
    cat > "$service_dir/docker-compose.yml" << EOF
version: '3.8'
services:
  $service_name:
    build: .
    ports:
      - "$port:$port"
    environment:
      - PORT=$port
      - LOG_LEVEL=info
    networks:
      - pyairtable-network

networks:
  pyairtable-network:
    external: true
EOF

    log_success "Generated Python service: $service_name"
}

# Function to generate frontend microservice
generate_frontend_service() {
    local service_name=$1
    local port=$2
    local service_dir="$FRONTEND_SERVICES_DIR/$service_name"
    
    log_info "Generating Frontend service: $service_name (port: $port)"
    
    mkdir -p "$service_dir/src/components"
    mkdir -p "$service_dir/src/pages"
    mkdir -p "$service_dir/public"
    
    # Create package.json
    cat > "$service_dir/package.json" << EOF
{
  "name": "pyairtable-$service_name",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "next dev -p $port",
    "build": "next build",
    "start": "next start -p $port",
    "lint": "next lint"
  },
  "dependencies": {
    "next": "14.0.3",
    "react": "18.2.0",
    "react-dom": "18.2.0",
    "@types/node": "20.9.2",
    "@types/react": "18.2.38",
    "@types/react-dom": "18.2.17",
    "typescript": "5.3.2"
  }
}
EOF

    # Create next.config.js
    cat > "$service_dir/next.config.js" << EOF
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: 'http://api-gateway:8000/api/:path*',
      },
    ]
  },
}

module.exports = nextConfig
EOF

    # Create main page
    mkdir -p "$service_dir/src/app"
    cat > "$service_dir/src/app/page.tsx" << EOF
export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-24">
      <div className="z-10 max-w-5xl w-full items-center justify-between font-mono text-sm">
        <h1 className="text-4xl font-bold text-center">
          PyAirtable ${service_name^}
        </h1>
        <p className="text-center mt-4">
          Microservice frontend running on port $port
        </p>
      </div>
    </main>
  )
}
EOF

    # Create layout
    cat > "$service_dir/src/app/layout.tsx" << EOF
import './globals.css'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'PyAirtable ${service_name^}',
  description: 'PyAirtable ${service_name} microservice frontend',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
EOF

    # Create globals.css
    cat > "$service_dir/src/app/globals.css" << EOF
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
    sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
EOF

    # Create Dockerfile
    cat > "$service_dir/Dockerfile" << EOF
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

EXPOSE $port

CMD ["npm", "start"]
EOF

    log_success "Generated Frontend service: $service_name"
}

# Generate all services
generate_all_services() {
    log_info "Generating all 30 services..."
    
    # Generate Go services
    for service_info in "${GO_SERVICES[@]}"; do
        IFS=':' read -r service_name port <<< "$service_info"
        generate_go_service "$service_name" "$port"
    done
    
    # Generate Python services
    for service_info in "${PYTHON_SERVICES[@]}"; do
        IFS=':' read -r service_name port <<< "$service_info"
        generate_python_service "$service_name" "$port"
    done
    
    # Generate Frontend services
    for service_info in "${FRONTEND_SERVICES[@]}"; do
        IFS=':' read -r service_name port <<< "$service_info"
        generate_frontend_service "$service_name" "$port"
    done
}

# Create comprehensive docker-compose file
create_full_docker_compose() {
    log_info "Creating comprehensive docker-compose.full.yml..."
    
    cat > "$PROJECT_ROOT/docker-compose.full.yml" << 'EOF'
version: '3.8'

services:
  # Infrastructure Services
  postgres:
    image: postgres:16-alpine
    environment:
      - POSTGRES_DB=${POSTGRES_DB:-pyairtable}
      - POSTGRES_USER=${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init-db.sql:/docker-entrypoint-initdb.d/init-db.sql:ro
    restart: unless-stopped
    networks:
      - pyairtable-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD:-redis}
    volumes:
      - redis-data:/data
    restart: unless-stopped
    networks:
      - pyairtable-network
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

  # Existing Core Services
  api-gateway:
    image: ghcr.io/reg-kris/pyairtable-api-gateway:latest
    build:
      context: ../pyairtable-api-gateway
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - API_KEY=${API_KEY}
      - LOG_LEVEL=${LOG_LEVEL:-info}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - pyairtable-network

  llm-orchestrator:
    image: ghcr.io/reg-kris/llm-orchestrator-py:latest
    build:
      context: ../llm-orchestrator-py
      dockerfile: Dockerfile
    ports:
      - "8003:8003"
    environment:
      - GEMINI_API_KEY=${GEMINI_API_KEY}
      - REDIS_URL=redis://redis:6379
      - REDIS_PASSWORD=${REDIS_PASSWORD:-redis}
    depends_on:
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - pyairtable-network

  mcp-server:
    image: ghcr.io/reg-kris/mcp-server-py:latest
    build:
      context: ../mcp-server-py
      dockerfile: Dockerfile
    ports:
      - "8001:8001"
    environment:
      - MCP_SERVER_MODE=http
      - MCP_SERVER_PORT=8001
      - LOG_LEVEL=${LOG_LEVEL:-info}
    restart: unless-stopped
    networks:
      - pyairtable-network

  airtable-gateway:
    image: ghcr.io/reg-kris/airtable-gateway-py:latest
    build:
      context: ../airtable-gateway-py
      dockerfile: Dockerfile
    ports:
      - "8002:8002"
    environment:
      - AIRTABLE_TOKEN=${AIRTABLE_TOKEN}
      - AIRTABLE_BASE=${AIRTABLE_BASE}
      - API_KEY=${API_KEY}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - pyairtable-network

  platform-services:
    image: ghcr.io/reg-kris/pyairtable-platform-services:latest
    build:
      context: ../pyairtable-platform-services
      dockerfile: Dockerfile
    ports:
      - "8007:8007"
    environment:
      - DATABASE_URL=postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@postgres:5432/${POSTGRES_DB:-pyairtable}
      - REDIS_URL=redis://redis:6379
      - REDIS_PASSWORD=${REDIS_PASSWORD:-redis}
      - API_KEY=${API_KEY}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - pyairtable-network

  automation-services:
    image: ghcr.io/reg-kris/pyairtable-automation-services:latest
    build:
      context: ../pyairtable-automation-services
      dockerfile: Dockerfile
    ports:
      - "8006:8006"
    environment:
      - DATABASE_URL=postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@postgres:5432/${POSTGRES_DB:-pyairtable}
      - REDIS_URL=redis://redis:6379
      - REDIS_PASSWORD=${REDIS_PASSWORD:-redis}
      - API_KEY=${API_KEY}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - pyairtable-network

EOF

    # Add Go services
    for service_info in "${GO_SERVICES[@]}"; do
        IFS=':' read -r service_name port <<< "$service_info"
        cat >> "$PROJECT_ROOT/docker-compose.full.yml" << EOF
  # Go Microservice: $service_name
  $service_name:
    build:
      context: ./go-services/$service_name
      dockerfile: Dockerfile
    ports:
      - "$port:$port"
    environment:
      - PORT=$port
      - DATABASE_URL=postgresql://\${POSTGRES_USER:-postgres}:\${POSTGRES_PASSWORD:-postgres}@postgres:5432/\${POSTGRES_DB:-pyairtable}
      - REDIS_URL=redis://redis:6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD:-redis}
      - JWT_SECRET=\${JWT_SECRET:-default-jwt-secret}
      - LOG_LEVEL=\${LOG_LEVEL:-info}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - pyairtable-network
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:$port/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

EOF
    done

    # Add Python services
    for service_info in "${PYTHON_SERVICES[@]}"; do
        IFS=':' read -r service_name port <<< "$service_info"
        cat >> "$PROJECT_ROOT/docker-compose.full.yml" << EOF
  # Python Microservice: $service_name
  $service_name:
    build:
      context: ./python-services/$service_name
      dockerfile: Dockerfile
    ports:
      - "$port:$port"
    environment:
      - PORT=$port
      - DATABASE_URL=postgresql://\${POSTGRES_USER:-postgres}:\${POSTGRES_PASSWORD:-postgres}@postgres:5432/\${POSTGRES_DB:-pyairtable}
      - REDIS_URL=redis://redis:6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD:-redis}
      - LOG_LEVEL=\${LOG_LEVEL:-info}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - pyairtable-network
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:$port/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

EOF
    done

    # Add Frontend services
    for service_info in "${FRONTEND_SERVICES[@]}"; do
        IFS=':' read -r service_name port <<< "$service_info"
        cat >> "$PROJECT_ROOT/docker-compose.full.yml" << EOF
  # Frontend Microservice: $service_name
  $service_name:
    build:
      context: ./frontend-services/$service_name
      dockerfile: Dockerfile
    ports:
      - "$port:$port"
    environment:
      - PORT=$port
      - NEXT_PUBLIC_API_URL=http://localhost:8000
      - NODE_ENV=\${NODE_ENV:-development}
    depends_on:
      - api-gateway
    restart: unless-stopped
    networks:
      - pyairtable-network
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:$port/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

EOF
    done

    # Add networks and volumes
    cat >> "$PROJECT_ROOT/docker-compose.full.yml" << 'EOF'

networks:
  pyairtable-network:
    driver: bridge

volumes:
  postgres-data:
    driver: local
  redis-data:
    driver: local
EOF

    log_success "Created docker-compose.full.yml with all 30 services"
}

# Create startup script
create_startup_script() {
    log_info "Creating startup and monitoring scripts..."
    
    cat > "$PROJECT_ROOT/start-all-services.sh" << 'EOF'
#!/bin/bash

# Start all PyAirtable services with proper ordering

set -e

echo "🚀 Starting PyAirtable Full Stack (30 services)"
echo "=============================================="

# Phase 1: Infrastructure
echo "Phase 1: Starting Infrastructure services..."
docker-compose -f docker-compose.full.yml up -d postgres redis

# Wait for infrastructure
echo "Waiting for infrastructure to be ready..."
sleep 15

# Phase 2: Core services
echo "Phase 2: Starting Core services..."
docker-compose -f docker-compose.full.yml up -d \
  api-gateway \
  airtable-gateway \
  mcp-server \
  llm-orchestrator \
  platform-services \
  automation-services

# Wait for core services
echo "Waiting for core services to be ready..."
sleep 20

# Phase 3: Go microservices
echo "Phase 3: Starting Go microservices..."
docker-compose -f docker-compose.full.yml up -d \
  auth-service \
  user-service \
  tenant-service \
  workspace-service \
  permission-service \
  file-service \
  notification-service \
  webhook-service \
  analytics-service \
  billing-service \
  audit-service \
  rate-limit-service \
  cache-service \
  search-service \
  backup-service \
  migration-service

# Wait for Go services
echo "Waiting for Go services to be ready..."
sleep 25

# Phase 4: Python microservices
echo "Phase 4: Starting Python microservices..."
docker-compose -f docker-compose.full.yml up -d \
  ai-service \
  data-processing-service \
  report-service \
  integration-service \
  task-scheduler \
  email-service

# Wait for Python services
echo "Waiting for Python services to be ready..."
sleep 20

# Phase 5: Frontend microservices
echo "Phase 5: Starting Frontend microservices..."
docker-compose -f docker-compose.full.yml up -d \
  auth-frontend \
  dashboard-frontend \
  analytics-frontend \
  settings-frontend \
  workspace-frontend \
  file-manager-frontend \
  admin-frontend \
  chat-frontend

echo "✅ All services started! Waiting for final health checks..."
sleep 30

echo "🎉 PyAirtable Full Stack is running!"
echo ""
echo "Service URLs:"
echo "============"
echo "🌐 Main API Gateway:     http://localhost:8000"
echo "🤖 LLM Orchestrator:     http://localhost:8003"
echo "📡 MCP Server:           http://localhost:8001"
echo "🔗 Airtable Gateway:     http://localhost:8002"
echo "⚙️  Platform Services:    http://localhost:8007"
echo "🤖 Automation Services:  http://localhost:8006"
echo ""
echo "🎯 Frontend Services:"
echo "Auth:        http://localhost:3001"
echo "Dashboard:   http://localhost:3002"
echo "Analytics:   http://localhost:3003"
echo "Settings:    http://localhost:3004"
echo "Workspace:   http://localhost:3005"
echo "Files:       http://localhost:3006"
echo "Admin:       http://localhost:3007"
echo "Chat:        http://localhost:3008"
echo ""
echo "Run './monitor-services.sh' to check service health"
EOF

    chmod +x "$PROJECT_ROOT/start-all-services.sh"

    # Create monitoring script
    cat > "$PROJECT_ROOT/monitor-services.sh" << 'EOF'
#!/bin/bash

# Monitor all PyAirtable services

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_service() {
    local name=$1
    local url=$2
    
    if curl -s --max-time 5 "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ $name${NC} - $url"
        return 0
    else
        echo -e "${RED}❌ $name${NC} - $url"
        return 1
    fi
}

echo "🔍 PyAirtable Service Health Check"
echo "=================================="

total=0
healthy=0

# Core services
echo "Core Services:"
for service in \
    "API Gateway:http://localhost:8000/health" \
    "LLM Orchestrator:http://localhost:8003/health" \
    "MCP Server:http://localhost:8001/health" \
    "Airtable Gateway:http://localhost:8002/health" \
    "Platform Services:http://localhost:8007/health" \
    "Automation Services:http://localhost:8006/health"
do
    IFS=':' read -r name url <<< "$service"
    if check_service "$name" "$url"; then
        ((healthy++))
    fi
    ((total++))
done

echo ""
echo "Go Microservices:"
# Go services health checks
for port in 8100 8101 8102 8103 8104 8105 8106 8107 8108 8109 8110 8111 8112 8113 8114 8115; do
    service_name=$(docker-compose -f docker-compose.full.yml ps --services | grep ":$port")
    if [ -n "$service_name" ]; then
        if check_service "Go Service ($port)" "http://localhost:$port/health"; then
            ((healthy++))
        fi
    fi
    ((total++))
done

echo ""
echo "Python Microservices:"
# Python services health checks
for port in 8200 8201 8202 8203 8204 8205; do
    service_name=$(docker-compose -f docker-compose.full.yml ps --services | grep ":$port")
    if [ -n "$service_name" ]; then
        if check_service "Python Service ($port)" "http://localhost:$port/health"; then
            ((healthy++))
        fi
    fi
    ((total++))
done

echo ""
echo "Frontend Microservices:"
# Frontend services health checks  
for port in 3001 3002 3003 3004 3005 3006 3007 3008; do
    service_name=$(docker-compose -f docker-compose.full.yml ps --services | grep ":$port")
    if [ -n "$service_name" ]; then
        if check_service "Frontend Service ($port)" "http://localhost:$port/"; then
            ((healthy++))
        fi
    fi
    ((total++))
done

echo ""
echo "=================================="
if [ $healthy -eq $total ]; then
    echo -e "${GREEN}🎉 All $total services are healthy!${NC}"
else
    echo -e "${YELLOW}⚠️  $healthy/$total services are healthy${NC}"
fi

# Show resource usage
echo ""
echo "📊 Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
EOF

    chmod +x "$PROJECT_ROOT/monitor-services.sh"

    log_success "Created startup and monitoring scripts"
}

# Create integration test
create_integration_test() {
    log_info "Creating integration test script..."
    
    cat > "$PROJECT_ROOT/test-integration.sh" << 'EOF'
#!/bin/bash

# Integration test for all PyAirtable services

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

echo "🧪 PyAirtable Integration Test Suite"
echo "===================================="

passed=0
failed=0

test_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="${3:-200}"
    
    log_info "Testing $name..."
    
    if response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$url" 2>/dev/null); then
        status_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
        body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]{3}$//')
        
        if [ "$status_code" = "$expected_status" ]; then
            log_success "$name responded with $status_code"
            ((passed++))
            return 0
        else
            log_error "$name responded with $status_code (expected $expected_status)"
            ((failed++))
            return 1
        fi
    else
        log_error "$name is unreachable"
        ((failed++))
        return 1
    fi
}

# Test core services
echo "Testing Core Services..."
test_endpoint "API Gateway Health" "http://localhost:8000/health"
test_endpoint "MCP Server Health" "http://localhost:8001/health"
test_endpoint "Airtable Gateway Health" "http://localhost:8002/health"
test_endpoint "LLM Orchestrator Health" "http://localhost:8003/health"
test_endpoint "Automation Services Health" "http://localhost:8006/health"
test_endpoint "Platform Services Health" "http://localhost:8007/health"

# Test Go microservices
echo ""
echo "Testing Go Microservices..."
for port in 8100 8101 8102 8103 8104 8105 8106 8107 8108 8109 8110 8111 8112 8113 8114 8115; do
    test_endpoint "Go Service Port $port" "http://localhost:$port/health"
done

# Test Python microservices
echo ""
echo "Testing Python Microservices..."
for port in 8200 8201 8202 8203 8204 8205; do
    test_endpoint "Python Service Port $port" "http://localhost:$port/health"
done

# Test Frontend microservices
echo ""
echo "Testing Frontend Microservices..."
for port in 3001 3002 3003 3004 3005 3006 3007 3008; do
    test_endpoint "Frontend Service Port $port" "http://localhost:$port/"
done

# Summary
echo ""
echo "===================================="
echo "Test Results:"
echo "============="
echo -e "Passed: ${GREEN}$passed${NC}"
echo -e "Failed: ${RED}$failed${NC}"
echo -e "Total:  $(($passed + $failed))"

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed.${NC}"
    exit 1
fi
EOF

    chmod +x "$PROJECT_ROOT/test-integration.sh"
    
    log_success "Created integration test script"
}

# Create environment file template
create_env_template() {
    log_info "Creating environment template..."
    
    cat > "$PROJECT_ROOT/.env.template" << 'EOF'
# PyAirtable Full Stack Configuration
# Copy this to .env and fill in your actual values

# Core API Configuration
API_KEY=your-api-key-here
LOG_LEVEL=info
ENVIRONMENT=development

# Database Configuration
POSTGRES_DB=pyairtable
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your-postgres-password

# Redis Configuration
REDIS_PASSWORD=your-redis-password

# Airtable Integration
AIRTABLE_TOKEN=your-airtable-token
AIRTABLE_BASE=your-base-id

# AI/LLM Configuration
GEMINI_API_KEY=your-gemini-api-key

# JWT Configuration
JWT_SECRET=your-super-secret-jwt-key-change-in-production
NEXTAUTH_SECRET=your-nextauth-secret

# CORS Configuration
CORS_ORIGINS=*

# Feature Flags
ENABLE_DEBUG=false
SHOW_COST_TRACKING=true
REQUIRE_API_KEY=true

# File Upload Configuration
MAX_FILE_SIZE=10MB
ALLOWED_EXTENSIONS=pdf,doc,docx,txt,csv,xlsx
UPLOAD_DIR=/tmp/uploads

# Workflow Configuration
DEFAULT_WORKFLOW_TIMEOUT=300
MAX_WORKFLOW_RETRIES=3
SCHEDULER_CHECK_INTERVAL=30

# Auth Configuration
PASSWORD_MIN_LENGTH=8
PASSWORD_HASH_ROUNDS=12

# Analytics Configuration
ANALYTICS_RETENTION_DAYS=90
METRICS_BATCH_SIZE=100

# Node.js Environment
NODE_ENV=development
EOF

    log_success "Created .env.template"
}

# Main execution
main() {
    echo "🚀 Starting PyAirtable Full Stack Setup"
    echo "========================================"
    
    create_directories
    generate_all_services
    create_full_docker_compose
    create_startup_script
    create_integration_test
    create_env_template
    
    echo ""
    echo "✅ Setup Complete!"
    echo "=================="
    echo ""
    echo "Next Steps:"
    echo "1. Copy .env.template to .env and configure your values"
    echo "2. Run: ./start-all-services.sh"
    echo "3. Monitor: ./monitor-services.sh"  
    echo "4. Test: ./test-integration.sh"
    echo ""
    echo "Service Architecture:"
    echo "- 6 Core services (ports 8000-8007)"
    echo "- 16 Go microservices (ports 8100-8115)" 
    echo "- 6 Python microservices (ports 8200-8205)"
    echo "- 8 Frontend microservices (ports 3001-3008)"
    echo "- PostgreSQL + Redis infrastructure"
    echo ""
    echo "Total: 30 services + 2 infrastructure components"
    echo ""
    echo "🎯 Ready to build the future of Airtable automation!"
}

# Run if script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
EOF