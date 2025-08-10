#!/bin/bash

# PyAirtable Repository Cleanup Script
# Date: 2025-08-10

echo "=== PyAirtable Repository Cleanup ==="
echo "Starting cleanup from 6.4GB repository..."

# Phase 1: Remove obvious duplicates and caches
echo "Phase 1: Removing caches and build artifacts..."
find . -name "node_modules" -type d -prune -exec rm -rf {} + 2>/dev/null
find . -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null
find . -name ".pytest_cache" -type d -prune -exec rm -rf {} + 2>/dev/null
find . -name ".next" -type d -prune -exec rm -rf {} + 2>/dev/null
find . -name "dist" -type d -prune -exec rm -rf {} + 2>/dev/null
find . -name "build" -type d -prune -exec rm -rf {} + 2>/dev/null
find . -name "*.pyc" -type f -delete 2>/dev/null
find . -name ".DS_Store" -type f -delete 2>/dev/null

# Phase 2: Consolidate duplicate services
echo "Phase 2: Consolidating services..."
# Remove duplicate automation service
rm -rf pyairtable-automation-services

# Remove frontend optimization (keep main frontend-services)
rm -rf frontend-optimization

# Remove old frontend (keep frontend-services)
rm -rf frontend

# Phase 3: Clean up test data
echo "Phase 3: Removing test data..."
find . -name "*.test.js" -o -name "*.test.ts" -o -name "*.spec.js" -o -name "*.spec.ts" | head -100 | xargs rm -f
rm -rf tests/fixtures/large_data
rm -rf tests/e2e/screenshots
rm -rf tests/e2e/videos

# Phase 4: Remove Docker artifacts
echo "Phase 4: Cleaning Docker artifacts..."
docker system prune -f 2>/dev/null

echo "=== Cleanup Complete ==="
du -sh .
echo "Documentation files moved to: docs-to-migrate/"
echo "Next step: Push these docs to pyairtable-docs repository"