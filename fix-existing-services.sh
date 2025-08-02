#!/bin/bash

# Fix existing service issues before running full setup

set -e

echo "🔧 Fixing Existing PyAirtable Services"
echo "======================================"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[FIX]${NC} $1"; }
log_success() { echo -e "${GREEN}[FIXED]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to backup and fix files
backup_and_fix() {
    local file_path="$1"
    local backup_path="${file_path}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$file_path" ]; then
        cp "$file_path" "$backup_path"
        log_info "Backed up $file_path to $backup_path"
        return 0
    else
        log_warning "File not found: $file_path"
        return 1
    fi
}

# Fix 1: LLM Orchestrator import issue
fix_llm_orchestrator() {
    log_info "Fixing LLM Orchestrator import issues..."
    
    local main_file="../llm-orchestrator-py/main.py"
    if [ -f "$main_file" ]; then
        backup_and_fix "$main_file"
        
        # Fix import paths
        sed -i.tmp 's/from chat.handler import chat_handler/from src.chat.handler import chat_handler/g' "$main_file"
        sed -i.tmp 's/from chat./from src.chat./g' "$main_file"
        rm -f "$main_file.tmp"
        
        log_success "Fixed LLM Orchestrator imports"
    else
        log_warning "LLM Orchestrator main.py not found at $main_file"
    fi
}

# Fix 2: Airtable Gateway pyairtable dependency
fix_airtable_gateway() {
    log_info "Fixing Airtable Gateway dependencies..."
    
    local dockerfile="../airtable-gateway-py/Dockerfile"
    local requirements="../airtable-gateway-py/requirements.txt"
    
    if [ -f "$requirements" ]; then
        backup_and_fix "$requirements"
        
        # Ensure pyairtable is installed
        if ! grep -q "pyairtable" "$requirements"; then
            echo "pyairtable==2.3.3" >> "$requirements"
        fi
        
        log_success "Fixed Airtable Gateway requirements"
    else
        log_warning "Airtable Gateway requirements.txt not found"
    fi
}

# Fix 3: Platform Services SQLAlchemy metadata issue
fix_platform_services() {
    log_info "Fixing Platform Services SQLAlchemy issues..."
    
    # Find and fix metadata field issues
    local service_dir="../pyairtable-platform-services"
    if [ -d "$service_dir" ]; then
        find "$service_dir" -name "*.py" -exec grep -l "metadata.*=" {} \; | while read -r file; do
            backup_and_fix "$file"
            
            # Replace metadata field with meta_data
            sed -i.tmp 's/metadata\s*=/meta_data =/g' "$file"
            sed -i.tmp 's/\.metadata/.meta_data/g' "$file"
            rm -f "$file.tmp"
            
            log_success "Fixed metadata field in $file"
        done
    else
        log_warning "Platform Services directory not found"
    fi
}

# Fix 4: Automation Services pydantic settings
fix_automation_services() {
    log_info "Fixing Automation Services pydantic issues..."
    
    local config_file="../pyairtable-automation-services/src/config.py"
    local requirements="../pyairtable-automation-services/requirements.txt"
    
    if [ -f "$config_file" ]; then
        backup_and_fix "$config_file"
        
        # Fix pydantic imports
        sed -i.tmp 's/from pydantic import BaseSettings/from pydantic_settings import BaseSettings/g' "$config_file"
        rm -f "$config_file.tmp"
        
        log_success "Fixed Automation Services pydantic imports"
    fi
    
    if [ -f "$requirements" ]; then
        backup_and_fix "$requirements"
        
        # Add pydantic-settings
        if ! grep -q "pydantic-settings" "$requirements"; then
            echo "pydantic-settings>=2.0.0" >> "$requirements"
        fi
        
        log_success "Added pydantic-settings to requirements"
    fi
}

# Fix 5: Create missing directories and files
create_missing_structure() {
    log_info "Creating missing directories and files..."
    
    # Create main directories if they don't exist
    mkdir -p python-services
    mkdir -p frontend-services
    mkdir -p go-services
    mkdir -p scripts
    mkdir -p configs
    mkdir -p monitoring
    
    # Create .env if it doesn't exist
    if [ ! -f ".env" ]; then
        if [ -f ".env.template" ]; then
            cp ".env.template" ".env"
            log_info "Created .env from template - please configure your values"
        else
            cat > ".env" << 'EOF'
# Basic PyAirtable Configuration
API_KEY=dev-api-key-change-me
LOG_LEVEL=info
ENVIRONMENT=development

POSTGRES_DB=pyairtable
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres

REDIS_PASSWORD=redis

AIRTABLE_TOKEN=your-token-here
AIRTABLE_BASE=your-base-here
GEMINI_API_KEY=your-gemini-key

JWT_SECRET=default-jwt-secret-change-in-production
NEXTAUTH_SECRET=default-nextauth-secret

CORS_ORIGINS=*
NODE_ENV=development
EOF
            log_info "Created basic .env file - please configure your values"
        fi
    fi
    
    log_success "Created missing structure"
}

# Quick health check script
create_quick_health_check() {
    log_info "Creating quick health check script..."
    
    cat > "quick-health-check.sh" << 'EOF'
#!/bin/bash

echo "🏥 Quick Health Check"
echo "===================="

# Check existing services
echo "Checking existing services..."

services=(
    "API Gateway:8000:/health"
    "MCP Server:8001:/health" 
    "Airtable Gateway:8002:/health"
    "LLM Orchestrator:8003:/health"
    "Automation Services:8006:/health"
    "Platform Services:8007:/health"
)

for service in "${services[@]}"; do
    IFS=':' read -r name port path <<< "$service"
    url="http://localhost:$port$path"
    
    if curl -s --max-time 3 "$url" > /dev/null 2>&1; then
        echo "✅ $name ($port) - OK"
    else
        echo "❌ $name ($port) - DOWN"
    fi
done

echo ""
echo "To start services: docker-compose up -d"
echo "To see logs: docker-compose logs -f [service-name]"
echo "To rebuild: docker-compose up -d --build"
EOF

    chmod +x "quick-health-check.sh"
    log_success "Created quick-health-check.sh"
}

# Create immediate startup script for current services
create_immediate_startup() {
    log_info "Creating immediate startup script for current services..."
    
    cat > "start-current-services.sh" << 'EOF'
#!/bin/bash

echo "🚀 Starting Current PyAirtable Services"
echo "======================================="

# Ensure we have an .env file
if [ ! -f ".env" ]; then
    echo "❌ No .env file found. Please create one from .env.template"
    exit 1
fi

# Start infrastructure first
echo "📦 Starting infrastructure..."
docker-compose up -d postgres redis

echo "⏳ Waiting for infrastructure (15 seconds)..."
sleep 15

# Start core services
echo "🔧 Starting core services..."
docker-compose up -d \
    api-gateway \
    mcp-server \
    airtable-gateway \
    llm-orchestrator \
    platform-services \
    automation-services

echo "⏳ Waiting for services to initialize (20 seconds)..."
sleep 20

# Start frontend
echo "🌐 Starting frontend..."
docker-compose up -d frontend

echo "✅ Services started! Running health check..."
sleep 10

./quick-health-check.sh

echo ""
echo "🎯 Access your services:"
echo "- Main API: http://localhost:8000"
echo "- Frontend: http://localhost:3000"
echo "- MCP Server: http://localhost:8001"
echo ""
echo "View logs: docker-compose logs -f"
echo "Stop all: docker-compose down"
EOF

    chmod +x "start-current-services.sh"
    log_success "Created start-current-services.sh"
}

# Create Docker rebuild script
create_rebuild_script() {
    log_info "Creating rebuild script..."
    
    cat > "rebuild-services.sh" << 'EOF'
#!/bin/bash

echo "🔨 Rebuilding PyAirtable Services"
echo "================================="

# Stop all services
echo "⏹️  Stopping all services..."
docker-compose down

# Remove old images (optional - uncomment if needed)
# docker-compose down --rmi all

# Rebuild with no cache
echo "🏗️  Rebuilding all services..."
docker-compose build --no-cache

# Start services
echo "🚀 Starting rebuilt services..."
./start-current-services.sh

echo "✅ Rebuild complete!"
EOF

    chmod +x "rebuild-services.sh"
    log_success "Created rebuild-services.sh"
}

# Main execution
main() {
    echo "Starting fixes for existing services..."
    echo ""
    
    fix_llm_orchestrator
    fix_airtable_gateway  
    fix_platform_services
    fix_automation_services
    create_missing_structure
    create_quick_health_check
    create_immediate_startup
    create_rebuild_script
    
    echo ""
    echo "✅ All fixes applied!"
    echo "===================="
    echo ""
    echo "🎯 IMMEDIATE ACTIONS YOU CAN RUN NOW:"
    echo ""
    echo "1. Test current services:"
    echo "   ./quick-health-check.sh"
    echo ""
    echo "2. Start current services (6 services):"
    echo "   ./start-current-services.sh"
    echo ""
    echo "3. Rebuild if there are issues:"
    echo "   ./rebuild-services.sh"
    echo ""
    echo "4. Generate all 30 services:"
    echo "   ./setup-all-services.sh"
    echo ""
    echo "5. View running containers:"
    echo "   docker-compose ps"
    echo ""
    echo "6. View logs:"
    echo "   docker-compose logs -f [service-name]"
    echo ""
    echo "🔧 Configuration:"
    echo "- Edit .env file with your actual API keys"
    echo "- Airtable token, Gemini API key, etc."
    echo ""
    echo "📊 Expected working services after fixes:"
    echo "- API Gateway (port 8000)"
    echo "- MCP Server (port 8001)" 
    echo "- Airtable Gateway (port 8002)"
    echo "- LLM Orchestrator (port 8003)"
    echo "- Platform Services (port 8007)"
    echo "- Automation Services (port 8006)"
    echo "- Frontend (port 3000)"
}

# Run main function
main "$@"