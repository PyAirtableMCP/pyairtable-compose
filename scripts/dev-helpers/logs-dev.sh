#!/bin/bash

echo "📋 Following logs for all PyAirtable services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 Press Ctrl+C to stop following logs"
echo ""

# Follow logs for all services with color output
docker-compose logs -f --tail=100