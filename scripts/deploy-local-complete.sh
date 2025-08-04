#!/bin/bash

# PyAirtable Complete Local Deployment Script
# One-command deployment for local development on Minikube
# Handles setup, build, deploy, and validation with proper error handling

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly MINIKUBE_PROFILE="pyairtable"
readonly NAMESPACE="pyairtable"
readonly TIMEOUT_SECONDS=600
readonly HEALTH_CHECK_RETRIES=30
readonly HEALTH_CHECK_INTERVAL=10

# Deployment phases
readonly PHASES=(
    "preflight"
    "cluster"
    "images"
    "database"
    "secrets"
    "services"
    "validation"
    "dashboard"
)

# Service deployment order (respecting dependencies)
readonly SERVICE_ORDER=(
    "postgres"
    "redis" 
    "airtable-gateway"
    "mcp-server"
    "llm-orchestrator"
    "platform-services"
    "automation-services"
    "saga-orchestrator"
    "api-gateway"
    "frontend"
)

# Error handling
readonly ERROR_LOG="/tmp/pyairtable-deploy-error.log"
touch "$ERROR_LOG"

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_phase() {
    echo -e "\n${PURPLE}📋 Phase: $1${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$ERROR_LOG"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_progress() {
    echo -e "${PURPLE}🔄 $1${NC}"
}

# Cleanup function for rollback
cleanup_on_error() {
    local exit_code=$?
    print_error "Deployment failed with exit code: $exit_code"
    print_info "Error log available at: $ERROR_LOG"
    
    if [[ "${ROLLBACK_ON_ERROR:-true}" == "true" ]]; then
        print_warning "Initiating rollback..."
        rollback_deployment
    fi
    
    exit $exit_code
}

trap cleanup_on_error ERR

# Rollback function
rollback_deployment() {
    print_header "Rolling Back Deployment"
    
    # Delete all resources in the namespace
    kubectl delete all --all -n "$NAMESPACE" --timeout=60s || true
    kubectl delete pvc --all -n "$NAMESPACE" --timeout=60s || true
    kubectl delete secrets --all -n "$NAMESPACE" --timeout=60s || true
    kubectl delete configmaps --all -n "$NAMESPACE" --timeout=60s || true
    
    print_success "Rollback completed"
}

# Preflight checks
preflight_checks() {
    print_phase "Preflight Checks"
    
    local missing_tools=()
    
    # Check required tools
    for tool in minikube kubectl helm docker; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Installation instructions:"
        echo "- minikube: https://minikube.sigs.k8s.io/docs/start/"
        echo "- kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "- helm: https://helm.sh/docs/intro/install/"
        echo "- docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check system resources
    local available_memory
    if [[ "$OSTYPE" == "darwin"* ]]; then
        available_memory=$(echo "$(sysctl -n hw.memsize) / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "8")
    else
        available_memory=$(free -g | awk '/^Mem:/{print $7}' 2>/dev/null || echo "8")
    fi
    
    if [ "$available_memory" -lt 6 ]; then
        print_warning "System has less than 6GB available memory. Performance may be impacted."
    fi
    
    print_success "Preflight checks passed"
}

# Setup Minikube cluster
setup_cluster() {
    print_phase "Cluster Setup"
    
    # Check if cluster exists and is running
    if minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
        print_info "Minikube cluster '$MINIKUBE_PROFILE' is already running"
    else
        print_progress "Starting Minikube cluster..."
        "$SCRIPT_DIR/minikube-setup.sh" --clean
    fi
    
    # Ensure kubectl context is set
    kubectl config use-context "$MINIKUBE_PROFILE"
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        kubectl create namespace "$NAMESPACE"
    fi
    
    print_success "Cluster setup completed"
}

# Build and push Docker images
build_images() {
    print_phase "Building Docker Images"
    
    # Enable Minikube Docker environment
    eval "$(minikube docker-env -p "$MINIKUBE_PROFILE")"
    
    local services=(
        "pyairtable-api-gateway:../pyairtable-api-gateway"
        "llm-orchestrator-py:../llm-orchestrator-py"
        "mcp-server-py:../mcp-server-py"
        "airtable-gateway-py:../airtable-gateway-py"
        "pyairtable-platform-services:../pyairtable-platform-services"
        "pyairtable-automation-services:../pyairtable-automation-services"
        "pyairtable-saga-orchestrator:./saga-orchestrator"
        "pyairtable-frontend:../pyairtable-frontend"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r image_name context_path <<< "$service_info"
        
        if [[ -d "$PROJECT_ROOT/$context_path" ]]; then
            print_progress "Building $image_name..."
            
            # Build with BuildKit for faster builds
            DOCKER_BUILDKIT=1 docker build \
                -t "$image_name:latest" \
                -f "$PROJECT_ROOT/$context_path/Dockerfile" \
                "$PROJECT_ROOT/$context_path" || {
                print_error "Failed to build $image_name"
                return 1
            }
            
            print_success "Built $image_name"
        else
            print_warning "Context path not found for $image_name: $context_path"
        fi
    done
    
    print_success "All images built successfully"
}

# Initialize database
initialize_database() {
    print_phase "Database Initialization"
    
    print_progress "Deploying PostgreSQL..."
    
    # Deploy PostgreSQL with initialization
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init-config
  namespace: $NAMESPACE
data:
  init-db.sql: |
    -- Create main database
    CREATE DATABASE IF NOT EXISTS pyairtable;
    
    -- Create user with proper permissions
    CREATE USER pyairtable_user WITH ENCRYPTED PASSWORD 'pyairtable_pass';
    GRANT ALL PRIVILEGES ON DATABASE pyairtable TO pyairtable_user;
    
    -- Connect to the database
    \\c pyairtable;
    
    -- Create extensions
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";
    
    -- Create schemas
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE SCHEMA IF NOT EXISTS analytics;
    CREATE SCHEMA IF NOT EXISTS workflows;
    CREATE SCHEMA IF NOT EXISTS files;
    CREATE SCHEMA IF NOT EXISTS saga;
    
    -- Grant schema permissions
    GRANT ALL ON SCHEMA auth TO pyairtable_user;
    GRANT ALL ON SCHEMA analytics TO pyairtable_user;
    GRANT ALL ON SCHEMA workflows TO pyairtable_user;
    GRANT ALL ON SCHEMA files TO pyairtable_user;
    GRANT ALL ON SCHEMA saga TO pyairtable_user;
    
    -- Create basic tables
    CREATE TABLE IF NOT EXISTS auth.users (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        email VARCHAR(255) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS analytics.events (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        event_type VARCHAR(100) NOT NULL,
        user_id UUID REFERENCES auth.users(id),
        data JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS saga.sagas (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        saga_type VARCHAR(100) NOT NULL,
        status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
        data JSONB,
        steps JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    -- Create indexes
    CREATE INDEX IF NOT EXISTS idx_users_email ON auth.users(email);
    CREATE INDEX IF NOT EXISTS idx_events_type_created ON analytics.events(event_type, created_at);
    CREATE INDEX IF NOT EXISTS idx_sagas_status ON saga.sagas(status);
    
    -- Insert test data
    INSERT INTO auth.users (email, password_hash) VALUES 
        ('test@pyairtable.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LWFAzFuBqFm.7BaXG') -- password: 'testpass'
    ON CONFLICT (email) DO NOTHING;
EOF

    # Apply PostgreSQL deployment
    kubectl apply -f "$PROJECT_ROOT/k8s/postgres-deployment.yaml" -n "$NAMESPACE"
    
    # Wait for PostgreSQL to be ready
    print_progress "Waiting for PostgreSQL to be ready..."
    kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=300s
    
    # Deploy Redis
    print_progress "Deploying Redis..."
    kubectl apply -f "$PROJECT_ROOT/k8s/redis-deployment.yaml" -n "$NAMESPACE"
    
    # Wait for Redis to be ready
    print_progress "Waiting for Redis to be ready..."
    kubectl wait --for=condition=ready pod -l app=redis -n "$NAMESPACE" --timeout=300s
    
    print_success "Database initialization completed"
}

# Setup secrets
setup_secrets() {
    print_phase "Secrets Setup"
    
    # Create secrets with development defaults
    kubectl create secret generic pyairtable-secrets \
        --from-literal=api-key="dev-api-key-$(openssl rand -hex 16)" \
        --from-literal=jwt-secret="dev-jwt-secret-$(openssl rand -hex 32)" \
        --from-literal=nextauth-secret="dev-nextauth-secret-$(openssl rand -hex 32)" \
        --from-literal=redis-password="dev-redis-$(openssl rand -hex 8)" \
        --from-literal=postgres-db="pyairtable" \
        --from-literal=postgres-user="postgres" \
        --from-literal=postgres-password="dev-postgres-$(openssl rand -hex 8)" \
        --from-literal=thinking-budget="2000" \
        --from-literal=cors-origins="*" \
        --from-literal=max-file-size="10MB" \
        --from-literal=allowed-extensions="pdf,doc,docx,txt,csv,xlsx,json,yaml" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create configmap for environment variables
    kubectl create configmap pyairtable-config \
        --from-literal=environment="development" \
        --from-literal=log-level="debug" \
        --from-literal=enable-debug="true" \
        --from-literal=enable-metrics="true" \
        --from-literal=enable-tracing="true" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Secrets setup completed"
}

# Deploy services in dependency order
deploy_services() {
    print_phase "Services Deployment"
    
    for service in "${SERVICE_ORDER[@]}"; do
        print_progress "Deploying $service..."
        
        case $service in
            "postgres"|"redis")
                # Already deployed in database phase
                print_info "$service already deployed in database phase"
                ;;
            *)
                deploy_single_service "$service"
                ;;
        esac
    done
    
    print_success "All services deployed"
}

# Deploy a single service
deploy_single_service() {
    local service=$1
    local deployment_file
    
    # Determine deployment file
    case $service in
        "api-gateway")
            deployment_file="$PROJECT_ROOT/k8s/api-gateway-deployment.yaml"
            ;;
        "airtable-gateway"|"mcp-server"|"llm-orchestrator"|"platform-services"|"automation-services"|"saga-orchestrator"|"frontend")
            # Use Helm chart
            deploy_with_helm "$service"
            return
            ;;
        *)
            deployment_file="$PROJECT_ROOT/k8s/${service}-deployment.yaml"
            ;;
    esac
    
    if [[ -f "$deployment_file" ]]; then
        kubectl apply -f "$deployment_file" -n "$NAMESPACE"
    else
        print_warning "Deployment file not found for $service: $deployment_file"
    fi
}

# Deploy service with Helm
deploy_with_helm() {
    local service=$1
    
    # Use the Helm chart with Minikube values
    helm upgrade --install pyairtable-stack \
        "$PROJECT_ROOT/k8s/helm/pyairtable-stack" \
        --namespace "$NAMESPACE" \
        --values "$PROJECT_ROOT/k8s/values-minikube.yaml" \
        --set services.${service//-/}.enabled=true \
        --wait --timeout=300s
}

# Validate deployment
validate_deployment() {
    print_phase "Deployment Validation"
    
    print_progress "Checking pod status..."
    
    # Wait for all pods to be ready
    for service in "${SERVICE_ORDER[@]}"; do
        print_progress "Waiting for $service to be ready..."
        
        # Get the actual pod selector
        local selector
        case $service in
            "postgres")
                selector="app=postgres"
                ;;
            "redis")
                selector="app=redis"
                ;;
            *)
                selector="app=$service"
                ;;
        esac
        
        # Wait for pod to be ready
        if ! kubectl wait --for=condition=ready pod -l "$selector" -n "$NAMESPACE" --timeout=300s; then
            print_error "Service $service failed to become ready"
            kubectl describe pods -l "$selector" -n "$NAMESPACE"
            return 1
        fi
        
        print_success "$service is ready"
    done
    
    # Perform health checks
    print_progress "Performing health checks..."
    perform_health_checks
    
    print_success "Deployment validation completed"
}

