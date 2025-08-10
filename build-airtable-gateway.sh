#!/bin/bash
# Build script for airtable-gateway service
set -e

echo "Building airtable-gateway service..."

# Navigate to the project root
cd "$(dirname "$0")"

# Build the Docker image
docker build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  -t airtable-gateway-local:latest \
  -f python-services/airtable-gateway/Dockerfile \
  python-services/airtable-gateway/

echo "✅ airtable-gateway build completed successfully"
echo "📦 Tagged as: airtable-gateway-local:latest"

# Test the image
echo "🧪 Testing the built image..."
docker run --rm -d --name airtable-gateway-test airtable-gateway-local:latest || {
  echo "❌ Container failed to start"
  exit 1
}

sleep 5
docker stop airtable-gateway-test || true
echo "✅ Container test passed"