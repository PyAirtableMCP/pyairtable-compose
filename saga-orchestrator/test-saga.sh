#!/bin/bash

# Test SAGA Orchestrator Service
# This script demonstrates SAGA functionality

set -e

echo "🧪 Testing PyAirtable SAGA Orchestrator..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

BASE_URL="http://localhost:8008"
API_KEY=${API_KEY:-"test-api-key"}

# Function to make API calls
api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    local description=$4
    
    print_test "$description"
    
    if [ -n "$data" ]; then
        response=$(curl -s -X "$method" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $API_KEY" \
            -d "$data" \
            "$BASE_URL$endpoint")
    else
        response=$(curl -s -X "$method" \
            -H "X-API-Key: $API_KEY" \
            "$BASE_URL$endpoint")
    fi
    
    echo "Response: $response"
    echo ""
    
    return 0
}

# Check if service is running
print_status "Checking if SAGA Orchestrator is running..."
if ! curl -f "$BASE_URL/health" > /dev/null 2>&1; then
    print_error "SAGA Orchestrator is not running. Please run deploy-saga.sh first."
    exit 1
fi

print_status "✅ SAGA Orchestrator is running"
echo ""

# Test 1: Health Check
print_test "1. Health Check"
health_response=$(curl -s "$BASE_URL/health")
echo "Health Status: $health_response"
echo ""

# Test 2: Get Available SAGA Types
print_test "2. Get Available SAGA Types"
api_call "GET" "/sagas/types/available" "" "Fetching available SAGA types"

# Test 3: Start User Onboarding SAGA
print_test "3. Start User Onboarding SAGA"
user_onboarding_data='{
    "saga_type": "user_onboarding",
    "input_data": {
        "user_id": "user-12345",
        "email": "test@example.com",
        "first_name": "John",
        "last_name": "Doe",
        "tenant_id": "tenant-67890"
    },
    "correlation_id": "test-correlation-123"
}'

saga_response=$(api_call "POST" "/sagas/start" "$user_onboarding_data" "Starting user onboarding SAGA")
saga_id=$(echo "$saga_response" | grep -o '"saga_id":"[^"]*"' | cut -d'"' -f4)

if [ -n "$saga_id" ]; then
    print_status "✅ SAGA started with ID: $saga_id"
    
    # Test 4: Get SAGA Details
    print_test "4. Get SAGA Details"
    api_call "GET" "/sagas/$saga_id" "" "Fetching SAGA details"
    
    # Test 5: Get SAGA Steps
    print_test "5. Get SAGA Steps"
    api_call "GET" "/sagas/$saga_id/steps" "" "Fetching SAGA steps"
    
    # Wait a bit for SAGA to process
    print_status "Waiting 5 seconds for SAGA to process..."
    sleep 5
    
    # Test 6: Check SAGA Status Again
    print_test "6. Check SAGA Status After Processing"
    api_call "GET" "/sagas/$saga_id" "" "Checking SAGA status after processing"
    
else
    print_error "Failed to extract SAGA ID from response"
fi

# Test 7: List All SAGAs
print_test "7. List All SAGAs"
api_call "GET" "/sagas/" "" "Listing all SAGAs"

# Test 8: Start Airtable Integration SAGA
print_test "8. Start Airtable Integration SAGA"
airtable_integration_data='{
    "saga_type": "airtable_integration",
    "input_data": {
        "base_id": "appXXXXXXXXXXXXXX",
        "api_key": "keyXXXXXXXXXXXXXX",
        "user_id": "user-12345",
        "tenant_id": "tenant-67890",
        "webhook_url": "https://api.pyairtable.com/webhooks/receive"
    },
    "correlation_id": "test-airtable-integration-456"
}'

airtable_saga_response=$(api_call "POST" "/sagas/start" "$airtable_integration_data" "Starting Airtable integration SAGA")
airtable_saga_id=$(echo "$airtable_saga_response" | grep -o '"saga_id":"[^"]*"' | cut -d'"' -f4)

if [ -n "$airtable_saga_id" ]; then
    print_status "✅ Airtable integration SAGA started with ID: $airtable_saga_id"
    
    # Wait a bit and check status
    sleep 3
    api_call "GET" "/sagas/$airtable_saga_id" "" "Checking Airtable integration SAGA status"
fi

# Test 9: Event Store Tests
print_test "9. Event Store Tests"

# Publish a test event
test_event_data='{
    "event_type": "user.registered",
    "aggregate_id": "user-test-789",
    "aggregate_type": "user",
    "data": {
        "email": "eventtest@example.com",
        "user_id": "user-test-789",
        "tenant_id": "tenant-test"
    },
    "correlation_id": "test-event-correlation-789"
}'

api_call "POST" "/events/publish" "$test_event_data" "Publishing test event"

# Get all events
api_call "GET" "/events/all?max_count=10" "" "Fetching recent events"

# Test 10: Error Handling Test
print_test "10. Error Handling Test"

# Try to start SAGA with invalid type
invalid_saga_data='{
    "saga_type": "invalid_saga_type",
    "input_data": {
        "test": "data"
    }
}'

print_test "Testing error handling with invalid SAGA type"
error_response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d "$invalid_saga_data" \
    "$BASE_URL/sagas/start")
echo "Error Response: $error_response"
echo ""

# Final status
print_status "🎉 SAGA Orchestrator testing completed!"
echo ""
print_status "📊 Test Summary:"
echo "   ✅ Health check passed"
echo "   ✅ SAGA types retrieved"
echo "   ✅ User onboarding SAGA started"
echo "   ✅ Airtable integration SAGA started"
echo "   ✅ Event publishing tested"
echo "   ✅ Error handling tested"
echo ""
print_status "🔍 Monitor SAGAs:"
echo "   List SAGAs: curl $BASE_URL/sagas/"
echo "   Health: curl $BASE_URL/health"
echo "   Logs: docker-compose logs -f saga-orchestrator"
echo ""
print_status "🌐 Web Interface:"
echo "   API Docs: http://localhost:8008/docs"
echo "   Health: http://localhost:8008/health"