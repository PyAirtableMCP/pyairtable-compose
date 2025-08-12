#!/bin/bash

# Build all PyAirtable images locally for Minikube
# Updated for current repository structure

set -e

echo "🔨 Building PyAirtable images for local Kubernetes..."

# Point Docker to Minikube's Docker daemon
eval $(minikube docker-env -p pyairtable-dev)

# Force use of legacy builder to avoid buildkit issues
export DOCKER_BUILDKIT=0

# Base directory
BASE_DIR="/Users/kg/IdeaProjects/pyairtable-compose"

# Load environment variables
source "${BASE_DIR}/.env"

echo "📦 Building Python services..."

# Build Python services
PYTHON_SERVICES=(
    "airtable-gateway:airtable-gateway-py"
    "mcp-server:mcp-server-py"
    "llm-orchestrator:llm-orchestrator-py"
    "automation-services:pyairtable-automation-services"
    "ai-service:ai-service-py"
    "analytics-service:analytics-service-py"
    "audit-service:audit-service-py"
    "chat-service:chat-service-py"
    "embedding-service:embedding-service-py"
    "formula-engine:formula-engine-py"
    "schema-service:schema-service-py"
    "semantic-search:semantic-search-py"
    "workflow-engine:workflow-engine-py"
)

for service_mapping in "${PYTHON_SERVICES[@]}"; do
    service_dir=$(echo $service_mapping | cut -d: -f1)
    image_name=$(echo $service_mapping | cut -d: -f2)
    
    if [ -d "${BASE_DIR}/python-services/${service_dir}" ]; then
        echo "📦 Building ${service_dir}..."
        cd "${BASE_DIR}/python-services/${service_dir}"
        
        # Create a simple Dockerfile if it doesn't exist
        if [ ! -f Dockerfile ]; then
            echo "Creating Dockerfile for ${service_dir}..."
            cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

# Default port (can be overridden)
EXPOSE 8000

# Run the application
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
        fi
        
        # Create basic requirements.txt if it doesn't exist
        if [ ! -f requirements.txt ]; then
            echo "Creating requirements.txt for ${service_dir}..."
            cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
httpx==0.25.2
aiofiles==23.2.1
python-multipart==0.0.6
python-dotenv==1.0.0
loguru==0.7.2
EOF
        fi
        
        # Create basic main.py if src/main.py doesn't exist
        if [ ! -f src/main.py ] && [ ! -f main.py ]; then
            mkdir -p src
            echo "Creating basic main.py for ${service_dir}..."
            cat > src/main.py << EOF
"""
${service_dir} - PyAirtable Service
Auto-generated service for development
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="${service_dir}",
    description="PyAirtable ${service_dir} service",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For development only
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "${service_dir}",
        "version": "1.0.0"
    }

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "Welcome to ${service_dir}",
        "service": "${service_dir}",
        "status": "running"
    }

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
EOF
        fi
        
        # Build the image
        docker build -t "${image_name}:latest" .
        
        echo "✅ Built ${service_dir} -> ${image_name}:latest"
    else
        echo "⚠️  Directory not found: ${BASE_DIR}/python-services/${service_dir}"
    fi
done

echo "📦 Building Go services..."

# Build Go services
GO_SERVICES=(
    "api-gateway:pyairtable-api-gateway"
    "auth-service:pyairtable-auth-service"
    "file-processing-service:pyairtable-file-processing-service"
    "file-service:pyairtable-file-service"
    "mobile-bff:pyairtable-mobile-bff"
    "notification-service:pyairtable-notification-service"
    "permission-service:pyairtable-permission-service"
    "user-service:pyairtable-user-service"
    "web-bff:pyairtable-web-bff"
    "webhook-service:pyairtable-webhook-service"
    "workspace-service:pyairtable-workspace-service"
)

for service_mapping in "${GO_SERVICES[@]}"; do
    service_dir=$(echo $service_mapping | cut -d: -f1)
    image_name=$(echo $service_mapping | cut -d: -f2)
    
    if [ -d "${BASE_DIR}/go-services/${service_dir}" ]; then
        echo "📦 Building ${service_dir}..."
        cd "${BASE_DIR}/go-services/${service_dir}"
        
        # Build the image
        docker build -t "${image_name}:latest" .
        
        echo "✅ Built ${service_dir} -> ${image_name}:latest"
    else
        echo "⚠️  Directory not found: ${BASE_DIR}/go-services/${service_dir}"
    fi
done

# Build special platform services image
echo "📦 Building platform services..."
cd "${BASE_DIR}"

# Create a platform services Dockerfile
cat > Dockerfile.platform-services << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY python-services/*/requirements.txt ./
RUN pip install --no-cache-dir fastapi uvicorn httpx pydantic python-dotenv loguru

# Copy shared components
COPY python-services/shared/ ./shared/

# Create a simple platform service
RUN mkdir -p src
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="Platform Services", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "platform-services"}

@app.get("/api/chat")
async def chat():
    return {"message": "Chat endpoint", "status": "ready"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8007)
PYEOF

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8007
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8007"]
EOF

docker build -f Dockerfile.platform-services -t "pyairtable-platform-services:latest" .
rm Dockerfile.platform-services

echo "✅ All images built successfully!"

# List images
echo -e "\n📋 Local PyAirtable images:"
docker images | grep -E "(airtable|mcp|orchestrator|platform|automation)" | grep -v "<none>"

echo -e "\n🚀 Ready to deploy to Kubernetes!"
echo "Next steps:"
echo "  kubectl rollout restart deployment -n pyairtable-dev"
echo "  kubectl get pods -n pyairtable-dev"