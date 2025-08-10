#!/bin/bash

# Test script for API Gateway authentication flow
# This script validates the JWT middleware implementation

set -e

API_GATEWAY_URL="${API_GATEWAY_URL:-http://localhost:7000}"
JWT_SECRET="${JWT_SECRET:-test_secret_for_development_only}"

echo "🚀 Testing PyAirtable API Gateway Authentication"
echo "================================================"
echo "Gateway URL: $API_GATEWAY_URL"
echo

# Function to generate a test JWT token
generate_test_token() {
    local user_id="$1"
    local email="$2"
    local role="${3:-user}"
    local exp_hours="${4:-24}"
    
    # Use a simple Python script to generate JWT for testing
    python3 -c "
import jwt
import json
from datetime import datetime, timedelta

claims = {
    'user_id': '$user_id',
    'email': '$email', 
    'role': '$role',
    'tenant_id': 'test-tenant',
    'exp': datetime.utcnow() + timedelta(hours=$exp_hours),
    'iat': datetime.utcnow()
}

token = jwt.encode(claims, '$JWT_SECRET', algorithm='HS256')
print(token)
" 2>/dev/null || echo "ERROR: Python3 with PyJWT required for token generation"
}

# Test 1: Health check (public route)
echo "📋 Test 1: Health Check (Public Route)"
response=$(curl -s -w "\n%{http_code}" "$API_GATEWAY_URL/health" || echo -e "\nERROR")
http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | head -n -1)

if [ "$http_code" = "200" ]; then
    echo "✅ Health check passed"
    echo "   Response: $response_body"
else
    echo "❌ Health check failed (HTTP $http_code)"
    echo "   Response: $response_body"
fi
echo

# Test 2: Protected route without token
echo "📋 Test 2: Protected Route Without Token"
response=$(curl -s -w "\n%{http_code}" "$API_GATEWAY_URL/api/v1/users/me" || echo -e "\nERROR")
http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | head -n -1)

if [ "$http_code" = "401" ]; then
    echo "✅ Unauthorized access correctly rejected"
    echo "   Response: $response_body"
else
    echo "❌ Should have returned 401, got HTTP $http_code"
    echo "   Response: $response_body"
fi
echo

# Test 3: Protected route with invalid token
echo "📋 Test 3: Protected Route With Invalid Token"
response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer invalid.token.here" \
    "$API_GATEWAY_URL/api/v1/users/me" || echo -e "\nERROR")
http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | head -n -1)

if [ "$http_code" = "401" ]; then
    echo "✅ Invalid token correctly rejected"
    echo "   Response: $response_body"
else
    echo "❌ Should have returned 401, got HTTP $http_code"
    echo "   Response: $response_body"
fi
echo

# Test 4: Generate and test valid token (if Python available)
echo "📋 Test 4: Protected Route With Valid Token"
if command -v python3 >/dev/null 2>&1 && python3 -c "import jwt" 2>/dev/null; then
    echo "🔑 Generating test JWT token..."
    test_token=$(generate_test_token "test-user-123" "test@example.com" "user")
    
    if [ -n "$test_token" ] && [ "$test_token" != "ERROR: Python3 with PyJWT required for token generation" ]; then
        echo "   Token generated: ${test_token:0:50}..."
        
        response=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer $test_token" \
            "$API_GATEWAY_URL/api/v1/users/me" || echo -e "\nERROR")
        http_code=$(echo "$response" | tail -n1)
        response_body=$(echo "$response" | head -n -1)
        
        if [ "$http_code" = "200" ] || [ "$http_code" = "404" ] || [ "$http_code" = "502" ]; then
            echo "✅ Valid token accepted (HTTP $http_code)"
            echo "   Note: HTTP $http_code may indicate backend service not running"
            echo "   Response: $response_body"
        else
            echo "❌ Valid token rejected (HTTP $http_code)" 
            echo "   Response: $response_body"
        fi
    else
        echo "⚠️  Could not generate test token"
    fi
else
    echo "⚠️  Skipping valid token test - requires python3 with PyJWT"
    echo "   Install with: pip3 install PyJWT"
fi
echo

# Test 5: Admin route with user role
echo "📋 Test 5: Admin Route Access Control"
if command -v python3 >/dev/null 2>&1 && python3 -c "import jwt" 2>/dev/null; then
    echo "🔑 Generating user token for admin route..."
    user_token=$(generate_test_token "test-user-123" "test@example.com" "user")
    
    if [ -n "$user_token" ] && [ "$user_token" != "ERROR"* ]; then
        response=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer $user_token" \
            "$API_GATEWAY_URL/api/v1/admin/services" || echo -e "\nERROR")
        http_code=$(echo "$response" | tail -n1)
        response_body=$(echo "$response" | head -n -1)
        
        if [ "$http_code" = "403" ]; then
            echo "✅ User role correctly denied admin access"
            echo "   Response: $response_body"
        else
            echo "❌ Should have returned 403, got HTTP $http_code"
            echo "   Response: $response_body"
        fi
    fi
    
    echo "🔑 Generating admin token..."
    admin_token=$(generate_test_token "test-admin-456" "admin@example.com" "admin")
    
    if [ -n "$admin_token" ] && [ "$admin_token" != "ERROR"* ]; then
        response=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer $admin_token" \
            "$API_GATEWAY_URL/api/v1/admin/services" || echo -e "\nERROR")
        http_code=$(echo "$response" | tail -n1)
        response_body=$(echo "$response" | head -n -1)
        
        if [ "$http_code" = "200" ]; then
            echo "✅ Admin role granted access"
            echo "   Response: $response_body"
        elif [ "$http_code" = "502" ] || [ "$http_code" = "404" ]; then
            echo "✅ Admin role authentication passed (HTTP $http_code)"
            echo "   Note: HTTP $http_code indicates backend service issue"
        else
            echo "❌ Admin access failed (HTTP $http_code)"
            echo "   Response: $response_body"
        fi
    fi
else
    echo "⚠️  Skipping role-based test - requires python3 with PyJWT"
fi
echo

# Test 6: Rate limiting (if enabled)
echo "📋 Test 6: Rate Limiting"
echo "🚀 Testing rate limiting (making 10 rapid requests to auth endpoint)..."

success_count=0
rate_limited_count=0

for i in {1..10}; do
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"email":"test@example.com","password":"test"}' \
        "$API_GATEWAY_URL/api/v1/auth/login" || echo -e "\nERROR")
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "429" ]; then
        rate_limited_count=$((rate_limited_count + 1))
    else
        success_count=$((success_count + 1))
    fi
    
    # Brief pause between requests
    sleep 0.1
done

if [ "$rate_limited_count" -gt 0 ]; then
    echo "✅ Rate limiting is active"
    echo "   Successful requests: $success_count"
    echo "   Rate limited requests: $rate_limited_count"
else
    echo "⚠️  Rate limiting not triggered or disabled"
    echo "   Note: This may indicate Redis is not running or rate limiting is disabled"
fi

echo
echo "🏁 Authentication Flow Tests Complete"
echo "========================================="
echo
echo "💡 Next Steps:"
echo "1. Ensure JWT_SECRET environment variable is set"
echo "2. Start Redis for rate limiting: redis-server"
echo "3. Start Auth Service for complete authentication flow"
echo "4. Test with frontend application on localhost:5173"
echo
echo "🔧 Troubleshooting:"
echo "- Check logs: docker logs <container-name>"
echo "- Verify environment: cat .env"
echo "- Test connectivity: curl $API_GATEWAY_URL/health"