#!/bin/bash
set -e

echo "🛑 Stopping PyAirtable development environment..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Stop all Docker Compose services
echo "📦 Stopping PyAirtable services..."
docker-compose down

# Optional: Stop observability stack if running
if [ -f "docker-compose.observability.yml" ]; then
    echo "📊 Stopping observability stack..."
    docker-compose -f docker-compose.observability.yml down
fi

# Stop Colima to free up system resources
echo "🐳 Stopping Colima container runtime..."
colima stop

# Clean up any orphaned containers or volumes (optional)
echo "🧹 Cleaning up..."
docker system prune -f --volumes || true

echo "✅ Development environment stopped successfully!"
echo "💡 System resources have been freed up."
echo ""
echo "🔧 To restart the environment, run:"
echo "   ./scripts/dev-helpers/start-dev.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"