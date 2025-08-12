#!/bin/bash
# Development environment startup script
set -e

echo "🚀 Starting PyAirtable development environment..."

# Start services in development mode with hot reload
docker-compose -f docker-compose.yml up --build

echo "✅ Development environment started"