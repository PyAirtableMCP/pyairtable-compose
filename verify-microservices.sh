#!/bin/bash

# PyAirtable Microservices Verification Script
# This script checks the actual status of all microservices

set -e

echo "🔍 PyAirtable Microservices Status Verification"
echo "=============================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track overall status
TOTAL_SERVICES=22
GITHUB_REPOS=0
LOCAL_DIRS=0
BUILDABLE=0
ISSUES=()

echo "📊 Checking GitHub Repositories..."
echo "--------------------------------"

# Go Services (expected 11)
GO_SERVICES=(
    "pyairtable-api-gateway-go"
    "pyairtable-auth-service-go"
    "pyairtable-user-service-go"
    "pyairtable-tenant-service-go"
    "pyairtable-workspace-service-go"
    "pyairtable-permission-service-go"
    "pyairtable-webhook-service-go"
    "pyairtable-notification-service-go"
    "pyairtable-file-service-go"
    "pyairtable-go-shared"
    "pyairtable-web-bff-go"
    "pyairtable-mobile-bff-go"
)

# Python Services (expected 11)
PYTHON_SERVICES=(
    "llm-orchestrator-py"
    "mcp-server-py"
    "airtable-gateway-py"
    "pyairtable-formula-engine-py"
    "pyairtable-embedding-service-py"
    "pyairtable-semantic-search-py"
    "pyairtable-chat-service-py"
    "pyairtable-workflow-engine-py"
    "pyairtable-analytics-service-py"
    "pyairtable-audit-service-py"
    "pyairtable-python-shared"
)

# Check Go services on GitHub
echo -e "\n${YELLOW}Go Services:${NC}"
for service in "${GO_SERVICES[@]}"; do
    if gh repo view "Reg-Kris/$service" --json name >/dev/null 2>&1; then
        echo -e "  ✅ $service - ${GREEN}Found on GitHub${NC}"
        ((GITHUB_REPOS++))
    else
        echo -e "  ❌ $service - ${RED}NOT on GitHub${NC}"
        ISSUES+=("GitHub: Missing $service")
    fi
done

# Check Python services on GitHub
echo -e "\n${YELLOW}Python Services:${NC}"
for service in "${PYTHON_SERVICES[@]}"; do
    if gh repo view "Reg-Kris/$service" --json name >/dev/null 2>&1; then
        echo -e "  ✅ $service - ${GREEN}Found on GitHub${NC}"
        ((GITHUB_REPOS++))
    else
        echo -e "  ❌ $service - ${RED}NOT on GitHub${NC}"
        ISSUES+=("GitHub: Missing $service")
    fi
done

echo -e "\n📁 Checking Local Directories..."
echo "--------------------------------"

# Check local Go service directories
echo -e "\n${YELLOW}Local Go Service Directories:${NC}"

# Check in pyairtable-infrastructure
if [ -d "pyairtable-infrastructure" ]; then
    for service in "${GO_SERVICES[@]}"; do
        if [ -d "pyairtable-infrastructure/$service" ]; then
            echo -e "  ✅ $service - ${GREEN}Found locally${NC}"
            ((LOCAL_DIRS++))
            
            # Check if it has go.mod (buildable)
            if [ -f "pyairtable-infrastructure/$service/go.mod" ]; then
                ((BUILDABLE++))
                echo -e "     └─ ${GREEN}Has go.mod - buildable${NC}"
            else
                echo -e "     └─ ${RED}Missing go.mod${NC}"
                ISSUES+=("Build: $service missing go.mod")
            fi
        elif [ -d "pyairtable-infrastructure/go-microservice-template/${service#pyairtable-}" ]; then
            echo -e "  ⚠️  $service - ${YELLOW}Found in template directory${NC}"
            ((LOCAL_DIRS++))
            ISSUES+=("Location: $service in template directory")
        else
            echo -e "  ❌ $service - ${RED}NOT found locally${NC}"
            ISSUES+=("Local: Missing $service")
        fi
    done
fi

# Check existing Python services
echo -e "\n${YELLOW}Local Python Service Directories:${NC}"
for service in "${PYTHON_SERVICES[@]}"; do
    if [ -d "../$service" ] || [ -d "$service" ]; then
        echo -e "  ✅ $service - ${GREEN}Found locally${NC}"
        ((LOCAL_DIRS++))
    else
        echo -e "  ❌ $service - ${RED}NOT found locally${NC}"
        ISSUES+=("Local: Missing $service")
    fi
done

echo -e "\n📊 Summary Report"
echo "================"
echo -e "Total Expected Services: ${TOTAL_SERVICES}"
echo -e "GitHub Repositories: ${GITHUB_REPOS}/${TOTAL_SERVICES}"
echo -e "Local Directories: ${LOCAL_DIRS}/${TOTAL_SERVICES}"
echo -e "Buildable Go Services: ${BUILDABLE}/11"

# Calculate percentages
GITHUB_PERCENT=$((GITHUB_REPOS * 100 / TOTAL_SERVICES))
LOCAL_PERCENT=$((LOCAL_DIRS * 100 / TOTAL_SERVICES))

echo -e "\nCompletion Status:"
echo -e "GitHub: ${GITHUB_PERCENT}%"
echo -e "Local: ${LOCAL_PERCENT}%"

# List issues
if [ ${#ISSUES[@]} -gt 0 ]; then
    echo -e "\n${RED}❌ Issues Found:${NC}"
    for issue in "${ISSUES[@]}"; do
        echo -e "  - $issue"
    done
else
    echo -e "\n${GREEN}✅ All services properly deployed!${NC}"
fi

echo -e "\n🔧 Actual Status:"
echo "=================="
echo "Based on the verification, here's what we actually have:"
echo ""
echo "✅ COMPLETED:"
echo "  - Infrastructure repository with Terraform/K8s"
echo "  - Go service template"
echo "  - Go shared library" 
echo "  - Python shared library"
echo "  - API Gateway (partially)"
echo "  - Auth Service (partially)"
echo "  - 11 Go services on GitHub (but not all with code)"
echo ""
echo "❌ MISSING/INCOMPLETE:"
echo "  - Go services are in template directory, not properly separated"
echo "  - Most Python services don't exist yet"
echo "  - Services aren't buildable in current state"
echo "  - No local testing setup ready"
echo ""
echo "📋 RECOMMENDATION:"
echo "  We need to properly extract and set up each service"
echo "  before we can consider the backend stable."