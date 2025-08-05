#!/bin/bash

# PyAirtable Minikube Deployment System - Fixed Version
# Comprehensive one-command deployment with full automation

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly PROJECT_NAME="pyairtable"
readonly NAMESPACE="pyairtable"
readonly MINIKUBE_PROFILE="pyairtable-dev"
readonly REQUIRED_MEMORY="8192"
readonly REQUIRED_CPUS="4"
readonly REQUIRED_DISK="30g"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly TIMEOUT_DEPLOYMENT="600"
readonly TIMEOUT_READY="300"

# Logging functions
log() {
    echo -e "${WHITE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
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

log_section() {
    echo -e "\n${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${PURPLE}  $*${NC}" | tee -a "$LOG_FILE"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}\n" | tee -a "$LOG_FILE"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        log_error "Check the log file: $LOG_FILE"
        log_error "For debugging, run: kubectl get pods -n $NAMESPACE"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Print banner
print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║    ____        _    _      _        _     _        __  __  _       _          ║
║   |  _ \ _   _| |  | |    (_)      | |_  | |      |  \/  |(_)     (_)         ║
║   | |_) | | | | |  | |    | |      | __| | |      | |\/| | |      | |         ║
║   |  __/| |_| | |__| |    | |      | |_  | |      | |  | | |      | |         ║
║   |_|    \__, |\____/     |_|       \__| |_|      |_|  |_|_|      |_|         ║
║           __/ |                                                               ║
║          |___/   Deployment System                                            ║
║                                                                               ║
║  Comprehensive Minikube deployment with full automation                       ║
║  • Service orchestration • Health monitoring • Log aggregation               ║
║  • Secret management • Database initialization • Developer tools             ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# Check prerequisites
check_prerequisites() {
    log_section "CHECKING PREREQUISITES"
    
    local missing_tools=()
    
    # Check required tools
    for tool in kubectl minikube docker curl jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        else
            log_success "$tool is installed"
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install them before continuing"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Setup Minikube
setup_minikube() {
    log_section "SETTING UP MINIKUBE"
    
    # Check if profile exists
    if minikube profile list -o json 2>/dev/null | jq -r '.valid[].Name' | grep -q "^${MINIKUBE_PROFILE}$"; then
        log_info "Minikube profile '$MINIKUBE_PROFILE' already exists"
        
        # Check if running
        if minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
            log_info "Minikube is already running"
        else
            log_info "Starting existing Minikube profile"
            minikube start -p "$MINIKUBE_PROFILE"
        fi
    else
        log_info "Creating new Minikube profile with optimized settings"
        minikube start \
            --profile="$MINIKUBE_PROFILE" \
            --cpus="$REQUIRED_CPUS" \
            --memory="$REQUIRED_MEMORY" \
            --disk-size="$REQUIRED_DISK" \
            --driver=docker \
            --kubernetes-version=v1.28.3 \
            --feature-gates="EphemeralContainers=true" \
            --extra-config=kubelet.housekeeping-interval=10s \
            --extra-config=kubelet.max-pods=110 \
            --extra-config=controller-manager.horizontal-pod-autoscaler-upscale-delay=1m \
            --extra-config=controller-manager.horizontal-pod-autoscaler-downscale-delay=2m \
            --addons=ingress,dashboard,metrics-server,storage-provisioner,default-storageclass
    fi
    
    # Set kubectl context
    kubectl config use-context "$MINIKUBE_PROFILE"
    
    # Verify cluster is ready
    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    log_success "Minikube cluster is ready"
}

# Generate secure secrets
generate_secrets() {
    log_section "GENERATING SECURE SECRETS"
    
    # Create secrets directory
    mkdir -p "${SCRIPT_DIR}/.secrets"
    chmod 700 "${SCRIPT_DIR}/.secrets"
    
    local secrets_file="${SCRIPT_DIR}/.secrets/generated-secrets.env"
    
    if [[ -f "$secrets_file" ]]; then
        log_info "Using existing secrets file"
        source "$secrets_file"
    else
        log_info "Generating new secure secrets"
        
        # Generate random secrets
        local postgres_password jwt_secret redis_password api_key
        postgres_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        jwt_secret=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-32)
        redis_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        api_key=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        
        # Save to file
        cat > "$secrets_file" << EOF
# Generated secrets for PyAirtable deployment
# Generated on: $(date)
export POSTGRES_PASSWORD="$postgres_password"
export JWT_SECRET="$jwt_secret"
export REDIS_PASSWORD="$redis_password"
export API_KEY="$api_key"
export NEXTAUTH_SECRET="$jwt_secret"
EOF
        
        chmod 600 "$secrets_file"
        log_success "Generated new secrets"
    fi
    
    # Load secrets
    source "$secrets_file"
    
    # Ensure required environment variables
    export POSTGRES_DB="${POSTGRES_DB:-pyairtablemcp}"
    export POSTGRES_USER="${POSTGRES_USER:-admin}"
    export ENVIRONMENT="${ENVIRONMENT:-development}"
    export LOG_LEVEL="${LOG_LEVEL:-info}"
    export NODE_ENV="${NODE_ENV:-development}"
    
    # Validate required external secrets
    if [[ -z "${AIRTABLE_TOKEN:-}" ]]; then
        log_warning "AIRTABLE_TOKEN not set. Please set it in your environment or .env file"
    fi
    
    if [[ -z "${GEMINI_API_KEY:-}" ]]; then
        log_warning "GEMINI_API_KEY not set. Please set it in your environment or .env file"
    fi
    
    log_success "Secrets configured"
}

