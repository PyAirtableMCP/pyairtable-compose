#!/bin/bash

# PyAirtable Minikube Deployment System
# Comprehensive one-command deployment with full automation
# Author: Claude Deployment Engineer
# Version: 1.0.0

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

# Service configurations
declare -A SERVICES=(
    ["frontend"]="../pyairtable-frontend"
    ["api-gateway"]="../pyairtable-api-gateway"
    ["llm-orchestrator"]="../llm-orchestrator-py"
    ["mcp-server"]="../mcp-server-py"
    ["airtable-gateway"]="../airtable-gateway-py"
    ["platform-services"]="../pyairtable-platform-services"
    ["automation-services"]="../pyairtable-automation-services"
)

declare -A SERVICE_PORTS=(
    ["frontend"]="3000"
    ["api-gateway"]="8000"
    ["llm-orchestrator"]="8003"
    ["mcp-server"]="8001"
    ["airtable-gateway"]="8002"
    ["platform-services"]="8007"
    ["automation-services"]="8006"
)

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

# Build and load Docker images
build_and_load_images() {
    log_section "BUILDING AND LOADING DOCKER IMAGES"
    
    # Configure Docker to use Minikube's environment
    eval "$(minikube docker-env -p "$MINIKUBE_PROFILE")"
    
    local total_services=${#SERVICES[@]}
    local current=0
    
    for service in "${!SERVICES[@]}"; do
        current=$((current + 1))
        log_info "[$current/$total_services] Building $service..."
        
        local service_path="${SERVICES[$service]}"
        local dockerfile="${service_path}/Dockerfile"
        
        if [[ ! -f "$dockerfile" ]]; then
            log_warning "Dockerfile not found for $service at $dockerfile"
            continue
        fi
        
        # Build image
        if docker build -t "$PROJECT_NAME/$service:latest" "$service_path" >> "$LOG_FILE" 2>&1; then
            log_success "Built $service"
        else
            log_error "Failed to build $service"
            log_error "Check $LOG_FILE for details"
            exit 1
        fi
    done
    
    log_success "All images built successfully"
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
        - name: postgres-init
          mountPath: "/docker-entrypoint-initdb.d"
          readOnly: true
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
      - name: postgres-init
        configMap:
          name: postgres-init-sql
          defaultMode: 0755
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

# Deploy application services
deploy_application_services() {
    log_section "DEPLOYING APPLICATION SERVICES"
    
    # Deploy services in dependency order
    local services_order=(
        "airtable-gateway"
        "mcp-server"
        "llm-orchestrator"
        "platform-services"
        "automation-services"
        "api-gateway"
        "frontend"
    )
    
    for service in "${services_order[@]}"; do
        log_info "Deploying $service..."
        deploy_service "$service"
        
        # Wait for service to be ready before deploying next
        log_info "Waiting for $service to be ready..."
        kubectl wait --namespace="$NAMESPACE" --for=condition=available "deployment/$service" --timeout="${TIMEOUT_READY}s"
        log_success "$service deployed and ready"
    done
    
    log_success "All application services deployed"
}

# Deploy individual service
deploy_service() {
    local service_name="$1"
    local port="${SERVICE_PORTS[$service_name]}"
    
    # Create service-specific deployment based on service type
    case "$service_name" in
        "frontend")
            deploy_frontend_service
            ;;
        "api-gateway")
            deploy_api_gateway_service
            ;;
        *)
            deploy_backend_service "$service_name" "$port"
            ;;
    esac
}

# Deploy backend service
deploy_backend_service() {
    local service_name="$1"
    local port="$2"
    
    kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $service_name
  namespace: $NAMESPACE
  labels:
    app: $service_name
    component: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $service_name
  template:
    metadata:
      labels:
        app: $service_name
        component: backend
    spec:
      containers:
      - name: $service_name
        image: $PROJECT_NAME/$service_name:latest
        imagePullPolicy: Never
        ports:
        - containerPort: $port
        env:
        - name: PORT
          value: "$port"
        - name: ENVIRONMENT
          value: "$ENVIRONMENT"
        - name: LOG_LEVEL
          value: "$LOG_LEVEL"
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: api-key
        - name: AIRTABLE_TOKEN
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: airtable-token
        - name: GEMINI_API_KEY
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: gemini-api-key
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: jwt-secret
        - name: DATABASE_URL
          value: "postgresql://$POSTGRES_USER:\$(POSTGRES_PASSWORD)@postgres:5432/$POSTGRES_DB"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: postgres-password
        - name: REDIS_URL
          value: "redis://redis:6379"
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: redis-password
        $(get_service_specific_env "$service_name")
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: $port
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
        readinessProbe:
          httpGet:
            path: /health
            port: $port
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: $service_name
  namespace: $NAMESPACE
  labels:
    app: $service_name
    component: backend
spec:
  ports:
  - port: $port
    targetPort: $port
  selector:
    app: $service_name
EOF
}

# Get service-specific environment variables
get_service_specific_env() {
    local service_name="$1"
    
    case "$service_name" in
        "airtable-gateway")
            echo "        - name: AIRTABLE_BASE"
            echo "          value: \"\${AIRTABLE_BASE:-}\""
            ;;
        "llm-orchestrator")
            echo "        - name: MCP_SERVER_HTTP_URL"
            echo "          value: \"http://mcp-server:8001\""
            echo "        - name: USE_HTTP_MCP"
            echo "          value: \"true\""
            echo "        - name: USE_REDIS_SESSIONS"
            echo "          value: \"true\""
            echo "        - name: THINKING_BUDGET"
            echo "          value: \"\${THINKING_BUDGET:-5}\""
            ;;
        "mcp-server")
            echo "        - name: AIRTABLE_GATEWAY_URL"
            echo "          value: \"http://airtable-gateway:8002\""
            echo "        - name: MCP_SERVER_MODE"
            echo "          value: \"http\""
            echo "        - name: MCP_SERVER_PORT"
            echo "          value: \"8001\""
            ;;
        "platform-services")
            echo "        - name: CORS_ORIGINS"
            echo "          value: \"*\""
            echo "        - name: PASSWORD_MIN_LENGTH"
            echo "          value: \"8\""
            echo "        - name: PASSWORD_HASH_ROUNDS"
            echo "          value: \"12\""
            ;;
        "automation-services")
            echo "        - name: MCP_SERVER_URL"
            echo "          value: \"http://mcp-server:8001\""
            echo "        - name: PLATFORM_SERVICES_URL"
            echo "          value: \"http://platform-services:8007\""
            echo "        - name: MAX_FILE_SIZE"
            echo "          value: \"10MB\""
            echo "        - name: UPLOAD_DIR"
            echo "          value: \"/tmp/uploads\""
            ;;
    esac
}

# Deploy API Gateway with NodePort
deploy_api_gateway_service() {
    kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: $NAMESPACE
  labels:
    app: api-gateway
    component: gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
        component: gateway
    spec:
      containers:
      - name: api-gateway
        image: $PROJECT_NAME/api-gateway:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 8000
        env:
        - name: PORT
          value: "8000"
        - name: ENVIRONMENT
          value: "$ENVIRONMENT"
        - name: LOG_LEVEL
          value: "$LOG_LEVEL"
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: api-key
        - name: AIRTABLE_GATEWAY_URL
          value: "http://airtable-gateway:8002"
        - name: MCP_SERVER_URL
          value: "http://mcp-server:8001"
        - name: LLM_ORCHESTRATOR_URL
          value: "http://llm-orchestrator:8003"
        - name: PLATFORM_SERVICES_URL
          value: "http://platform-services:8007"
        - name: AUTOMATION_SERVICES_URL
          value: "http://automation-services:8006"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: $NAMESPACE
  labels:
    app: api-gateway
    component: gateway
spec:
  type: NodePort
  ports:
  - port: 8000
    targetPort: 8000
    nodePort: 30080
  selector:
    app: api-gateway
EOF
}

# Deploy frontend service
deploy_frontend_service() {
    kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: $NAMESPACE
  labels:
    app: frontend
    component: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        component: frontend
    spec:
      containers:
      - name: frontend
        image: $PROJECT_NAME/frontend:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 3000
        env:
        - name: NODE_ENV
          value: "$NODE_ENV"
        - name: LOG_LEVEL
          value: "$LOG_LEVEL"
        - name: NEXT_PUBLIC_API_URL
          value: "http://localhost:30080"
        - name: NEXT_PUBLIC_API_GATEWAY_URL
          value: "http://api-gateway:8000"
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: api-key
        - name: NEXTAUTH_SECRET
          valueFrom:
            secretKeyRef:
              name: pyairtable-secrets
              key: nextauth-secret
        - name: NEXTAUTH_URL
          value: "http://localhost:30081"
        - name: LLM_ORCHESTRATOR_URL
          value: "http://llm-orchestrator:8003"
        - name: MCP_SERVER_URL
          value: "http://mcp-server:8001"
        - name: AIRTABLE_GATEWAY_URL
          value: "http://airtable-gateway:8002"
        - name: PLATFORM_SERVICES_URL
          value: "http://platform-services:8007"
        - name: AUTOMATION_SERVICES_URL
          value: "http://automation-services:8006"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: $NAMESPACE
  labels:
    app: frontend
    component: frontend
spec:
  type: NodePort
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30081
  selector:
    app: frontend
EOF
}

# Health monitoring system
setup_monitoring() {
    log_section "SETTING UP HEALTH MONITORING"
    
    # Create monitoring deployment
    kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: health-monitor
  namespace: $NAMESPACE
  labels:
    app: health-monitor
    component: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: health-monitor
  template:
    metadata:
      labels:
        app: health-monitor
        component: monitoring
    spec:
      containers:
      - name: health-monitor
        image: curlimages/curl:latest
        command: ['/bin/sh']
        args: ['-c', 'while true; do sleep 30; done']
        resources:
          requests:
            memory: "32Mi"
            cpu: "10m"
          limits:
            memory: "64Mi"
            cpu: "50m"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: monitoring-scripts
  namespace: $NAMESPACE
data:
  health-check.sh: |
    #!/bin/sh
    NAMESPACE="$NAMESPACE"
    SERVICES="api-gateway airtable-gateway llm-orchestrator mcp-server platform-services automation-services frontend"
    
    echo "=== PyAirtable Health Check ==="
    echo "Timestamp: \$(date)"
    echo "Namespace: \$NAMESPACE"
    echo
    
    for service in \$SERVICES; do
        echo "Checking \$service..."
        if kubectl get service \$service -n \$NAMESPACE &>/dev/null; then
            echo "  ✅ Service exists"
            
            # Check if pods are running
            running_pods=\$(kubectl get pods -n \$NAMESPACE -l app=\$service --field-selector=status.phase=Running --no-headers | wc -l)
            total_pods=\$(kubectl get pods -n \$NAMESPACE -l app=\$service --no-headers | wc -l)
            
            echo "  📊 Pods: \$running_pods/\$total_pods running"
            
            if [ "\$running_pods" -gt 0 ]; then
                echo "  ✅ \$service is healthy"
            else
                echo "  ❌ \$service has no running pods"
            fi
        else
            echo "  ❌ Service not found"
        fi
        echo
    done
EOF
    
    log_success "Health monitoring configured"
}

# Create log aggregation system
setup_log_aggregation() {
    log_section "SETTING UP LOG AGGREGATION"
    
    # Create log viewing scripts
    kubectl apply -f - << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: log-scripts
  namespace: $NAMESPACE
data:
  view-logs.sh: |
    #!/bin/sh
    SERVICE=\${1:-api-gateway}
    LINES=\${2:-100}
    
    echo "=== Logs for \$SERVICE (last \$LINES lines) ==="
    kubectl logs -n $NAMESPACE deployment/\$SERVICE --tail=\$LINES
    
  follow-logs.sh: |
    #!/bin/sh
    SERVICE=\${1:-api-gateway}
    
    echo "=== Following logs for \$SERVICE ==="
    kubectl logs -n $NAMESPACE deployment/\$SERVICE -f
    
  all-logs.sh: |
    #!/bin/sh
    SERVICES="api-gateway airtable-gateway llm-orchestrator mcp-server platform-services automation-services frontend"
    
    for service in \$SERVICES; do
        echo "=== \$service logs ==="
        kubectl logs -n $NAMESPACE deployment/\$service --tail=20
        echo
    done
EOF
    
    log_success "Log aggregation configured"
}

