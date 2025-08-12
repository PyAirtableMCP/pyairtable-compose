#!/bin/bash

# PyAirtable Optimized Minikube Development Setup
# Fast startup, resource efficient, developer-friendly local environment
# Version: 2.0
# Target: < 3 minutes full stack startup, < 6GB RAM, < 3 CPU cores

set -euo pipefail

# Color codes for better UX
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration optimized for laptop development
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_NAME="pyairtable"
readonly NAMESPACE="pyairtable-dev"
readonly MINIKUBE_PROFILE="pyairtable-dev"

# Resource optimization for local development
readonly MINIKUBE_MEMORY="3072"  # 3GB - optimized for current Docker allocation
readonly MINIKUBE_CPUS="2"       # 2 CPUs - conservative for stability
readonly MINIKUBE_DISK="20g"     # 20GB - optimized for current setup
readonly KUBERNETES_VERSION="v1.28.3"
readonly CONTAINER_RUNTIME="containerd"

# Performance tuning
readonly MAX_STARTUP_TIME="180"  # 3 minutes max
readonly HEALTH_CHECK_TIMEOUT="60"
readonly SERVICE_STARTUP_DELAY="5"

# Logging
readonly LOG_FILE="${SCRIPT_DIR}/.minikube-dev.log"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Essential addons only for faster startup
readonly ADDONS=(
    "storage-provisioner"
    "default-storageclass"
    "metrics-server"
    "ingress"
)

# Service startup order for dependency management
readonly SERVICE_ORDER=(
    "postgres"
    "redis"
    "airtable-gateway"
    "mcp-server"
    "llm-orchestrator"
    "platform-services"
    "automation-services"
)

