#!/bin/bash

# PyAirtable - Secure Kubernetes Secrets Deployment
# This script creates Kubernetes secrets from environment variables or GitHub Secrets

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="pyairtable"
SECRET_NAME="pyairtable-secrets"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

# Function to check required credentials
check_required_credentials() {
    local missing_creds=()
    local required_env_vars=(
        "PYAIRTABLE_API_KEY"
        "AIRTABLE_TOKEN"
        "AIRTABLE_BASE"
        "GEMINI_API_KEY"
        "JWT_SECRET"
        "NEXTAUTH_SECRET"
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
    )
    
    for var in "${required_env_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_creds+=("$var")
        fi
    done
    
    if [ ${#missing_creds[@]} -gt 0 ]; then
        print_error "Missing required environment variables:"
        for cred in "${missing_creds[@]}"; do
            echo "  - $cred"
        done
        echo ""
        print_info "Options to resolve:"
        echo "1. Run: ./scripts/setup-local-credentials.sh"
        echo "2. Set environment variables manually"
        echo "3. Source .env file: source .env"
        echo "4. Use GitHub CLI to fetch from secrets"
        return 1
    fi
    
    return 0
}

# Function to load environment from .env file
load_env_file() {
    local env_file="$PROJECT_ROOT/.env"
    
    if [ -f "$env_file" ]; then
        print_info "Loading environment from .env file..."
        # Export all variables from .env file
        set -a  # Automatically export all variables
        source "$env_file"
        set +a  # Stop automatically exporting
        print_status "Environment loaded from .env"
        return 0
    else
        print_warning ".env file not found at $env_file"
        return 1
    fi
}

# Function to create namespace if it doesn't exist
create_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
        print_status "Namespace created"
    else
        print_info "Namespace $NAMESPACE already exists"
    fi
}

# Function to delete existing secret
delete_existing_secret() {
    if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
        print_info "Deleting existing secret: $SECRET_NAME"
        kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
        print_status "Existing secret deleted"
    fi
}

# Function to create Kubernetes secret
create_kubernetes_secret() {
    print_info "Creating Kubernetes secret: $SECRET_NAME"
    
    # Create secret with all required credentials
    kubectl create secret generic "$SECRET_NAME" \
        --namespace="$NAMESPACE" \
        --from-literal=API_KEY="$PYAIRTABLE_API_KEY" \
        --from-literal=PYAIRTABLE_API_KEY="$PYAIRTABLE_API_KEY" \
        --from-literal=AIRTABLE_TOKEN="$AIRTABLE_TOKEN" \
        --from-literal=AIRTABLE_BASE="$AIRTABLE_BASE" \
        --from-literal=GEMINI_API_KEY="$GEMINI_API_KEY" \
        --from-literal=JWT_SECRET="$JWT_SECRET" \
        --from-literal=NEXTAUTH_SECRET="$NEXTAUTH_SECRET" \
        --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
        --from-literal=POSTGRES_USER="pyairtable" \
        --from-literal=POSTGRES_DB="pyairtable" \
        --from-literal=REDIS_DB="0"
    
    print_status "Kubernetes secret created successfully"
}

# Function to verify secret creation
verify_secret() {
    print_info "Verifying secret creation..."
    
    if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
        print_status "Secret exists in cluster"
        
        # Show secret keys (not values for security)
        print_info "Secret contains the following keys:"
        kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data}' | \
            jq -r 'keys[]' | sed 's/^/  - /'
        
        return 0
    else
        print_error "Secret verification failed"
        return 1
    fi
}

# Function to show deployment instructions
show_deployment_instructions() {
    echo ""
    echo -e "${GREEN}🎉 Kubernetes Secrets Deployed Successfully!${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Deploy the Helm chart:"
    echo "   helm install pyairtable ./k8s/helm/pyairtable-stack -n $NAMESPACE"
    echo ""
    echo "2. Or upgrade existing deployment:"
    echo "   helm upgrade pyairtable ./k8s/helm/pyairtable-stack -n $NAMESPACE"
    echo ""
    echo "3. Check pod status:"
    echo "   kubectl get pods -n $NAMESPACE"
    echo ""
    echo -e "${YELLOW}Security Notes:${NC}"
    echo "• Secrets are stored encrypted in etcd"
    echo "• Only authorized pods can access these secrets"
    echo "• Regularly rotate credentials for security"
    echo "• Monitor secret access via Kubernetes audit logs"
    echo ""
}

# Function to show troubleshooting info
show_troubleshooting() {
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo ""
    echo "View secret details (keys only):"
    echo "  kubectl describe secret $SECRET_NAME -n $NAMESPACE"
    echo ""
    echo "Delete and recreate secret:"
    echo "  kubectl delete secret $SECRET_NAME -n $NAMESPACE"
    echo "  $0"
    echo ""
    echo "View pods using the secret:"
    echo "  kubectl get pods -n $NAMESPACE -o yaml | grep -A 10 -B 10 $SECRET_NAME"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}🔐 PyAirtable Kubernetes Secrets Deployment${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo ""
    
    # Check prerequisites
    if ! command_exists kubectl; then
        print_error "kubectl is required but not installed"
        echo "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    
    if ! command_exists jq; then
        print_error "jq is required but not installed"
        echo "Install jq: https://stedolan.github.io/jq/download/"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        echo "Ensure kubectl is configured and cluster is accessible"
        exit 1
    fi
    
    print_status "Kubernetes cluster accessible"
    
    # Load environment variables
    if ! check_required_credentials; then
        # Try to load from .env file
        if load_env_file; then
            if ! check_required_credentials; then
                print_error "Required credentials still missing after loading .env"
                exit 1
            fi
        else
            print_error "Cannot proceed without required credentials"
            exit 1
        fi
    fi
    
    print_status "All required credentials available"
    
    # Create namespace
    create_namespace
    
    # Delete existing secret if it exists
    delete_existing_secret
    
    # Create new secret
    create_kubernetes_secret
    
    # Verify secret creation
    if verify_secret; then
        show_deployment_instructions
    else
        print_error "Secret deployment failed"
        show_troubleshooting
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --delete       Delete existing secrets only"
        echo "  --verify       Verify existing secrets only"
        echo ""
        echo "Environment Variables Required:"
        echo "  PYAIRTABLE_API_KEY     Internal service API key"
        echo "  AIRTABLE_TOKEN         Airtable Personal Access Token"
        echo "  AIRTABLE_BASE          Airtable Base ID"
        echo "  GEMINI_API_KEY         Google Gemini API key"
        echo "  JWT_SECRET             JWT signing secret"
        echo "  NEXTAUTH_SECRET        NextAuth session secret"
        echo "  POSTGRES_PASSWORD      PostgreSQL password"
        echo "  REDIS_PASSWORD         Redis password"
        echo ""
        echo "Examples:"
        echo "  $0                     Deploy secrets normally"
        echo "  source .env && $0      Load .env file and deploy"
        echo "  $0 --delete            Delete existing secrets"
        exit 0
        ;;
    --delete)
        create_namespace
        delete_existing_secret
        print_status "Secret deletion completed"
        exit 0
        ;;
    --verify)
        if verify_secret; then
            print_status "Secret verification passed"
            exit 0
        else
            print_error "Secret verification failed"
            exit 1
        fi
        ;;
esac

# Run main function
main "$@"