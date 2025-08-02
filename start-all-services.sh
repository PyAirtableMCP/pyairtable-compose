#!/bin/bash

# Start all 22 microservices

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Starting PyAirtable Microservices${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${YELLOW}Warning: .env file not found. Creating from example...${NC}"
    if [ -f .env.example ]; then
        cp .env.example .env
        echo -e "${GREEN}Created .env file. Please update it with your credentials.${NC}"
        echo -e "${RED}Stopping. Please update .env file and run again.${NC}"
        exit 1
    else
        echo -e "${RED}Error: .env.example not found. Cannot proceed.${NC}"
        exit 1
    fi
fi

# Check required environment variables
required_vars=("AIRTABLE_TOKEN" "GEMINI_API_KEY" "POSTGRES_PASSWORD" "REDIS_PASSWORD" "JWT_SECRET")
missing_vars=()

for var in "${required_vars[@]}"; do
    if ! grep -q "^$var=" .env || grep -q "^$var=\s*$" .env || grep -q "^$var=changeme" .env; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo -e "${RED}Error: Missing or invalid environment variables:${NC}"
    for var in "${missing_vars[@]}"; do
        echo -e "  - $var"
    done
    echo -e "\n${YELLOW}Please update your .env file with valid values.${NC}"
    exit 1
fi

# Start services
echo -e "${BLUE}Starting infrastructure services...${NC}"
docker-compose -f docker-compose.all-services.yml up -d postgres redis

echo -e "\n${YELLOW}Waiting for infrastructure to be ready...${NC}"
sleep 10

echo -e "\n${BLUE}Starting all microservices...${NC}"
docker-compose -f docker-compose.all-services.yml up -d --build

echo -e "\n${YELLOW}Waiting for services to start...${NC}"
sleep 20

echo -e "\n${BLUE}Checking service health...${NC}"
./test-all-services.sh

echo -e "\n${GREEN}=====================================${NC}"
echo -e "${GREEN}All services started!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo "Service URLs:"
echo "  API Gateway:      http://localhost:8080"
echo "  Web BFF:          http://localhost:8089"
echo "  Mobile BFF:       http://localhost:8090"
echo "  MCP Server:       http://localhost:8092"
echo "  Chat Service:     http://localhost:8098"
echo ""
echo "Infrastructure:"
echo "  PostgreSQL:       localhost:5432"
echo "  Redis:            localhost:6379"
echo ""
echo "Monitoring:"
echo "  docker-compose -f docker-compose.all-services.yml logs -f [service-name]"
echo ""
echo "Stop all services:"
echo "  docker-compose -f docker-compose.all-services.yml down"