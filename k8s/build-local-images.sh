#!/bin/bash

# Build all PyAirtable images locally for Minikube

set -e

echo "🔨 Building PyAirtable images for local Kubernetes..."

# Point Docker to Minikube's Docker daemon
eval $(minikube docker-env)

# Base directory
BASE_DIR="/Users/kg/IdeaProjects"

# Build each service
echo "📦 Building API Gateway..."
cd "$BASE_DIR/pyairtable-api-gateway"
docker build -t pyairtable-api-gateway:dev .

echo "📦 Building LLM Orchestrator..."
cd "$BASE_DIR/llm-orchestrator-py"
docker build -t pyairtable-llm-orchestrator:dev .

echo "📦 Building MCP Server..."
cd "$BASE_DIR/mcp-server-py"
docker build -t pyairtable-mcp-server:dev .

echo "📦 Building Airtable Gateway..."
cd "$BASE_DIR/airtable-gateway-py"
docker build -t pyairtable-airtable-gateway:dev .

echo "📦 Building Platform Services..."
cd "$BASE_DIR/pyairtable-platform-services"
docker build -t pyairtable-platform-services:dev .

echo "📦 Building Automation Services..."
cd "$BASE_DIR/pyairtable-automation-services"
docker build -t pyairtable-automation-services:dev .

echo "📦 Building Frontend..."
cd "$BASE_DIR/pyairtable-frontend"
# Create a simple Dockerfile if it doesn't exist
if [ ! -f Dockerfile ]; then
cat > Dockerfile << 'EOF'
FROM node:18-alpine as builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/next.config.js ./
RUN npm ci --production
EXPOSE 3000
CMD ["npm", "start"]
EOF
fi
docker build -t pyairtable-frontend:dev .

echo "✅ All images built successfully!"

# List images
echo -e "\n📋 Local images:"
docker images | grep pyairtable

echo -e "\n🚀 Ready to deploy to Kubernetes!"