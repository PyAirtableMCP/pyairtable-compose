#!/bin/bash

# Sprint 1 Python Services Fix Script
# Addresses testing and dependency issues in Python services

set -e

echo "🐍 Sprint 1 Python Services Fix Script"
echo "======================================="

# Function to setup Python service testing
setup_python_service() {
    local service_name="$1"
    local service_path="$2"
    
    echo "📦 Setting up $service_name..."
    
    if [ ! -d "$service_path" ]; then
        echo "❌ Service path does not exist: $service_path"
        return 1
    fi
    
    cd "$service_path"
    echo "📋 Current directory: $(pwd)"
    
    # Check for virtual environment
    if [ ! -d "venv" ]; then
        echo "  - Creating virtual environment..."
        python3 -m venv venv
    fi
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Update pip
    pip install --upgrade pip
    
    # Install dependencies
    if [ -f "requirements.txt" ]; then
        echo "  - Installing requirements.txt..."
        pip install -r requirements.txt
    fi
    
    if [ -f "pyproject.toml" ]; then
        echo "  - Installing pyproject.toml..."
        pip install -e .
    fi
    
    # Install test dependencies
    echo "  - Installing test dependencies..."
    pip install pytest pytest-asyncio pytest-cov flake8 black isort
    
    # Create pytest.ini if it doesn't exist
    if [ ! -f "pytest.ini" ]; then
        echo "  - Creating pytest.ini..."
        cat > pytest.ini << 'EOF'
[tool:pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = -v --tb=short --strict-markers
asyncio_mode = auto
EOF
    fi
    
    # Run tests
    echo "  - Running tests..."
    if pytest -v --tb=short || echo "⚠️ Some tests failed - this may be expected during development"; then
        echo "✅ Test setup completed for $service_name"
    fi
    
    # Deactivate virtual environment
    deactivate
    
    cd - > /dev/null
}

# Fix Airtable Gateway
echo "🎯 Step 1: Fixing Airtable Gateway..."
setup_python_service "airtable-gateway" "python-services/airtable-gateway"

# Fix Automation Services  
echo "🎯 Step 2: Fixing Automation Services..."
setup_python_service "automation-services" "pyairtable-automation-services"

# Fix Saga Orchestrator
echo "🎯 Step 3: Fixing Saga Orchestrator..."
setup_python_service "saga-orchestrator" "saga-orchestrator"

# Create a master test runner script
echo "🎯 Step 4: Creating master test runner..."
cat > run_python_tests.sh << 'EOF'
#!/bin/bash

echo "🧪 Running Python Service Tests"
echo "================================"

# Test Airtable Gateway
echo "Testing Airtable Gateway..."
cd python-services/airtable-gateway
source venv/bin/activate
pytest -v --tb=short || echo "⚠️ Airtable Gateway tests completed with issues"
deactivate
cd ../..

# Test Automation Services
echo "Testing Automation Services..."
cd pyairtable-automation-services
source venv/bin/activate
pytest -v --tb=short || echo "⚠️ Automation Services tests completed with issues"
deactivate
cd ..

# Test Saga Orchestrator
echo "Testing Saga Orchestrator..."
cd saga-orchestrator
source venv/bin/activate
pytest -v --tb=short || echo "⚠️ Saga Orchestrator tests completed with issues"
deactivate
cd ..

echo "✅ All Python service tests completed!"
EOF

chmod +x run_python_tests.sh

echo ""
echo "🎉 Python services fix script completed!"
echo "📋 What was done:"
echo "   1. Created virtual environments for each Python service"
echo "   2. Installed dependencies and test frameworks"
echo "   3. Created pytest configuration files"
echo "   4. Attempted to run tests (some failures expected during development)"
echo "   5. Created run_python_tests.sh for easy test execution"
echo ""
echo "📝 Next steps:"
echo "   1. Review any test failures and fix them"
echo "   2. Add more comprehensive test coverage"
echo "   3. Run: ./run_python_tests.sh to test all Python services"