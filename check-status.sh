#!/bin/bash

# PyAirtable Database Status Checker
# ==================================
# This script checks the current state of the database and shows a "Reality Score"
# 
# Usage: ./check-status.sh

echo "🔍 PyAirtable Database Status Check"
echo "=================================="

# Check if Docker is running and postgres container exists
if ! docker ps | grep -q pyairtable-compose-postgres-1; then
    echo "❌ Error: PostgreSQL container not found or not running"
    echo "   Please start the Docker services first with: docker-compose up -d"
    exit 1
fi

# Run the status checker
docker run --rm --network pyairtable-compose_pyairtable-network \
    -v "$(pwd)":/app -w /app python:3.11-slim \
    bash -c "pip install -q psycopg2-binary && python check_database_status.py"

exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo ""
    echo "❌ Status check failed with exit code: $exit_code"
fi

exit $exit_code