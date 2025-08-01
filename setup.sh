#!/bin/bash

# PyAirtable Microservices - Local Development Setup
# Automated setup script for internal tool (2 people)

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_DIR="/Users/kg/IdeaProjects/pyairtable-compose"
REQUIRED_SERVICES=("llm-orchestrator-py" "mcp-server-py" "airtable-gateway-py" "pyairtable-common")
FRONTEND_SERVICE="pyairtable-frontend"

echo -e "${BLUE}🚀 PyAirtable Local Development Setup${NC}"
echo -e "${BLUE}====================================${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if directory exists
check_directory() {
    if [ ! -d "$1" ]; then
        print_error "Directory not found: $1"
        echo "Please ensure all microservice repositories are cloned in the correct location."
        exit 1
    fi
}

# Function to create .env file if it doesn't exist
create_env_file() {
    local service_dir=$1
    local env_file="$service_dir/.env"
    
    if [ ! -f "$env_file" ]; then
        print_info "Creating .env file for $(basename $service_dir)..."
        
        # Create basic .env based on service type
        case "$(basename $service_dir)" in
            "llm-orchestrator-py")
                cat > "$env_file" << 'EOF'
# LLM Orchestrator Configuration
GEMINI_API_KEY=your_gemini_api_key_here
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=
MCP_SERVER_HTTP_URL=http://localhost:8001
USE_HTTP_MCP=true
DEFAULT_MODEL=gemini-2.5-flash
MAX_TOKENS=4000
TEMPERATURE=0.1
SESSION_TIMEOUT=3600
THINKING_BUDGET=5
USE_REDIS_SESSIONS=true
LOG_LEVEL=INFO
CORS_ORIGINS=http://localhost:3000,http://localhost:8000
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/pyairtable
API_KEY=internal_api_key_123
EOF
                ;;
            "mcp-server-py")
                cat > "$env_file" << 'EOF'
# MCP Server Configuration
AIRTABLE_GATEWAY_URL=http://localhost:8002
AIRTABLE_GATEWAY_API_KEY=internal_api_key_123
MCP_SERVER_MODE=http
MCP_SERVER_PORT=8001
LOG_LEVEL=INFO
CORS_ORIGINS=http://localhost:3000,http://localhost:8000
API_KEY=internal_api_key_123
EOF
                ;;
            "airtable-gateway-py")
                cat > "$env_file" << 'EOF'
# Airtable Gateway Configuration
AIRTABLE_TOKEN=your_airtable_token_here
API_KEY=internal_api_key_123
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=
LOG_LEVEL=INFO
CORS_ORIGINS=http://localhost:3000,http://localhost:8000
EOF
                ;;
            "pyairtable-frontend")
                cat > "$env_file" << 'EOF'
# Frontend Configuration
# API Gateway endpoint (public - used by browser)
NEXT_PUBLIC_API_URL=http://localhost:8000
NEXT_PUBLIC_API_GATEWAY_URL=http://localhost:8000

# Internal service URLs (server-side only)
LLM_ORCHESTRATOR_URL=http://localhost:8003
MCP_SERVER_URL=http://localhost:8001
AIRTABLE_GATEWAY_URL=http://localhost:8002

# Authentication and security
API_KEY=internal_api_key_123
NEXTAUTH_SECRET=your-secret-key-change-in-production
NEXTAUTH_URL=http://localhost:3000

# Development configuration
NODE_ENV=development
LOG_LEVEL=info

# Feature flags
NEXT_PUBLIC_ENABLE_DEBUG=false
NEXT_PUBLIC_SHOW_COST_TRACKING=true
EOF
                ;;
        esac
        
        print_status "Created $env_file"
    else
        print_info "Using existing .env file for $(basename $service_dir)"
    fi
}

# Function to check Python environment
check_python_env() {
    local service_dir=$1
    
    cd "$service_dir"
    
    # Check if virtual environment exists
    if [ ! -d "venv" ]; then
        print_info "Creating Python virtual environment for $(basename $service_dir)..."
        python3 -m venv venv
        print_status "Virtual environment created"
    fi
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Install dependencies
    if [ -f "requirements.txt" ]; then
        print_info "Installing Python dependencies for $(basename $service_dir)..."
        pip install -r requirements.txt --quiet
        print_status "Dependencies installed"
    fi
    
    deactivate
    cd - > /dev/null
}

# Function to check Node.js environment
check_nodejs_env() {
    local service_dir=$1
    
    cd "$service_dir"
    
    # Check if package.json exists
    if [ ! -f "package.json" ]; then
        print_warning "No package.json found in $(basename $service_dir)"
        return 1
    fi
    
    # Install dependencies based on available package manager
    if command_exists yarn && [ -f "yarn.lock" ]; then
        print_info "Installing Node.js dependencies with Yarn for $(basename $service_dir)..."
        yarn install --silent
        print_status "Yarn dependencies installed"
    elif command_exists npm; then
        print_info "Installing Node.js dependencies with npm for $(basename $service_dir)..."
        npm install --silent
        print_status "npm dependencies installed"
    else
        print_error "Neither npm nor yarn found"
        return 1
    fi
    
    cd - > /dev/null
}

# Function to setup database
setup_database() {
    print_info "Setting up PostgreSQL database..."
    
    # Check if PostgreSQL is running
    if ! pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
        print_warning "PostgreSQL is not running. Please start PostgreSQL:"
        echo "  macOS: brew services start postgresql"
        echo "  Ubuntu: sudo systemctl start postgresql"
        echo "  Windows: Start PostgreSQL service"
        echo ""
        read -p "Press Enter once PostgreSQL is running..."
    fi
    
    # Create database if it doesn't exist
    if ! psql -h localhost -U postgres -lqt | cut -d \| -f 1 | grep -qw pyairtable; then
        print_info "Creating pyairtable database..."
        createdb -h localhost -U postgres pyairtable
        print_status "Database created"
    else
        print_info "Database already exists"
    fi
    
    # Run migrations
    if [ -f "$COMPOSE_DIR/migrations/001_create_session_tables.sql" ]; then
        print_info "Running database migrations..."
        psql -h localhost -U postgres -d pyairtable -f "$COMPOSE_DIR/migrations/001_create_session_tables.sql" > /dev/null 2>&1
        print_status "Migrations completed"
    fi
}

# Function to setup Redis
setup_redis() {
    print_info "Checking Redis setup..."
    
    if ! redis-cli ping >/dev/null 2>&1; then
        print_warning "Redis is not running. Please start Redis:"
        echo "  macOS: brew services start redis"
        echo "  Ubuntu: sudo systemctl start redis"
        echo "  Windows: Start Redis service"
        echo ""
        read -p "Press Enter once Redis is running..."
    else
        print_status "Redis is running"
    fi
}

