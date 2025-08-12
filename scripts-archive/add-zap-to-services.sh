#!/bin/bash

# Add zap dependency to all Go services

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="/Users/kg/IdeaProjects/pyairtable-compose"
GO_SERVICES_DIR="$PROJECT_ROOT/go-services"

# Go services list
GO_SERVICES=(
    "api-gateway"
    "auth-service"
    "user-service"
    "tenant-service"
    "workspace-service"
    "permission-service"
    "webhook-service"
    "notification-service"
    "file-service"
    "web-bff"
    "mobile-bff"
)

echo -e "${BLUE}Adding zap dependency to all Go services...${NC}"

for service in "${GO_SERVICES[@]}"; do
    echo -e "${BLUE}Processing $service...${NC}"
    cd "$GO_SERVICES_DIR/$service"
    go get go.uber.org/zap@v1.25.0
    go mod tidy
done

echo -e "${GREEN}✅ Dependencies updated!${NC}"