#!/bin/bash

# PyAirtable Database Seeding Script
# ==================================
# This script seeds the PyAirtable PostgreSQL database with realistic test data
# 
# Usage: ./seed-database.sh

echo "🚀 PyAirtable Database Seeding"
echo "=============================="

# Check if Docker is running and postgres container exists
if ! docker ps | grep -q pyairtable-compose-postgres-1; then
    echo "❌ Error: PostgreSQL container not found or not running"
    echo "   Please start the Docker services first with: docker-compose up -d"
    exit 1
fi

echo "🐳 Running database seeding script in Docker container..."
echo "   This will populate the database with realistic test data:"
echo "   • 21 users with different roles"
echo "   • 7 tenants/organizations"
echo "   • 24 workspaces"
echo "   • 34 workflows with 321 runs"
echo "   • 500 analytics events and 200 metrics"
echo "   • API keys and workspace members"
echo ""

# Run the seeding script
docker run --rm --network pyairtable-compose_pyairtable-network \
    -v "$(pwd)":/app -w /app python:3.11-slim \
    bash -c "pip install -q psycopg2-binary bcrypt && python seed_database.py"

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "🎉 Database seeding completed successfully!"
    echo "📊 Run './check-status.sh' to verify the data"
else
    echo ""
    echo "❌ Database seeding failed with exit code: $exit_code"
fi

exit $exit_code