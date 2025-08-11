#!/bin/bash
set -euo pipefail

# PyAirtable Chaos Engineering Local Environment Setup
# This script sets up a local development environment for chaos engineering

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAOS_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔧 Setting up PyAirtable Chaos Engineering Local Environment"
echo "📁 Chaos directory: $CHAOS_DIR"

# Check prerequisites
check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for required tools
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v minikube >/dev/null 2>&1 || missing_tools+=("minikube")
    command -v python3 >/dev/null 2>&1 || missing_tools+=("python3")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "❌ Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again."
        return 1
    fi
    
    echo "✅ All prerequisites satisfied"
    return 0
}

# Setup minikube for chaos engineering
setup_minikube() {
    echo "🚀 Setting up minikube for chaos engineering..."
    
    # Check if minikube is running
    if ! minikube status >/dev/null 2>&1; then
        echo "Starting minikube with chaos engineering optimizations..."
        minikube start \
            --cpus=4 \
            --memory=8192 \
            --disk-size=20gb \
            --kubernetes-version=v1.25.0 \
            --driver=docker \
            --addons=metrics-server,dashboard,ingress
    else
        echo "✅ Minikube is already running"
    fi
    
    # Enable necessary addons
    minikube addons enable metrics-server
    minikube addons enable dashboard
    
    echo "✅ Minikube setup completed"
}

# Create necessary namespaces
create_namespaces() {
    echo "📁 Creating Kubernetes namespaces..."
    
    local namespaces=("chaos-engineering" "pyairtable" "monitoring")
    
    for ns in "${namespaces[@]}"; do
        if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
            kubectl create namespace "$ns"
            echo "✅ Created namespace: $ns"
        else
            echo "✅ Namespace already exists: $ns"
        fi
    done
}

# Deploy mock PyAirtable services for testing
deploy_mock_services() {
    echo "🔄 Deploying mock PyAirtable services..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: pyairtable
  labels:
    app: api-gateway
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
        tier: frontend
    spec:
      containers:
      - name: api-gateway
        image: nginx:alpine
        ports:
        - containerPort: 80
        - containerPort: 8080
        command: ["/bin/sh"]
        args:
          - -c
          - |
            cat > /etc/nginx/conf.d/default.conf << 'EOL'
            server {
                listen 80;
                listen 8080;
                location /health {
                    access_log off;
                    return 200 "healthy\n";
                    add_header Content-Type text/plain;
                }
                location /api/test {
                    return 200 "api-gateway-test-response\n";
                    add_header Content-Type text/plain;
                }
                location / {
                    return 200 "PyAirtable API Gateway\n";
                    add_header Content-Type text/plain;
                }
            }
            EOL
            nginx -g 'daemon off;'
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: pyairtable
spec:
  selector:
    app: api-gateway
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  - name: nginx
    port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: pyairtable
  labels:
    app: auth-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
        tier: backend
    spec:
      containers:
      - name: auth-service
        image: nginx:alpine
        ports:
        - containerPort: 8081
        command: ["/bin/sh"]
        args:
          - -c
          - |
            cat > /etc/nginx/conf.d/default.conf << 'EOL'
            server {
                listen 8081;
                location /health {
                    access_log off;
                    return 200 "healthy\n";
                    add_header Content-Type text/plain;
                }
                location /auth {
                    return 200 "auth-service-response\n";
                    add_header Content-Type text/plain;
                }
                location / {
                    return 200 "PyAirtable Auth Service\n";
                    add_header Content-Type text/plain;
                }
            }
            EOL
            nginx -g 'daemon off;'
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: auth-service
  namespace: pyairtable
spec:
  selector:
    app: auth-service
  ports:
  - port: 8081
    targetPort: 8081
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: platform-services
  namespace: pyairtable
  labels:
    app: platform-services
spec:
  replicas: 2
  selector:
    matchLabels:
      app: platform-services
  template:
    metadata:
      labels:
        app: platform-services
        tier: backend
    spec:
      containers:
      - name: platform-services
        image: nginx:alpine
        ports:
        - containerPort: 8000
        command: ["/bin/sh"]
        args:
          - -c
          - |
            cat > /etc/nginx/conf.d/default.conf << 'EOL'
            server {
                listen 8000;
                location /health {
                    access_log off;
                    return 200 "healthy\n";
                    add_header Content-Type text/plain;
                }
                location /api {
                    return 200 "platform-services-response\n";
                    add_header Content-Type text/plain;
                }
                location / {
                    return 200 "PyAirtable Platform Services\n";
                    add_header Content-Type text/plain;
                }
            }
            EOL
            nginx -g 'daemon off;'
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: platform-services
  namespace: pyairtable
spec:
  selector:
    app: platform-services
  ports:
  - port: 8000
    targetPort: 8000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: pyairtable
  labels:
    app: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
        tier: database
    spec:
      containers:
      - name: postgres
        image: postgres:13
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: "pyairtable"
        - name: POSTGRES_USER
          value: "pyairtable"
        - name: POSTGRES_PASSWORD
          value: "password"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: pyairtable
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: pyairtable
  labels:
    app: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        tier: cache
    spec:
      containers:
      - name: redis
        image: redis:alpine
        ports:
        - containerPort: 6379
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: pyairtable
spec:
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
---
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: pyairtable
type: Opaque
data:
  password: cGFzc3dvcmQ=  # base64 encoded "password"
EOF

    echo "✅ Mock services deployed"
}