# Main setup function
main() {
    echo "Starting automated setup for PyAirtable microservices..."
    echo ""
    
    # 1. Check prerequisites
    print_info "Checking prerequisites..."
    
    if ! command_exists python3; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi
    print_status "Python 3 found"
    
    if ! command_exists node; then
        print_error "Node.js is required but not installed"
        print_info "Install Node.js: https://nodejs.org/ or use nvm/brew"
        exit 1
    fi
    print_status "Node.js found ($(node --version))"
    
    if ! command_exists npm; then
        print_error "npm is required but not installed"
        exit 1
    fi
    print_status "npm found ($(npm --version))"
    
    if ! command_exists docker; then
        print_warning "Docker not found - you'll need to run services manually"
    else
        print_status "Docker found"
    fi
    
    if ! command_exists psql; then
        print_error "PostgreSQL client (psql) is required but not installed"
        exit 1
    fi
    print_status "PostgreSQL client found"
    
    if ! command_exists redis-cli; then
        print_error "Redis CLI is required but not installed"
        exit 1
    fi
    print_status "Redis CLI found"
    
    echo ""
    
    # 2. Check service directories
    print_info "Checking service directories..."
    for service in "${REQUIRED_SERVICES[@]}"; do
        service_path="/Users/kg/IdeaProjects/$service"
        check_directory "$service_path"
        print_status "$service directory found"
    done
    
    # Check frontend directory
    frontend_path="/Users/kg/IdeaProjects/$FRONTEND_SERVICE"
    check_directory "$frontend_path"
    print_status "$FRONTEND_SERVICE directory found"
    echo ""
    
    # 3. Setup infrastructure
    setup_database
    setup_redis
    echo ""
    
    # 4. Setup each microservice
    print_info "Setting up microservices..."
    for service in "${REQUIRED_SERVICES[@]}"; do
        if [ "$service" = "pyairtable-common" ]; then
            continue  # Skip common library for env setup
        fi
        
        service_path="/Users/kg/IdeaProjects/$service"
        print_info "Setting up $service..."
        
        create_env_file "$service_path"
        check_python_env "$service_path"
        
        print_status "$service setup complete"
        echo ""
    done
    
    # 5. Setup frontend service
    print_info "Setting up frontend service..."
    frontend_path="/Users/kg/IdeaProjects/$FRONTEND_SERVICE"
    print_info "Setting up $FRONTEND_SERVICE..."
    
    create_env_file "$frontend_path"
    check_nodejs_env "$frontend_path"
    
    print_status "$FRONTEND_SERVICE setup complete"
    echo ""
    
    # 6. Create master environment file
    print_info "Creating master environment configuration..."
    cat > "$COMPOSE_DIR/.env" << 'EOF'
# Master Environment Configuration
# Copy the API keys from individual service .env files

# Required: Get from Google AI Studio
GEMINI_API_KEY=your_gemini_api_key_here

# Required: Get from Airtable > Account > Developer hub > Personal access tokens
AIRTABLE_TOKEN=your_airtable_token_here

# Internal API keys (can leave as default for local development)
API_KEY=internal_api_key_123

# Database Configuration
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/pyairtable
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=pyairtable

# Redis Configuration
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=

# Service Ports
LLM_ORCHESTRATOR_PORT=8003
MCP_SERVER_PORT=8001
AIRTABLE_GATEWAY_PORT=8002
FRONTEND_PORT=3000

# CORS Configuration
CORS_ORIGINS=http://localhost:3000,http://localhost:8000

# Frontend Configuration
NEXT_PUBLIC_API_URL=http://localhost:8000
NEXTAUTH_SECRET=your-secret-key-change-in-production
NEXTAUTH_URL=http://localhost:3000
NODE_ENV=development
ENABLE_DEBUG=false
SHOW_COST_TRACKING=true

# Logging
LOG_LEVEL=INFO

# Other Configuration
USE_HTTP_MCP=true
DEFAULT_MODEL=gemini-2.5-flash
SESSION_TIMEOUT=3600
EOF
    
    print_status "Master .env file created"
    echo ""
    
    # 6. Final instructions
    echo -e "${GREEN}🎉 Setup Complete!${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Edit the API keys in .env files:"
    echo "   - Add your GEMINI_API_KEY from Google AI Studio"
    echo "   - Add your AIRTABLE_TOKEN from Airtable Developer hub"
    echo ""
    echo "2. Start the services:"
    echo "   ./start.sh"
    echo ""
    echo "3. Test the system:"
    echo "   ./test.sh"
    echo ""
    echo -e "${BLUE}Service URLs (once started):${NC}"
    echo "• Frontend: http://localhost:3000"
    echo "• API Gateway: http://localhost:8000"
    echo "• LLM Orchestrator: http://localhost:8003"
    echo "• MCP Server: http://localhost:8001" 
    echo "• Airtable Gateway: http://localhost:8002"
    echo ""
    echo -e "${YELLOW}Configuration files created:${NC}"
    echo "• $COMPOSE_DIR/.env (master config)"
    echo "• Individual service .env files"
    echo ""
    echo -e "${GREEN}Ready for local development! 🚀${NC}"
}

# Run main function
main "$@"