# Create Kubernetes resources
create_kubernetes_resources() {
    log_section "CREATING KUBERNETES RESOURCES"
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    log_success "Namespace created/updated"
    
    # Create secrets
    kubectl create secret generic pyairtable-secrets \
        --namespace="$NAMESPACE" \
        --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
        --from-literal=redis-password="${REDIS_PASSWORD}" \
        --from-literal=jwt-secret="${JWT_SECRET}" \
        --from-literal=airtable-token="${AIRTABLE_TOKEN:-placeholder}" \
        --from-literal=gemini-api-key="${GEMINI_API_KEY:-placeholder}" \
        --from-literal=api-key="${API_KEY}" \
        --from-literal=nextauth-secret="${NEXTAUTH_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Secrets created/updated"
    
    # Create ConfigMap for database initialization
    if [[ -f "${SCRIPT_DIR}/init-db.sql" ]]; then
        kubectl create configmap postgres-init-sql \
            --namespace="$NAMESPACE" \
            --from-file=init.sql="${SCRIPT_DIR}/init-db.sql" \
            --dry-run=client -o yaml | kubectl apply -f -
        log_success "Database initialization ConfigMap created"
    fi
}

# Deploy infrastructure services
deploy_infrastructure() {
    log_section "DEPLOYING INFRASTRUCTURE SERVICES"
    
    # Deploy PostgreSQL
    kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: $NAMESPACE
  labels:
    app: postgres
    component: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
        component: database
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: "$POSTGRES_DB"
        - name: POSTGRES_USER
          value: "$POSTGRES_USER"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: postgres-password
        - name: PGDATA
          value: "/var/lib/postgresql/data/pgdata"
        volumeMounts:
        - name: postgres-storage
          mountPath: "/var/lib/postgresql/data"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - "$POSTGRES_USER"
            - -d
            - "$POSTGRES_DB"
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - "$POSTGRES_USER"
            - -d
            - "$POSTGRES_DB"
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: $NAMESPACE
  labels:
    app: postgres
    component: database
spec:
  ports:
  - port: 5432
    targetPort: 5432
  selector:
    app: postgres
EOF
    
    # Deploy Redis
    kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: $NAMESPACE
  labels:
    app: redis
    component: cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        component: cache
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        command:
        - redis-server
        - --requirepass
        - "\$(REDIS_PASSWORD)"
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: redis-password
        volumeMounts:
        - name: redis-storage
          mountPath: "/data"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          exec:
            command:
            - redis-cli
            - -a
            - "\$(REDIS_PASSWORD)"
            - ping
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - redis-cli
            - -a
            - "\$(REDIS_PASSWORD)"
            - ping
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: redis-storage
        persistentVolumeClaim:
          claimName: redis-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: $NAMESPACE
  labels:
    app: redis
    component: cache
spec:
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    app: redis
EOF
    
    # Wait for infrastructure to be ready
    log_info "Waiting for infrastructure services to be ready..."
    kubectl wait --namespace="$NAMESPACE" --for=condition=available deployment/postgres --timeout="${TIMEOUT_READY}s"
    kubectl wait --namespace="$NAMESPACE" --for=condition=available deployment/redis --timeout="${TIMEOUT_READY}s"
    
    log_success "Infrastructure services deployed and ready"
}

# Simple validation check
run_validation() {
    log_section "RUNNING DEPLOYMENT VALIDATION"
    
    local failed_checks=0
    
    # Check all deployments are available
    log_info "Checking deployment status..."
    if ! kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].status.conditions[?(@.type=="Available")].status}' | grep -q "False"; then
        log_success "All deployments are available"
    else
        log_error "Some deployments are not available"
        kubectl get deployments -n "$NAMESPACE"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Check all pods are running
    log_info "Checking pod status..."
    local not_running_pods
    not_running_pods=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
    if [[ "$not_running_pods" -eq 0 ]]; then
        log_success "All pods are running"
    else
        log_error "$not_running_pods pods are not running"
        kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running
        failed_checks=$((failed_checks + 1))
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        log_success "All validation checks passed!"
        return 0
    else
        log_error "$failed_checks validation checks failed"
        return 1
    fi
}

# Print deployment summary
print_summary() {
    log_section "DEPLOYMENT SUMMARY"
    
    # Get service URLs
    local minikube_ip
    if command -v minikube &> /dev/null && minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
        minikube_ip=$(minikube ip -p "$MINIKUBE_PROFILE")
    else
        minikube_ip="localhost"
    fi
    
    echo -e "${GREEN}🎉 PyAirtable infrastructure deployment completed successfully!${NC}\n"
    
    echo -e "${CYAN}📋 Infrastructure Information:${NC}"
    echo -e "  🗄️  PostgreSQL:      Ready on port 5432"
    echo -e "  🔵 Redis:           Ready on port 6379"
    echo -e "  📊 Minikube IP:     ${minikube_ip}"
    echo
    
    echo -e "${CYAN}🛠  Management Commands:${NC}"
    echo -e "  View all pods:       kubectl get pods -n $NAMESPACE"
    echo -e "  View all services:   kubectl get services -n $NAMESPACE"
    echo -e "  View logs:          kubectl logs -n $NAMESPACE deployment/postgres"
    echo
    
    echo -e "${CYAN}🗂  File Locations:${NC}"
    echo -e "  Deployment log:     $LOG_FILE"
    echo -e "  Generated secrets:  ${SCRIPT_DIR}/.secrets/generated-secrets.env"
    echo
    
    echo -e "${GREEN}✅ Infrastructure deployment completed at $(date)${NC}"
    echo -e "${YELLOW}🔧 Next: Build and deploy application services${NC}"
}

# Main execution
main() {
    print_banner
    
    # Initialize log file
    echo "PyAirtable Minikube Deployment Log" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    
    # Execute deployment steps
    check_prerequisites
    setup_minikube
    generate_secrets
    create_kubernetes_resources
    deploy_infrastructure
    
    # Validation and summary
    if run_validation; then
        print_summary
        log_success "PyAirtable infrastructure deployment completed successfully!"
    else
        log_error "Deployment validation failed. Check the logs and fix issues."
        exit 1
    fi
}

# Execute main
main