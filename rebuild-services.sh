#!/bin/bash

echo "🔨 Rebuilding PyAirtable Services"
echo "================================="

# Stop all services
echo "⏹️  Stopping all services..."
docker-compose down

# Remove old images (optional - uncomment if needed)
# docker-compose down --rmi all

# Rebuild with no cache
echo "🏗️  Rebuilding all services..."
docker-compose build --no-cache

# Start services
echo "🚀 Starting rebuilt services..."
./start-current-services.sh

echo "✅ Rebuild complete!"