# Wait for services to be ready
wait_for_services() {
    echo "⏳ Waiting for services to be ready..."
    
    kubectl wait --for=condition=ready pod -l app=api-gateway -n pyairtable --timeout=300s
    kubectl wait --for=condition=ready pod -l app=auth-service -n pyairtable --timeout=300s
    kubectl wait --for=condition=ready pod -l app=platform-services -n pyairtable --timeout=300s
    kubectl wait --for=condition=ready pod -l app=postgres -n pyairtable --timeout=300s
    kubectl wait --for=condition=ready pod -l app=redis -n pyairtable --timeout=300s
    
    echo "✅ All services are ready"
}

# Install Chaos Mesh
install_chaos_mesh() {
    echo "📦 Installing Chaos Mesh..."
    
    cd "$CHAOS_DIR/chaos-mesh"
    
    if [ -f "install.sh" ]; then
        bash install.sh
    else
        echo "❌ install.sh not found in chaos-mesh directory"
        return 1
    fi
    
    echo "✅ Chaos Mesh installation completed"
}

# Setup monitoring
setup_monitoring() {
    echo "📊 Setting up monitoring..."
    
    # Apply monitoring configurations
    kubectl apply -f "$CHAOS_DIR/observability/chaos-monitoring.yaml"
    kubectl apply -f "$CHAOS_DIR/observability/grafana-dashboards.yaml"
    
    echo "⏳ Waiting for monitoring components to be ready..."
    kubectl wait --for=condition=ready pod -l app=chaos-prometheus -n chaos-engineering --timeout=300s
    kubectl wait --for=condition=ready pod -l app=chaos-grafana -n chaos-engineering --timeout=300s
    
    echo "✅ Monitoring setup completed"
}

# Setup CLI alias
setup_cli_alias() {
    echo "🔧 Setting up CLI alias..."
    
    local chaos_cli="$CHAOS_DIR/tools/chaos-cli.py"
    local alias_command="alias chaos='python3 $chaos_cli'"
    
    # Add alias to shell configuration files
    for config_file in ~/.bashrc ~/.zshrc ~/.bash_profile; do
        if [ -f "$config_file" ]; then
            if ! grep -q "alias chaos=" "$config_file"; then
                echo "$alias_command" >> "$config_file"
                echo "✅ Added chaos alias to $config_file"
            else
                echo "✅ Chaos alias already exists in $config_file"
            fi
        fi
    done
    
    echo "🔄 Reload your shell or run: source ~/.bashrc (or ~/.zshrc)"
    echo "Then you can use: chaos list, chaos run <experiment>, etc."
}

# Display access information
show_access_info() {
    echo ""
    echo "🎉 PyAirtable Chaos Engineering Environment Setup Complete!"
    echo "=" * 60
    echo ""
    echo "📋 Services Status:"
    kubectl get pods -n pyairtable -o wide
    echo ""
    echo "🔗 Access Information:"
    echo "  Kubernetes Dashboard: minikube dashboard"
    echo "  Chaos Dashboard: kubectl port-forward svc/chaos-dashboard 2333:2333 -n chaos-engineering"
    echo "  Grafana: kubectl port-forward svc/chaos-grafana 3000:3000 -n chaos-engineering"
    echo "  Prometheus: kubectl port-forward svc/chaos-prometheus 9090:9090 -n chaos-engineering"
    echo ""
    echo "🧪 Getting Started:"
    echo "  1. Test health: python3 $CHAOS_DIR/tools/chaos-cli.py health"
    echo "  2. List experiments: python3 $CHAOS_DIR/tools/chaos-cli.py list"
    echo "  3. Run first experiment: python3 $CHAOS_DIR/tools/chaos-cli.py run basic-pod-failure 2m --dry-run"
    echo ""
    echo "📚 Documentation:"
    echo "  Chaos Engineering Guide: $CHAOS_DIR/documentation/chaos-engineering-guide.md"
    echo "  Pod Failure Runbook: $CHAOS_DIR/documentation/runbook-pod-failures.md"
    echo ""
}

# Main execution
main() {
    echo "🚀 Starting PyAirtable Chaos Engineering Setup"
    
    # Run setup steps
    check_prerequisites || exit 1
    setup_minikube
    create_namespaces
    deploy_mock_services
    wait_for_services
    install_chaos_mesh
    setup_monitoring
    setup_cli_alias
    
    # Show final information
    show_access_info
    
    echo "✅ Setup completed successfully!"
}

# Handle script arguments
case "${1:-setup}" in
    "setup"|"install")
        main
        ;;
    "cleanup"|"uninstall")
        echo "🧹 Cleaning up chaos engineering environment..."
        kubectl delete namespace pyairtable chaos-engineering monitoring --ignore-not-found=true
        echo "✅ Cleanup completed"
        ;;
    "status")
        echo "📊 Environment Status:"
        kubectl get namespaces pyairtable chaos-engineering monitoring 2>/dev/null || echo "Namespaces not found"
        kubectl get pods -n pyairtable 2>/dev/null || echo "No PyAirtable pods found"
        kubectl get pods -n chaos-engineering 2>/dev/null || echo "No Chaos Engineering pods found"
        ;;
    "help"|"-h"|"--help")
        echo "PyAirtable Chaos Engineering Local Environment Setup"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  setup     - Setup the complete environment (default)"
        echo "  cleanup   - Remove all chaos engineering components"
        echo "  status    - Show current environment status"
        echo "  help      - Show this help message"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac