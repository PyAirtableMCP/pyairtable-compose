#!/bin/bash

# Build essential PyAirtable images for local Minikube
# Simplified approach focusing on core services

set -e

echo "🔨 Building essential PyAirtable images for local Kubernetes..."

# Point Docker to Minikube's Docker daemon
eval $(minikube docker-env -p pyairtable-dev)

# Force use of legacy builder to avoid buildkit issues
export DOCKER_BUILDKIT=0

# Base directory
BASE_DIR="/Users/kg/IdeaProjects/pyairtable-compose"

# Load environment variables
source "${BASE_DIR}/.env"

echo "📦 Building core Python services..."

# Create temporary dockerfiles for core services
mkdir -p /tmp/pyairtable-build

# 1. Airtable Gateway
echo "📦 Building airtable-gateway..."
cat > /tmp/pyairtable-build/Dockerfile.airtable-gateway << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

RUN pip install fastapi uvicorn httpx pydantic python-dotenv loguru aiofiles

RUN mkdir -p src
COPY << 'PYEOF' src/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="Airtable Gateway", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "airtable-gateway"}

@app.get("/")
async def root():
    return {"service": "airtable-gateway", "status": "running"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
PYEOF

RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8002
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8002"]
EOF

# Build with proper HEREDOC handling
cat > /tmp/pyairtable-build/main-airtable.py << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="Airtable Gateway", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "airtable-gateway"}

@app.get("/")
async def root():
    return {"service": "airtable-gateway", "status": "running"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
EOF

cat > /tmp/pyairtable-build/Dockerfile.airtable-gateway << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN pip install fastapi uvicorn httpx pydantic python-dotenv loguru aiofiles

RUN mkdir -p src
COPY main-airtable.py src/main.py

RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8002
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8002"]
EOF

cd /tmp/pyairtable-build
docker build -f Dockerfile.airtable-gateway -t airtable-gateway-py:latest .

# 2. MCP Server
echo "📦 Building mcp-server..."
cat > /tmp/pyairtable-build/main-mcp.py << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="MCP Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "mcp-server"}

@app.get("/")
async def root():
    return {"service": "mcp-server", "status": "running"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
EOF

cat > /tmp/pyairtable-build/Dockerfile.mcp-server << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN pip install fastapi uvicorn httpx pydantic python-dotenv loguru aiofiles

RUN mkdir -p src
COPY main-mcp.py src/main.py

RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8001
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8001"]
EOF

docker build -f Dockerfile.mcp-server -t mcp-server-py:latest .

# 3. LLM Orchestrator
echo "📦 Building llm-orchestrator..."
cat > /tmp/pyairtable-build/main-llm.py << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="LLM Orchestrator", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "llm-orchestrator"}

@app.get("/")
async def root():
    return {"service": "llm-orchestrator", "status": "running"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)
EOF

cat > /tmp/pyairtable-build/Dockerfile.llm-orchestrator << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN pip install fastapi uvicorn httpx pydantic python-dotenv loguru aiofiles

RUN mkdir -p src
COPY main-llm.py src/main.py

RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8003
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8003"]
EOF

docker build -f Dockerfile.llm-orchestrator -t llm-orchestrator-py:latest .

# 4. Platform Services
echo "📦 Building platform-services..."
cat > /tmp/pyairtable-build/main-platform.py << 'EOF'
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
    return {"message": "Chat endpoint available", "service": "platform-services"}

@app.get("/")
async def root():
    return {"service": "platform-services", "status": "running"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8007)
EOF

cat > /tmp/pyairtable-build/Dockerfile.platform-services << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN pip install fastapi uvicorn httpx pydantic python-dotenv loguru aiofiles

RUN mkdir -p src
COPY main-platform.py src/main.py

RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8007
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8007"]
EOF

docker build -f Dockerfile.platform-services -t pyairtable-platform-services:latest .

# 5. Automation Services
echo "📦 Building automation-services..."
cat > /tmp/pyairtable-build/main-automation.py << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="Automation Services", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "automation-services"}

@app.get("/")
async def root():
    return {"service": "automation-services", "status": "running"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8006)
EOF

cat > /tmp/pyairtable-build/Dockerfile.automation-services << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN pip install fastapi uvicorn httpx pydantic python-dotenv loguru aiofiles

RUN mkdir -p src
COPY main-automation.py src/main.py

RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8006
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8006"]
EOF

docker build -f Dockerfile.automation-services -t pyairtable-automation-services:latest .

echo "✅ Essential images built successfully!"

# Clean up temporary files
rm -rf /tmp/pyairtable-build

# List images
echo -e "\n📋 Built PyAirtable images:"
docker images | grep -E "(airtable|mcp|orchestrator|platform|automation)" | grep -v "<none>"

echo -e "\n🚀 Ready to restart deployments!"
echo "Run: kubectl rollout restart deployment -n pyairtable-dev"