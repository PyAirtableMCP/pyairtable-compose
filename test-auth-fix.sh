#!/bin/bash

echo "🔥 Testing PyAirtable Authentication Fix"
echo "======================================="

# Clean up any existing containers
echo "📦 Cleaning up existing containers..."
docker-compose -f docker-compose.auth-test.yml down --volumes

# Build and start the services
echo "🚀 Starting test services..."
docker-compose -f docker-compose.auth-test.yml up -d --build

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check if services are healthy
echo "🔍 Checking service health..."
for i in {1..30}; do
    if curl -f http://localhost:8005/health > /dev/null 2>&1; then
        echo "✅ Auth service is ready!"
        break
    fi
    echo "   Attempt $i/30: Auth service not ready yet..."
    sleep 2
done

# Run the tests
echo "🧪 Running authentication tests..."
python3 test_auth_endpoints.py

TEST_RESULT=$?

# Show logs if tests failed
if [ $TEST_RESULT -ne 0 ]; then
    echo "❌ Tests failed! Showing auth service logs:"
    docker-compose -f docker-compose.auth-test.yml logs auth-service
fi

# Clean up
echo "🧹 Cleaning up test environment..."
docker-compose -f docker-compose.auth-test.yml down --volumes

if [ $TEST_RESULT -eq 0 ]; then
    echo "🎉 All authentication tests passed!"
else
    echo "❌ Some tests failed!"
fi

exit $TEST_RESULT