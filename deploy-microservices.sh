#!/bin/bash

# PyAirtable Microservices Deployment Script
# This script deploys all microservices with proper orchestration

set -e

echo "🚀 PyAirtable Microservices Deployment"
echo "======================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if service is healthy
check_service_health() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/health"}
    
    echo -n "Checking $service_name health..."
    
    for i in {1..30}; do
        if curl -s -f "http://localhost:$port$endpoint" > /dev/null 2>&1; then
            echo -e " ${GREEN}✓${NC}"
            return 0
        fi
        sleep 2
    done
    
    echo -e " ${RED}✗${NC}"
    return 1
}

# Function to check gRPC service health
check_grpc_health() {
    local service_name=$1
    local port=$2
    
    echo -n "Checking $service_name gRPC health..."
    
    for i in {1..30}; do
        if grpcurl -plaintext localhost:$port list > /dev/null 2>&1; then
            echo -e " ${GREEN}✓${NC}"
            return 0
        fi
        sleep 2
    done
    
    echo -e " ${RED}✗${NC}"
    return 1
}

# Parse command line arguments
ENVIRONMENT=${1:-development}
ACTION=${2:-deploy}

echo "Environment: $ENVIRONMENT"
echo "Action: $ACTION"
echo ""

case $ACTION in
    deploy)
        echo "📦 Starting deployment..."
        echo ""
        
        # Step 1: Infrastructure
        echo "1️⃣ Infrastructure Services"
        echo "------------------------"
        cd pyairtable-infrastructure
        
        if [ ! -f "docker-compose.infrastructure.yml" ]; then
            echo -e "${RED}Infrastructure config not found!${NC}"
            exit 1
        fi
        
        echo "Starting PostgreSQL, Redis, and monitoring..."
        docker-compose -f docker-compose.infrastructure.yml up -d postgres redis
        sleep 5
        
        check_service_health "PostgreSQL" 5432 "/"
        check_service_health "Redis" 6379 "/"
        
        echo ""
        
        # Step 2: Core Services (gRPC)
        echo "2️⃣ Core gRPC Services"
        echo "-------------------"
        
        # Auth Service
        echo "Starting Auth Service..."
        cd ../pyairtable-auth-service-go
        docker-compose up -d --build
        check_grpc_health "Auth Service" 50051
        
        # User Service
        echo "Starting User Service..."
        cd ../pyairtable-user-service-go
        docker-compose up -d --build
        check_grpc_health "User Service" 50052
        
        # Workspace Service
        echo "Starting Workspace Service..."
        cd ../pyairtable-workspace-service-go
        docker-compose up -d --build
        check_grpc_health "Workspace Service" 50053
        
        # Table Service
        echo "Starting Table Service..."
        cd ../pyairtable-table-service-go
        docker-compose up -d --build
        check_grpc_health "Table Service" 50054
        
        # Data Service
        echo "Starting Data Service..."
        cd ../pyairtable-data-service-go
        docker-compose up -d --build
        check_grpc_health "Data Service" 50055
        
        echo ""
        
        # Step 3: API Gateway
        echo "3️⃣ API Gateway"
        echo "------------"
        cd ../pyairtable-api-gateway-go
        
        echo "Starting API Gateway..."
        docker-compose up -d --build
        sleep 5
        check_service_health "API Gateway" 8080 "/health"
        
        echo ""
        
        # Step 4: Monitoring Stack
        echo "4️⃣ Monitoring Stack"
        echo "-----------------"
        cd ../pyairtable-infrastructure
        
        echo "Starting Prometheus, Grafana, Jaeger..."
        docker-compose -f docker-compose.infrastructure.yml up -d prometheus grafana jaeger
        
        check_service_health "Prometheus" 9090 "/-/healthy"
        check_service_health "Grafana" 3001 "/api/health"
        check_service_health "Jaeger" 16686 "/"
        
        echo ""
        
        # Step 5: Status Summary
        echo "📊 Deployment Status"
        echo "-----------------"
        
        echo -e "${GREEN}✅ Infrastructure:${NC}"
        echo "   - PostgreSQL: Running on port 5432"
        echo "   - Redis: Running on port 6379"
        
        echo -e "${GREEN}✅ Core Services:${NC}"
        echo "   - Auth Service: gRPC on port 50051"
        echo "   - User Service: gRPC on port 50052"
        echo "   - Workspace Service: gRPC on port 50053"
        echo "   - Table Service: gRPC on port 50054"
        echo "   - Data Service: gRPC on port 50055"
        
        echo -e "${GREEN}✅ API Layer:${NC}"
        echo "   - API Gateway: HTTP on port 8080"
        
        echo -e "${GREEN}✅ Monitoring:${NC}"
        echo "   - Prometheus: http://localhost:9090"
        echo "   - Grafana: http://localhost:3001"
        echo "   - Jaeger: http://localhost:16686"
        
        echo ""
        echo -e "${GREEN}🎉 Deployment Complete!${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Access API Gateway: http://localhost:8080"
        echo "2. View metrics: http://localhost:3001 (admin/admin)"
        echo "3. View traces: http://localhost:16686"
        echo "4. Run tests: ./test-microservices.sh"
        ;;
        
    stop)
        echo "🛑 Stopping all services..."
        
        # Stop services in reverse order
        cd pyairtable-api-gateway-go && docker-compose down
        cd ../pyairtable-data-service-go && docker-compose down
        cd ../pyairtable-table-service-go && docker-compose down
        cd ../pyairtable-workspace-service-go && docker-compose down
        cd ../pyairtable-user-service-go && docker-compose down
        cd ../pyairtable-auth-service-go && docker-compose down
        cd ../pyairtable-infrastructure && docker-compose -f docker-compose.infrastructure.yml down
        
        echo -e "${GREEN}✅ All services stopped${NC}"
        ;;
        
    restart)
        $0 $ENVIRONMENT stop
        sleep 5
        $0 $ENVIRONMENT deploy
        ;;
        
    status)
        echo "📊 Service Status"
        echo "---------------"
        
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "pyairtable|postgres|redis" || true
        ;;
        
    logs)
        SERVICE=${3:-all}
        
        if [ "$SERVICE" = "all" ]; then
            docker-compose logs -f
        else
            docker logs -f pyairtable-$SERVICE
        fi
        ;;
        
    test)
        echo "🧪 Running integration tests..."
        ./test-microservices.sh
        ;;
        
    *)
        echo "Usage: $0 <environment> <action> [options]"
        echo ""
        echo "Environments:"
        echo "  development  - Local development environment"
        echo "  staging      - Staging environment"
        echo "  production   - Production environment"
        echo ""
        echo "Actions:"
        echo "  deploy       - Deploy all services"
        echo "  stop         - Stop all services"
        echo "  restart      - Restart all services"
        echo "  status       - Show service status"
        echo "  logs [service] - Show logs (all or specific service)"
        echo "  test         - Run integration tests"
        echo ""
        echo "Examples:"
        echo "  $0 development deploy"
        echo "  $0 development logs auth-service"
        echo "  $0 staging restart"
        exit 1
        ;;
esac

cd ..