# Helper functions
log() {
    echo -e "${WHITE}[$(date +'%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║  🚀 PyAirtable Fast Minikube Development Environment                         ║
║                                                                              ║
║  ⚡ Optimized for: < 3min startup, < 6GB RAM, < 3 CPU cores                ║
║  🔧 Features: Hot reload, debug ports, health monitoring                    ║
║  🎯 Target: Laptop-friendly local development workflow                      ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

print_section() {
    echo -e "\n${PURPLE}═══ $* ═══${NC}\n"
}

# Time tracking
start_timer() {
    TIMER_START=$(date +%s)
}

stop_timer() {
    local end_time=$(date +%s)
    local duration=$((end_time - TIMER_START))
    log_success "Operation completed in ${duration}s"
}

# Prerequisites check (fast)
check_prerequisites() {
    print_section "CHECKING PREREQUISITES"
    
    local missing=()
    for tool in minikube kubectl docker; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing tools: ${missing[*]}"
        echo -e "\n${YELLOW}Quick install:${NC}"
        echo "  brew install minikube kubectl docker"
        exit 1
    fi
    
    # Quick Docker check
    if ! docker info &> /dev/null; then
        log_error "Docker daemon not running. Please start Docker Desktop."
        exit 1
    fi
    
    log_success "All prerequisites available"
}

# System resource verification
check_resources() {
    print_section "VERIFYING SYSTEM RESOURCES"
    
    # macOS memory check
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local total_mem_gb=$(echo "$(sysctl -n hw.memsize) / 1024 / 1024 / 1024" | bc)
        local available_mem_gb=$(echo "$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//' ) * 4096 / 1024 / 1024 / 1024" | bc)
        
        log_info "Total memory: ${total_mem_gb}GB, Available: ${available_mem_gb}GB"
        
        if [ "$total_mem_gb" -lt 8 ]; then
            log_warning "System has less than 8GB total memory. Performance may be affected."
        fi
    fi
    
    log_success "System resources adequate for development"
}

# Fast Minikube setup with optimizations
setup_minikube() {
    print_section "SETTING UP MINIKUBE (OPTIMIZED)"
    start_timer
    
    # Check existing cluster
    if minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
        log_info "Minikube cluster already running"
        stop_timer
        return 0
    fi
    
    log_info "Starting optimized Minikube cluster..."
    log_info "Config: ${MINIKUBE_MEMORY}MB RAM, ${MINIKUBE_CPUS} CPUs, ${MINIKUBE_DISK} disk"
    
    # Start with performance optimizations
    minikube start \
        --profile="$MINIKUBE_PROFILE" \
        --memory="$MINIKUBE_MEMORY" \
        --cpus="$MINIKUBE_CPUS" \
        --disk-size="$MINIKUBE_DISK" \
        --kubernetes-version="$KUBERNETES_VERSION" \
        --driver=docker \
        --container-runtime="$CONTAINER_RUNTIME" \
        --cache-images=true \
        --embed-certs=true \
        --install-addons=false \
        --wait=true \
        --wait-timeout="${MAX_STARTUP_TIME}s" \
        --extra-config=kubelet.housekeeping-interval=30s \
        --extra-config=kubelet.image-gc-high-threshold=85 \
        --extra-config=kubelet.image-gc-low-threshold=80 \
        --extra-config=kubelet.max-pods=50 \
        --extra-config=controller-manager.horizontal-pod-autoscaler-sync-period=30s \
        --extra-config=controller-manager.node-monitor-grace-period=30s \
        --extra-config=apiserver.default-not-ready-toleration-seconds=60 \
        --extra-config=apiserver.default-unreachable-toleration-seconds=60
    
    # Set context
    kubectl config use-context "$MINIKUBE_PROFILE"
    
    # Enable only essential addons for faster startup
    log_info "Enabling essential addons..."
    for addon in "${ADDONS[@]}"; do
        minikube addons enable "$addon" -p "$MINIKUBE_PROFILE" &
    done
    wait
    
    # Wait for cluster to be ready
    kubectl wait --for=condition=Ready nodes --all --timeout=60s
    
    stop_timer
    log_success "Minikube cluster ready"
}

# Generate development secrets quickly
generate_dev_secrets() {
    print_section "GENERATING DEVELOPMENT SECRETS"
    
    local secrets_dir="${SCRIPT_DIR}/.dev-secrets"
    mkdir -p "$secrets_dir"
    chmod 700 "$secrets_dir"
    
    local secrets_file="${secrets_dir}/secrets.env"
    
    if [[ -f "$secrets_file" ]] && [[ -n "${FORCE_REGEN:-}" ]]; then
        log_info "Using existing development secrets"
        source "$secrets_file"
        return 0
    fi
    
    log_info "Generating secure development secrets..."
    
    # Fast secret generation
    local postgres_pass=$(openssl rand -base64 12 | tr -d "=+/")
    local jwt_secret=$(openssl rand -base64 24 | tr -d "=+/")
    local redis_pass=$(openssl rand -base64 12 | tr -d "=+/")
    local api_key=$(openssl rand -base64 16 | tr -d "=+/")
    
    cat > "$secrets_file" << EOF
# PyAirtable Development Secrets - Generated $(date)
export POSTGRES_PASSWORD="$postgres_pass"
export JWT_SECRET="$jwt_secret"
export REDIS_PASSWORD="$redis_pass"
export API_KEY="$api_key"
export NEXTAUTH_SECRET="$jwt_secret"

# Database config
export POSTGRES_DB="pyairtable_dev"
export POSTGRES_USER="pyairtable"

# Development defaults
export ENVIRONMENT="development"
export LOG_LEVEL="debug"
export NODE_ENV="development"
EOF
    
    chmod 600 "$secrets_file"
    source "$secrets_file"
    
    log_success "Development secrets generated"
}

# Create namespace and basic resources
create_namespace() {
    print_section "CREATING NAMESPACE AND RESOURCES"
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create development secrets
    kubectl create secret generic pyairtable-dev-secrets \
        --namespace="$NAMESPACE" \
        --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
        --from-literal=redis-password="${REDIS_PASSWORD}" \
        --from-literal=jwt-secret="${JWT_SECRET}" \
        --from-literal=api-key="${API_KEY}" \
        --from-literal=nextauth-secret="${NEXTAUTH_SECRET}" \
        --from-literal=airtable-token="${AIRTABLE_TOKEN:-dev-placeholder}" \
        --from-literal=gemini-api-key="${GEMINI_API_KEY:-dev-placeholder}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Namespace and secrets created"
}

# Deploy infrastructure with fast startup
deploy_infrastructure() {
    print_section "DEPLOYING INFRASTRUCTURE (FAST MODE)"
    start_timer
    
    # PostgreSQL with development optimizations
    kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: pyairtable-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: "pyairtable_dev"
        - name: POSTGRES_USER
          value: "pyairtable"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pyairtable-dev-secrets
              key: postgres-password
        # Development performance optimizations
        - name: POSTGRES_SHARED_BUFFERS
          value: "64MB"
        - name: POSTGRES_EFFECTIVE_CACHE_SIZE
          value: "256MB"
        - name: POSTGRES_WORK_MEM
          value: "2MB"
        - name: POSTGRES_MAINTENANCE_WORK_MEM
          value: "32MB"
        - name: POSTGRES_FSYNC
          value: "off"  # Fast for development
        - name: POSTGRES_SYNCHRONOUS_COMMIT
          value: "off"
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "pyairtable", "-d", "pyairtable_dev"]
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: postgres-data
        emptyDir: {}  # Fast ephemeral storage for development
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: pyairtable-dev
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
EOF

    # Redis with minimal resources
    kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: pyairtable-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        command: ["redis-server", "--appendonly", "no", "--save", ""]
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pyairtable-dev-secrets
              key: redis-password
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
        readinessProbe:
          exec:
            command: ["redis-cli", "ping"]
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: pyairtable-dev
spec:
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
EOF

    # Wait for infrastructure
    log_info "Waiting for infrastructure to be ready..."
    kubectl wait --for=condition=available deployment/postgres deployment/redis \
        --namespace="$NAMESPACE" --timeout=60s
    
    stop_timer
    log_success "Infrastructure deployed and ready"
}

# Deploy services with optimized manifests
deploy_services() {
    print_section "DEPLOYING APPLICATION SERVICES"
    start_timer
    
    # Apply optimized minikube manifests
    if [[ -d "${SCRIPT_DIR}/minikube-manifests-optimized" ]]; then
        kubectl apply -f "${SCRIPT_DIR}/minikube-manifests-optimized/"
    else
        log_warning "Optimized manifests not found, using existing manifests"
        kubectl apply -f "${SCRIPT_DIR}/minikube-manifests/"
    fi
    
    # Wait for services in dependency order
    for service in "${SERVICE_ORDER[@]}"; do
        if kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
            log_info "Waiting for $service to be ready..."
            kubectl wait --for=condition=available "deployment/$service" \
                --namespace="$NAMESPACE" --timeout=60s || log_warning "$service not ready yet"
            sleep "$SERVICE_STARTUP_DELAY"
        fi
    done
    
    stop_timer
    log_success "Services deployed"
}

# Health validation
validate_deployment() {
    print_section "VALIDATING DEPLOYMENT"
    
    local failed=0
    
    # Check pods
    log_info "Checking pod status..."
    local not_running=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
    if [[ "$not_running" -eq 0 ]]; then
        log_success "All pods running"
    else
        log_warning "$not_running pods not running"
        kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running
        ((failed++))
    fi
    
    # Test basic connectivity
    log_info "Testing service connectivity..."
    if kubectl run test-connectivity --rm -i --restart=Never --image=curlimages/curl:latest \
       --namespace="$NAMESPACE" -- sh -c "curl -f http://postgres:5432 && echo 'DB: OK'" &> /dev/null; then
        log_success "Basic connectivity working"
    else
        log_warning "Connectivity test failed"
        ((failed++))
    fi
    
    if [[ $failed -eq 0 ]]; then
        log_success "Deployment validation passed"
        return 0
    else
        log_warning "Deployment validation completed with $failed warnings"
        return 1
    fi
}

# Setup development tools and access
setup_dev_access() {
    print_section "SETTING UP DEVELOPMENT ACCESS"
    
    local minikube_ip
    minikube_ip=$(minikube ip -p "$MINIKUBE_PROFILE" 2>/dev/null || echo "localhost")
    
    # Create development script
    cat > "${SCRIPT_DIR}/dev-access.sh" << EOF
#!/bin/bash
# PyAirtable Development Access Script
# Generated: $(date)

export MINIKUBE_PROFILE="$MINIKUBE_PROFILE"
export NAMESPACE="$NAMESPACE"
export MINIKUBE_IP="$minikube_ip"

# Quick commands
alias k="kubectl -n $NAMESPACE"
alias logs="kubectl logs -n $NAMESPACE"
alias pods="kubectl get pods -n $NAMESPACE"
alias services="kubectl get services -n $NAMESPACE"

# Port forwarding functions
forward_all() {
    echo "Setting up port forwarding for all services..."
    kubectl port-forward -n $NAMESPACE service/postgres 5432:5432 &
    kubectl port-forward -n $NAMESPACE service/redis 6379:6379 &
    echo "Port forwarding active. Use 'pkill -f port-forward' to stop."
}

# Health check
health_check() {
    echo "=== PyAirtable Health Check ==="
    kubectl get pods -n $NAMESPACE
    echo ""
    kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Metrics not available yet"
}

# Quick restart
restart_service() {
    local service=\$1
    if [[ -z "\$service" ]]; then
        echo "Usage: restart_service <service-name>"
        return 1
    fi
    kubectl rollout restart deployment/\$service -n $NAMESPACE
    kubectl rollout status deployment/\$service -n $NAMESPACE
}

echo "PyAirtable development environment ready!"
echo "Available commands: forward_all, health_check, restart_service"
echo "Quick access: k, logs, pods, services"
EOF
    
    chmod +x "${SCRIPT_DIR}/dev-access.sh"
    
    log_success "Development access script created: ./dev-access.sh"
}