# Perform health checks
perform_health_checks() {
    local services_with_health=(
        "api-gateway:8000:/health"
        "llm-orchestrator:8003:/health"
        "mcp-server:8001:/health"
        "airtable-gateway:8002:/health"
        "platform-services:8007:/health"
        "automation-services:8006:/health"
        "saga-orchestrator:8008:/health"
        "frontend:3000:/api/health"
    )
    
    for service_info in "${services_with_health[@]}"; do
        IFS=':' read -r service port path <<< "$service_info"
        
        print_progress "Health check: $service"
        
        # Use kubectl port-forward for health check
        kubectl port-forward "service/$service" "$port:$port" -n "$NAMESPACE" &
        local port_forward_pid=$!
        
        sleep 3
        
        if curl -f "http://localhost:$port$path" &> /dev/null; then
            print_success "$service health check passed"
        else
            print_warning "$service health check failed"
        fi
        
        kill $port_forward_pid 2>/dev/null || true
        sleep 1
    done
}

# Setup monitoring dashboard
setup_dashboard() {
    print_phase "Dashboard Setup"
    
    # Start Minikube dashboard
    print_info "Starting Minikube dashboard..."
    nohup minikube dashboard -p "$MINIKUBE_PROFILE" &> /dev/null &
    
    # Get service URLs
    local minikube_ip
    minikube_ip=$(minikube ip -p "$MINIKUBE_PROFILE")
    
    print_success "Dashboard setup completed"
    
    # Display access information
    print_header "🎉 Deployment Completed Successfully!"
    
    echo ""
    echo "Service Access URLs:"
    echo "==================="
    echo "Frontend:        http://$minikube_ip:30000"
    echo "API Gateway:     http://$minikube_ip:30800"
    echo "Kubernetes Dashboard: minikube dashboard -p $MINIKUBE_PROFILE"
    echo ""
    echo "Development Commands:"
    echo "===================="
    echo "View pods:       kubectl get pods -n $NAMESPACE"
    echo "View services:   kubectl get services -n $NAMESPACE"
    echo "View logs:       kubectl logs -f deployment/<service-name> -n $NAMESPACE"
    echo "Port forward:    kubectl port-forward service/<service-name> <local-port>:<service-port> -n $NAMESPACE"
    echo ""
    echo "Useful Shortcuts:"
    echo "================"
    echo "kubectl config set-context --current --namespace=$NAMESPACE"
    echo "alias k='kubectl'"
    echo "alias kgp='kubectl get pods'"
    echo "alias kgs='kubectl get services'"
    echo ""
    
    if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
        print_warning "Some errors occurred during deployment. Check $ERROR_LOG for details."
    fi
}

# Main deployment function
main() {
    print_header "PyAirtable Local Deployment"
    
    local start_time=$(date +%s)
    local selected_phases=("${PHASES[@]}")
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --phase)
                IFS=',' read -ra selected_phases <<< "$2"
                shift 2
                ;;
            --skip-build)
                selected_phases=("${selected_phases[@]/images}")
                shift
                ;;
            --no-rollback)
                ROLLBACK_ON_ERROR="false"
                shift
                ;;
            --clean)
                rollback_deployment
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --phase PHASES    Run specific phases (comma-separated): ${PHASES[*]}"
                echo "  --skip-build      Skip image building phase"
                echo "  --no-rollback     Don't rollback on error"
                echo "  --clean           Clean up existing deployment"
                echo "  --help, -h        Show this help message"
                echo ""
                echo "Available phases: ${PHASES[*]}"
                exit 0
                ;;
            *)
                print_error "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute selected phases
    for phase in "${selected_phases[@]}"; do
        case $phase in
            "preflight")
                preflight_checks
                ;;
            "cluster")
                setup_cluster
                ;;
            "images")
                build_images
                ;;
            "database")
                initialize_database
                ;;
            "secrets")
                setup_secrets
                ;;
            "services")
                deploy_services
                ;;
            "validation")
                validate_deployment
                ;;
            "dashboard")
                setup_dashboard
                ;;
            *)
                print_error "Unknown phase: $phase"
                exit 1
                ;;
        esac
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_success "Deployment completed in ${duration}s"
}

# Execute main function
main "$@"