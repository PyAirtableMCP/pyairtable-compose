#!/bin/bash
set -e

echo "☸️  Setting up Minikube for Kubernetes development..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found. Please install Homebrew first:"
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

# Install kubectl if not present
if ! command -v kubectl &> /dev/null; then
    echo "📦 Installing kubectl..."
    brew install kubernetes-cli
    echo "✅ kubectl installed successfully!"
else
    echo "✅ kubectl is already installed"
    kubectl version --client
fi

# Install Minikube if not present
if ! command -v minikube &> /dev/null; then
    echo "📦 Installing Minikube..."
    brew install minikube
    echo "✅ Minikube installed successfully!"
else
    echo "✅ Minikube is already installed"
    minikube version
fi

# Check if Minikube is already running
if minikube status &> /dev/null; then
    echo "ℹ️  Minikube is already running:"
    minikube status
else
    echo "🚀 Starting Minikube cluster..."
    
    # Determine optimal driver
    if command -v docker &> /dev/null; then
        DRIVER="docker"
        echo "🐳 Using Docker driver (via Colima or Docker Desktop)"
    else
        DRIVER="hyperkit"  # For macOS
        echo "🖥️  Using HyperKit driver"
    fi
    
    # Start with optimized settings
    minikube start \
        --driver="$DRIVER" \
        --memory=8192 \
        --cpus=4 \
        --disk-size=20g \
        --kubernetes-version=stable \
        --addons=ingress,metrics-server,dashboard
    
    echo "✅ Minikube cluster started successfully!"
fi

# Enable essential addons
echo "🔧 Configuring essential addons..."
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard
minikube addons enable storage-provisioner

# Verify cluster
echo "🔍 Verifying Kubernetes cluster..."
kubectl cluster-info
kubectl get nodes

echo ""
echo "🎉 Minikube setup complete!"
echo "📊 Cluster status:"
minikube status

echo ""
echo "🔧 Useful Minikube commands:"
echo "   • Check status:           minikube status"
echo "   • Stop cluster:           minikube stop"
echo "   • Delete cluster:         minikube delete"
echo "   • Open dashboard:         minikube dashboard"
echo "   • Enable tunnel:          minikube tunnel (for LoadBalancer services)"
echo "   • SSH into cluster:       minikube ssh"
echo "   • View cluster IP:        minikube ip"
echo ""
echo "🔧 Useful kubectl commands:"
echo "   • Get pods:               kubectl get pods -A"
echo "   • Get services:           kubectl get services -A"
echo "   • View cluster info:      kubectl cluster-info"
echo "   • Apply manifests:        kubectl apply -f k8s/"
echo ""
echo "💡 To deploy PyAirtable to Minikube:"
echo "   1. Build local images:    eval \$(minikube docker-env) && docker build ..."
echo "   2. Apply manifests:       kubectl apply -f k8s/"
echo "   3. Port forward:          kubectl port-forward service/api-gateway 8000:8000"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"