# Print final summary
print_summary() {
    print_section "DEPLOYMENT COMPLETE"
    
    local minikube_ip
    minikube_ip=$(minikube ip -p "$MINIKUBE_PROFILE" 2>/dev/null || echo "localhost")
    
    echo -e "${GREEN}🎉 PyAirtable development environment is ready!${NC}\n"
    
    echo -e "${CYAN}📋 Environment Information:${NC}"
    echo -e "  Profile: $MINIKUBE_PROFILE"
    echo -e "  Namespace: $NAMESPACE"
    echo -e "  Minikube IP: $minikube_ip"
    echo -e "  Resources: ${MINIKUBE_MEMORY}MB RAM, ${MINIKUBE_CPUS} CPUs"
    echo
    
    echo -e "${CYAN}🔧 Quick Commands:${NC}"
    echo -e "  source ./dev-access.sh          # Load development environment"
    echo -e "  kubectl get pods -n $NAMESPACE  # Check service status"
    echo -e "  minikube dashboard -p $MINIKUBE_PROFILE  # Open dashboard"
    echo
    
    echo -e "${CYAN}🌐 Service Access:${NC}"
    echo -e "  Database: localhost:5432 (via port-forward)"
    echo -e "  Redis: localhost:6379 (via port-forward)"
    echo -e "  Use './dev-access.sh' and run 'forward_all' for port forwarding"
    echo
    
    echo -e "${YELLOW}⚠️  Development Notes:${NC}"
    echo -e "  • This is optimized for development - not production ready"
    echo -e "  • Database uses ephemeral storage (data lost on restart)"
    echo -e "  • Security is relaxed for development convenience"
    echo -e "  • Set AIRTABLE_TOKEN and GEMINI_API_KEY for full functionality"
    echo
    
    echo -e "${GREEN}✨ Happy developing!${NC}"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Setup failed with exit code $exit_code"
        echo -e "\n${YELLOW}Troubleshooting:${NC}"
        echo -e "  • Check log: $LOG_FILE"
        echo -e "  • Verify Docker is running"
        echo -e "  • Try: minikube delete -p $MINIKUBE_PROFILE && $0"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Main execution
main() {
    print_banner
    
    # Initialize logging
    echo "PyAirtable Minikube Dev Setup - $(date)" > "$LOG_FILE"
    
    local start_time=$(date +%s)
    
    # Execute setup
    check_prerequisites
    check_resources
    setup_minikube
    generate_dev_secrets
    create_namespace
    deploy_infrastructure
    deploy_services
    validate_deployment
    setup_dev_access
    
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    log_success "Total setup time: ${total_time}s"
    print_summary
}

# Command line handling
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "PyAirtable Fast Minikube Development Setup"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  (no args)  Full setup"
        echo "  clean      Clean up everything"
        echo "  restart    Restart services"
        echo "  status     Show status"
        echo "  help       Show this help"
        echo
        exit 0
        ;;
    "clean")
        log_info "Cleaning up development environment..."
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
        minikube delete -p "$MINIKUBE_PROFILE" || true
        rm -rf "${SCRIPT_DIR}/.dev-secrets"
        rm -f "${SCRIPT_DIR}/dev-access.sh"
        log_success "Cleanup completed"
        exit 0
        ;;
    "restart")
        log_info "Restarting services..."
        for service in "${SERVICE_ORDER[@]}"; do
            if kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
                kubectl rollout restart "deployment/$service" -n "$NAMESPACE"
            fi
        done
        log_success "Services restarted"
        exit 0
        ;;
    "status")
        echo "PyAirtable Development Status"
        echo "============================="
        kubectl get all -n "$NAMESPACE" 2>/dev/null || echo "Environment not deployed"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac