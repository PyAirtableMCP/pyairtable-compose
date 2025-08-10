#!/bin/bash
# Comprehensive build script for all PyAirtableMCP services
set -e

echo "🚀 Building PyAirtableMCP Services"
echo "=================================="

# Navigate to the project root
cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to build a service
build_service() {
    local service_name=$1
    local context_dir=$2
    local image_tag=$3
    
    print_status "Building $service_name..."
    
    if [ ! -d "$context_dir" ]; then
        print_error "Context directory $context_dir not found for $service_name"
        return 1
    fi
    
    if [ ! -f "$context_dir/Dockerfile" ]; then
        print_error "Dockerfile not found in $context_dir for $service_name"
        return 1
    fi
    
    # Build the image
    docker build \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        -t "$image_tag" \
        -f "$context_dir/Dockerfile" \
        "$context_dir" || {
        print_error "Failed to build $service_name"
        return 1
    }
    
    print_success "✅ $service_name built successfully as $image_tag"
}

# Function to test a service
test_service() {
    local service_name=$1
    local image_tag=$2
    local expected_port=$3
    
    print_status "Testing $service_name..."
    
    # Start container in detached mode
    container_id=$(docker run -d --name "${service_name}-test" "$image_tag") || {
        print_error "Failed to start test container for $service_name"
        return 1
    }
    
    # Wait for container to be ready
    sleep 10
    
    # Check if container is still running
    if ! docker ps | grep -q "${service_name}-test"; then
        print_error "Container $service_name failed to start or exited"
        docker logs "${service_name}-test" 2>/dev/null || true
        docker rm -f "${service_name}-test" 2>/dev/null || true
        return 1
    fi
    
    # Clean up
    docker stop "${service_name}-test" >/dev/null 2>&1
    docker rm "${service_name}-test" >/dev/null 2>&1
    
    print_success "✅ $service_name container test passed"
}

# Create build timestamp
BUILD_TIME=$(date +%Y%m%d-%H%M%S)
print_status "Build timestamp: $BUILD_TIME"

# Build Python services
print_status "Building Python Services..."
print_status "============================"

# Airtable Gateway
build_service "airtable-gateway" "./python-services/airtable-gateway" "airtable-gateway-local:latest"
test_service "airtable-gateway" "airtable-gateway-local:latest" "8002"

# MCP Server
build_service "mcp-server" "./python-services/mcp-server" "mcp-server-test:latest"
test_service "mcp-server" "mcp-server-test:latest" "8001"

# LLM Orchestrator
if [ -d "./python-services/llm-orchestrator" ]; then
    build_service "llm-orchestrator" "./python-services/llm-orchestrator" "llm-orchestrator-test:latest"
    test_service "llm-orchestrator" "llm-orchestrator-test:latest" "8003"
else
    print_warning "LLM Orchestrator service directory not found - skipping"
fi

# Build additional services if they exist
additional_services=(
    "ai-service:./python-services/ai-service:ai-service-local:latest"
    "analytics-service:./python-services/analytics-service:analytics-service-local:latest"
    "audit-service:./python-services/audit-service:audit-service-local:latest"
    "chat-service:./python-services/chat-service:chat-service-local:latest"
    "embedding-service:./python-services/embedding-service:embedding-service-local:latest"
    "formula-engine:./python-services/formula-engine:formula-engine-local:latest"
    "schema-service:./python-services/schema-service:schema-service-local:latest"
    "semantic-search:./python-services/semantic-search:semantic-search-local:latest"
    "workflow-engine:./python-services/workflow-engine:workflow-engine-local:latest"
)

for service_config in "${additional_services[@]}"; do
    IFS=":" read -r service_name context_dir image_tag <<< "$service_config"
    if [ -d "$context_dir" ] && [ -f "$context_dir/Dockerfile" ]; then
        build_service "$service_name" "$context_dir" "$image_tag"
        # Skip testing for simpler services to speed up build
    else
        print_warning "$service_name directory or Dockerfile not found - skipping"
    fi
done

# Build Frontend services if they exist
print_status "Building Frontend Services..."
print_status "=============================="

frontend_services=(
    "admin-dashboard:./frontend-services/admin-dashboard:admin-dashboard-local:latest"
    "tenant-dashboard:./frontend-services/tenant-dashboard:tenant-dashboard-local:latest"
    "auth-frontend:./frontend-services/auth-frontend:auth-frontend-local:latest"
    "event-sourcing-ui:./frontend-services/event-sourcing-ui:event-sourcing-ui-local:latest"
)

for service_config in "${frontend_services[@]}"; do
    IFS=":" read -r service_name context_dir image_tag <<< "$service_config"
    if [ -d "$context_dir" ] && [ -f "$context_dir/Dockerfile" ]; then
        build_service "$service_name" "$context_dir" "$image_tag"
    else
        print_warning "$service_name directory or Dockerfile not found - skipping"
    fi
done

# Display summary
print_status "Build Summary"
print_status "============="
echo ""
docker images | grep -E "(airtable-gateway-local|mcp-server-test|llm-orchestrator-test)" | head -10

# Save build info
cat > build-info.json << EOF
{
  "build_time": "$BUILD_TIME",
  "services_built": [
    "airtable-gateway-local:latest",
    "mcp-server-test:latest",
    "llm-orchestrator-test:latest"
  ],
  "docker_compose_file": "docker-compose.minimal-working.yml",
  "notes": "Local development build - not for production use"
}
EOF

print_success "🎉 Build completed successfully!"
print_status "📋 Build info saved to build-info.json"
print_status "🐳 To start services: docker-compose -f docker-compose.minimal-working.yml up"
print_status ""
print_warning "⚠️  Remember to set up environment variables before starting services"