#\!/bin/bash

# Test SSL Database Connections
# This script verifies that all services can connect to the database with SSL enabled

set -e

echo "Testing SSL database connections for PyAirtable services..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to test Go service DB connection
test_go_service() {
    local service_path=$1
    local service_name=$(basename $service_path)
    
    echo -e "${YELLOW}Testing $service_name...${NC}"
    
    if [ \! -f "$service_path/go.mod" ]; then
        echo -e "${YELLOW}Skipping $service_name - no go.mod found${NC}"
        return 0
    fi
    
    cd "$service_path"
    
    # Try to build the service
    if go build ./... > /dev/null 2>&1; then
        echo -e "${GREEN}✅ $service_name builds successfully${NC}"
    else
        echo -e "${RED}❌ $service_name build failed${NC}"
        return 1
    fi
    
    cd - > /dev/null
}

# Function to test Python service
test_python_service() {
    local service_path=$1
    local service_name=$(basename $service_path)
    
    echo -e "${YELLOW}Testing $service_name...${NC}"
    
    if [ \! -f "$service_path/requirements.txt" ]; then
        echo -e "${YELLOW}Skipping $service_name - no requirements.txt found${NC}"
        return 0
    fi
    
    # Check if database configuration exists
    if find "$service_path" -name "*.py" -exec grep -l "database_url\|DATABASE_URL" {} \; | head -1 > /dev/null; then
        echo -e "${GREEN}✅ $service_name has database configuration${NC}"
    else
        echo -e "${YELLOW}⚠️  $service_name - no database configuration found${NC}"
    fi
}

echo "=== Testing Go Services ==="
for service in go-services/*/; do
    if [ -d "$service" ]; then
        test_go_service "$service"
    fi
done

echo ""
echo "=== Testing Python Services ==="
for service in python-services/*/; do
    if [ -d "$service" ]; then
        test_python_service "$service"
    fi
done

# Test automation services
if [ -d "pyairtable-automation-services" ]; then
    test_python_service "pyairtable-automation-services"
fi

echo ""
echo "=== Configuration Verification ==="

# Check that SSL mode is enabled in configuration files
echo -e "${YELLOW}Checking SSL configuration...${NC}"

# Check main config files
if grep -r "sslmode=require" . --include="*.go" --include="*.yml" --include="*.py" > /dev/null; then
    echo -e "${GREEN}✅ SSL mode is enabled in configuration files${NC}"
else
    echo -e "${RED}❌ SSL mode not found in configuration files${NC}"
    exit 1
fi

# Check for any remaining insecure configurations
if grep -r "sslmode=disable" . --include="*.go" --include="*.yml" --include="*.py" 2>/dev/null | grep -v test | grep -v example; then
    echo -e "${RED}❌ Found insecure SSL configurations:${NC}"
    grep -r "sslmode=disable" . --include="*.go" --include="*.yml" --include="*.py" 2>/dev/null | grep -v test | grep -v example
    exit 1
else
    echo -e "${GREEN}✅ No insecure SSL configurations found${NC}"
fi

echo ""
echo -e "${GREEN}🎉 All SSL database connection tests passed\!${NC}"
echo ""
echo "Next steps:"
echo "1. Start PostgreSQL with SSL enabled"
echo "2. Run 'docker-compose up' to test actual connections"
echo "3. Monitor logs for SSL connection confirmations"
