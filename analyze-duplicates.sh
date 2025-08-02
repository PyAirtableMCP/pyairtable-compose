#!/bin/bash

# Script to analyze potential duplicate functionality across services

echo "=== ANALYZING DUPLICATE FUNCTIONALITY ==="
echo

# Check for duplicate service implementations
echo "1. Checking for duplicate service implementations..."
echo

# API Gateway duplicates
echo "API Gateway implementations:"
find . -name "main.go" -o -name "main.py" -o -name "app.py" | xargs grep -l "api.gateway\|api-gateway\|API Gateway" 2>/dev/null | grep -v node_modules | head -10

echo
echo "Auth Service implementations:"
find . -name "*.go" -o -name "*.py" | xargs grep -l "auth.*service\|jwt.*token\|authentication" 2>/dev/null | grep -E "(auth|jwt)" | grep -v node_modules | head -10

echo
echo "Airtable Gateway implementations:"
find . -name "*.go" -o -name "*.py" | xargs grep -l "airtable.*gateway\|pyairtable" 2>/dev/null | grep -v node_modules | head -10

echo
echo "LLM/AI Service implementations:"
find . -name "*.go" -o -name "*.py" | xargs grep -l "llm.*orchestrator\|gemini\|openai" 2>/dev/null | grep -v node_modules | head -10

echo
echo "2. Checking for configuration duplicates..."
echo

echo "Docker Compose files:"
find . -name "docker-compose*.yml" -type f | grep -v node_modules

echo
echo "Kubernetes manifests:"
find . -path "*/k8s/*" -name "*.yaml" -o -name "*.yml" | grep -v helm | head -20

echo
echo "3. Checking for documentation duplicates..."
echo

echo "Architecture documents:"
find . -name "*ARCHITECT*.md" -o -name "*MIGRATION*.md" -o -name "*PLAN*.md" | grep -v node_modules

echo
echo "4. Service directories structure:"
echo

echo "Go services:"
ls -la go-services/ 2>/dev/null || echo "No go-services directory"

echo
echo "Python services:"
ls -la python-services/ 2>/dev/null || echo "No python-services directory"

echo
echo "5. Checking for router/proxy duplicates:"
find . -name "*.go" -o -name "*.py" | xargs grep -l "proxy\|route.*service\|service.*route" 2>/dev/null | grep -v node_modules | head -10