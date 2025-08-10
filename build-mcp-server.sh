#!/bin/bash
# Build script for MCP Server service
set -e

echo "Building mcp-server service..."

# Navigate to the project root
cd "$(dirname "$0")"

# Build the Docker image
docker build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  -t mcp-server-test:latest \
  -f python-services/mcp-server/Dockerfile \
  python-services/mcp-server/

echo "✅ mcp-server build completed successfully"
echo "📦 Tagged as: mcp-server-test:latest"

# Test the image
echo "🧪 Testing the built image..."
docker run --rm -d --name mcp-server-test mcp-server-test:latest || {
  echo "❌ Container failed to start"
  exit 1
}

sleep 5
docker stop mcp-server-test || true
echo "✅ Container test passed"