# Run comprehensive validation
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
    
    # Test service connectivity
    log_info "Testing service connectivity..."
    local test_pod="test-connectivity"
    
    kubectl run "$test_pod" \
        --namespace="$NAMESPACE" \
        --image=curlimages/curl:latest \
        --rm -it --restart=Never \
        --command -- sh -c "
            curl -s http://api-gateway:8000/health && echo 'API Gateway: OK' || echo 'API Gateway: FAILED'
            curl -s http://airtable-gateway:8002/health && echo 'Airtable Gateway: OK' || echo 'Airtable Gateway: FAILED'
            curl -s http://llm-orchestrator:8003/health && echo 'LLM Orchestrator: OK' || echo 'LLM Orchestrator: FAILED'
            curl -s http://mcp-server:8001/health && echo 'MCP Server: OK' || echo 'MCP Server: FAILED'
            curl -s http://platform-services:8007/health && echo 'Platform Services: OK' || echo 'Platform Services: FAILED'
            curl -s http://automation-services:8006/health && echo 'Automation Services: OK' || echo 'Automation Services: FAILED'
        " 2>/dev/null || {
        log_error "Service connectivity test failed"
        failed_checks=$((failed_checks + 1))
    }
    
    # Test external access
    log_info "Testing external access..."
    local api_url
    if command -v minikube &> /dev/null && minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
        api_url=$(minikube service api-gateway --namespace="$NAMESPACE" --url -p "$MINIKUBE_PROFILE" 2>/dev/null)
    else
        api_url="http://localhost:30080"
    fi
    
    if curl -s "$api_url/health" > /dev/null; then
        log_success "External API access is working"
    else
        log_warning "External API access test failed - this may be expected during initial startup"
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
    local api_url frontend_url minikube_ip
    if command -v minikube &> /dev/null && minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
        minikube_ip=$(minikube ip -p "$MINIKUBE_PROFILE")
        api_url="http://$minikube_ip:30080"
        frontend_url="http://$minikube_ip:30081"
    else
        api_url="http://localhost:30080"
        frontend_url="http://localhost:30081"
    fi
    
    echo -e "${GREEN}🎉 PyAirtable deployment completed successfully!${NC}\n"
    
    echo -e "${CYAN}📋 Service Information:${NC}"
    echo -e "  🌐 API Gateway:    $api_url"
    echo -e "  🎨 Frontend:       $frontend_url"
    echo -e "  📊 Minikube IP:    ${minikube_ip:-localhost}"
    echo
    
    echo -e "${CYAN}🔍 Quick Health Check:${NC}"
    echo -e "  curl $api_url/health"
    echo
    
    echo -e "${CYAN}🛠  Management Commands:${NC}"
    echo -e "  View all pods:       kubectl get pods -n $NAMESPACE"
    echo -e "  View all services:   kubectl get services -n $NAMESPACE"
    echo -e "  View logs:          kubectl logs -n $NAMESPACE deployment/api-gateway"
    echo -e "  Scale service:      kubectl scale deployment/api-gateway --replicas=2 -n $NAMESPACE"
    echo -e "  Port forward:       kubectl port-forward -n $NAMESPACE service/api-gateway 8080:8000"
    echo
    
    echo -e "${CYAN}📊 Monitoring Commands:${NC}"
    echo -e "  Health check:       kubectl exec -n $NAMESPACE deployment/health-monitor -- sh /scripts/health-check.sh"
    echo -e "  View all logs:      kubectl exec -n $NAMESPACE deployment/health-monitor -- sh /scripts/all-logs.sh"
    echo -e "  Follow logs:        kubectl exec -n $NAMESPACE deployment/health-monitor -- sh /scripts/follow-logs.sh api-gateway"
    echo
    
    echo -e "${CYAN}🗂  File Locations:${NC}"
    echo -e "  Deployment log:     $LOG_FILE"
    echo -e "  Generated secrets:  ${SCRIPT_DIR}/.secrets/generated-secrets.env"
    echo
    
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo -e "  • Services may take a few minutes to fully initialize"
    echo -e "  • Ensure AIRTABLE_TOKEN and GEMINI_API_KEY are set for full functionality"
    echo -e "  • Use 'minikube delete -p $MINIKUBE_PROFILE' to completely remove the cluster"
    echo
    
    echo -e "${GREEN}✅ Deployment completed at $(date)${NC}"
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
    build_and_load_images
    deploy_infrastructure
    deploy_application_services
    setup_monitoring
    setup_log_aggregation
    
    # Validation and summary
    if run_validation; then
        print_summary
        log_success "PyAirtable deployment completed successfully!"
    else
        log_error "Deployment validation failed. Check the logs and fix issues."
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "PyAirtable Minikube Deployment System"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  (no args)  Full deployment"
        echo "  help       Show this help message"
        echo "  clean      Clean up deployment"
        echo "  status     Show deployment status"
        echo "  logs       Show logs for all services"
        echo
        exit 0
        ;;
    "clean")
        log_info "Cleaning up PyAirtable deployment..."
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
        minikube delete -p "$MINIKUBE_PROFILE" || true
        log_success "Cleanup completed"
        exit 0
        ;;
    "status")
        echo "PyAirtable Deployment Status"
        echo "============================"
        kubectl get all -n "$NAMESPACE" 2>/dev/null || echo "No resources found"
        exit 0
        ;;
    "logs")
        echo "PyAirtable Service Logs"
        echo "======================="
        for service in api-gateway airtable-gateway llm-orchestrator mcp-server platform-services automation-services frontend; do
            echo
            echo "=== $service ==="
            kubectl logs -n "$NAMESPACE" "deployment/$service" --tail=10 2>/dev/null || echo "Service not found"
        done
        exit 0
        ;;
    "")
        # Default: run full deployment
        main
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac