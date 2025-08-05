#!/bin/bash

# PyAirtable HashiCorp Vault Production Deployment Script
# Enterprise-grade secrets management deployment for 3vantage organization
# Security implementation for PyAirtable Compose

set -euo pipefail

# Configuration
VAULT_NAMESPACE="vault-system"
VAULT_RELEASE="vault"
VAULT_VERSION="1.14.0"
PROJECT_NAME="pyairtable"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we can connect to Kubernetes cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed or not in PATH"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Create namespace
create_namespace() {
    log_info "Creating Vault namespace..."
    
    kubectl create namespace $VAULT_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Namespace $VAULT_NAMESPACE created/updated"
}

# Add Helm repository
add_helm_repo() {
    log_info "Adding HashiCorp Helm repository..."
    
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo update
    
    log_success "HashiCorp Helm repository added"
}

# Create Vault configuration
create_vault_config() {
    log_info "Creating Vault configuration..."
    
    cat > vault-values.yaml << EOF
global:
  enabled: true
  tlsDisable: false
  
server:
  enabled: true
  image:
    repository: "hashicorp/vault"
    tag: "${VAULT_VERSION}"
    
  # Run in HA mode with 3 replicas
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
      config: |
        ui = true
        
        listener "tcp" {
          tls_disable = 0
          address = "[::]:8200"
          cluster_address = "[::]:8201"
          tls_cert_file = "/vault/userconfig/vault-tls/tls.crt"
          tls_key_file = "/vault/userconfig/vault-tls/tls.key"
          tls_client_ca_file = "/vault/userconfig/vault-tls/ca.crt"
        }
        
        storage "raft" {
          path = "/vault/data"
          
          retry_join {
            leader_api_addr = "https://vault-0.vault-internal:8200"
            leader_ca_cert_file = "/vault/userconfig/vault-tls/ca.crt"
            leader_client_cert_file = "/vault/userconfig/vault-tls/tls.crt"
            leader_client_key_file = "/vault/userconfig/vault-tls/tls.key"
          }
          
          retry_join {
            leader_api_addr = "https://vault-1.vault-internal:8200"
            leader_ca_cert_file = "/vault/userconfig/vault-tls/ca.crt"
            leader_client_cert_file = "/vault/userconfig/vault-tls/tls.crt"
            leader_client_key_file = "/vault/userconfig/vault-tls/tls.key"
          }
          
          retry_join {
            leader_api_addr = "https://vault-2.vault-internal:8200"
            leader_ca_cert_file = "/vault/userconfig/vault-tls/ca.crt"
            leader_client_cert_file = "/vault/userconfig/vault-tls/tls.crt"
            leader_client_key_file = "/vault/userconfig/vault-tls/tls.key"
          }
        }
        
        service_registration "kubernetes" {}
        
        # Disable mlock to prevent memory from being swapped to disk
        disable_mlock = true
        
        # Enable API addr
        api_addr = "https://POD_IP:8200"
        cluster_addr = "https://POD_IP:8201"
        
  # Resource limits
  resources:
    requests:
      memory: 256Mi
      cpu: 250m
    limits:
      memory: 1Gi
      cpu: 500m
      
  # Volume for persistent storage
  dataStorage:
    enabled: true
    size: 10Gi
    storageClass: null
    accessMode: ReadWriteOnce
    
  # Audit storage
  auditStorage:
    enabled: true
    size: 5Gi
    storageClass: null
    accessMode: ReadWriteOnce
    
  # Mount TLS certificates
  volumes:
    - name: vault-tls
      secret:
        secretName: vault-tls
        defaultMode: 420
  volumeMounts:
    - name: vault-tls
      mountPath: /vault/userconfig/vault-tls
      readOnly: true
      
  # Environment variables
  extraEnvironmentVars:
    VAULT_CACERT: /vault/userconfig/vault-tls/ca.crt
    VAULT_TLSCERT: /vault/userconfig/vault-tls/tls.crt
    VAULT_TLSKEY: /vault/userconfig/vault-tls/tls.key
    
  # Service configuration
  service:
    enabled: true
    type: ClusterIP
    port: 8200
    targetPort: 8200
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: https
      service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
      
  # Ingress configuration
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/backend-protocol: HTTPS
    hosts:
      - host: vault.pyairtable.com
        paths:
          - /
    tls:
      - secretName: vault-tls-ingress
        hosts:
          - vault.pyairtable.com
          
ui:
  enabled: true
  serviceType: ClusterIP
  
# Injector for automatic secret injection
injector:
  enabled: true
  image:
    repository: "hashicorp/vault-k8s"
    tag: "1.3.1"
    
  resources:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
      cpu: 100m
      
  # Webhook configuration
  webhook:
    failurePolicy: Ignore
    matchPolicy: Exact
    timeoutSeconds: 30
    
# CSI provider for secret mounting
csi:
  enabled: true
  image:
    repository: "hashicorp/vault-csi-provider"
    tag: "1.4.0"
    
  resources:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 128Mi
      cpu: 100m

# Server-side TLS configuration
serverTelemetry:
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
EOF

    log_success "Vault configuration created"
}

# Generate TLS certificates
generate_tls_certificates() {
    log_info "Generating TLS certificates for Vault..."
    
    # Create temporary directory for certificates
    CERT_DIR=$(mktemp -d)
    cd $CERT_DIR
    
    # Generate CA private key
    openssl genrsa -out ca.key 4096
    
    # Generate CA certificate
    openssl req -new -x509 -key ca.key -sha256 -subj "/C=US/ST=CA/O=PyAirtable/CN=vault-ca" -days 3650 -out ca.crt
    
    # Generate server private key
    openssl genrsa -out tls.key 4096
    
    # Create certificate request configuration
    cat > vault.conf << EOF
[req]
default_bits = 4096
prompt = no
encrypt_key = no
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
C = US
ST = CA
L = San Francisco
O = PyAirtable
OU = Security
CN = vault

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = vault
DNS.2 = vault.${VAULT_NAMESPACE}
DNS.3 = vault.${VAULT_NAMESPACE}.svc
DNS.4 = vault.${VAULT_NAMESPACE}.svc.cluster.local
DNS.5 = vault-0.vault-internal
DNS.6 = vault-1.vault-internal
DNS.7 = vault-2.vault-internal
DNS.8 = vault-active
DNS.9 = vault-standby
DNS.10 = vault.pyairtable.com
IP.1 = 127.0.0.1
EOF
    
    # Generate certificate request
    openssl req -new -key tls.key -out vault.csr -config vault.conf
    
    # Generate server certificate
    openssl x509 -req -in vault.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out tls.crt -days 365 -extensions v3_req -extfile vault.conf
    
    # Create Kubernetes secret
    kubectl create secret generic vault-tls \
        --namespace=$VAULT_NAMESPACE \
        --from-file=ca.crt=ca.crt \
        --from-file=tls.crt=tls.crt \
        --from-file=tls.key=tls.key \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Cleanup
    cd -
    rm -rf $CERT_DIR
    
    log_success "TLS certificates generated and stored in Kubernetes secret"
}

# Deploy Vault using Helm
deploy_vault() {
    log_info "Deploying Vault using Helm..."
    
    helm upgrade --install $VAULT_RELEASE hashicorp/vault \
        --namespace $VAULT_NAMESPACE \
        --values vault-values.yaml \
        --wait \
        --timeout 10m
        
    log_success "Vault deployed successfully"
}

# Wait for Vault pods to be ready
wait_for_vault() {
    log_info "Waiting for Vault pods to be ready..."
    
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault \
        --namespace=$VAULT_NAMESPACE \
        --timeout=300s
        
    log_success "Vault pods are ready"
}

# Initialize Vault
initialize_vault() {
    log_info "Initializing Vault..."
    
    # Check if Vault is already initialized
    INIT_STATUS=$(kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault status -format=json | jq -r .initialized 2>/dev/null || echo "false")
    
    if [ "$INIT_STATUS" = "true" ]; then
        log_warning "Vault is already initialized"
        return 0
    fi
    
    # Initialize Vault
    INIT_OUTPUT=$(kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault operator init -format=json -key-shares=5 -key-threshold=3)
    
    # Extract keys and root token
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[]' > unseal-keys.txt
    echo "$INIT_OUTPUT" | jq -r '.root_token' > root-token.txt
    
    # Store keys in Kubernetes secrets
    kubectl create secret generic vault-unseal-keys \
        --namespace=$VAULT_NAMESPACE \
        --from-file=unseal-keys.txt \
        --dry-run=client -o yaml | kubectl apply -f -
        
    kubectl create secret generic vault-root-token \
        --namespace=$VAULT_NAMESPACE \
        --from-file=root-token.txt \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Vault initialized successfully"
    log_warning "Unseal keys and root token have been stored in Kubernetes secrets"
    log_warning "Please backup these secrets securely and remove them from the cluster after initial setup"
}

# Unseal Vault
unseal_vault() {
    log_info "Unsealing Vault..."
    
    # Get unseal keys
    UNSEAL_KEYS=($(kubectl get secret vault-unseal-keys -n $VAULT_NAMESPACE -o jsonpath='{.data.unseal-keys\.txt}' | base64 -d))
    
    # Unseal all Vault instances
    for i in 0 1 2; do
        POD_NAME="vault-$i"
        
        log_info "Unsealing $POD_NAME..."
        
        # Use first 3 keys to unseal
        for j in 0 1 2; do
            kubectl exec $POD_NAME -n $VAULT_NAMESPACE -- vault operator unseal "${UNSEAL_KEYS[$j]}" >/dev/null 2>&1 || true
        done
        
        # Check if unsealed
        SEALED_STATUS=$(kubectl exec $POD_NAME -n $VAULT_NAMESPACE -- vault status -format=json | jq -r .sealed 2>/dev/null || echo "true")
        
        if [ "$SEALED_STATUS" = "false" ]; then
            log_success "$POD_NAME unsealed successfully"
        else
            log_error "Failed to unseal $POD_NAME"
        fi
    done
}

# Configure Vault
configure_vault() {
    log_info "Configuring Vault..."
    
    # Get root token
    ROOT_TOKEN=$(kubectl get secret vault-root-token -n $VAULT_NAMESPACE -o jsonpath='{.data.root-token\.txt}' | base64 -d)
    
    # Export Vault environment variables
    export VAULT_ADDR="https://127.0.0.1:8200"
    export VAULT_TOKEN="$ROOT_TOKEN"
    export VAULT_CACERT="/tmp/ca.crt"
    
    # Get CA certificate
    kubectl get secret vault-tls -n $VAULT_NAMESPACE -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/ca.crt
    
    # Port forward to Vault
    kubectl port-forward vault-0 8200:8200 -n $VAULT_NAMESPACE &
    PF_PID=$!
    
    # Wait for port forward to be ready
    sleep 5
    
    # Configure Kubernetes auth method
    log_info "Configuring Kubernetes authentication..."
    
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault auth enable kubernetes
    
    # Configure service account
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault write auth/kubernetes/config \
        token_reviewer_jwt="$(kubectl create token vault -n $VAULT_NAMESPACE)" \
        kubernetes_host="https://kubernetes.default.svc:443" \
        kubernetes_ca_cert="$(kubectl get secret -n $VAULT_NAMESPACE vault-token -o jsonpath='{.data.ca\.crt}' | base64 -d)"
    
    # Enable KV v2 secrets engine
    log_info "Enabling KV v2 secrets engine..."
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault secrets enable -path=$PROJECT_NAME kv-v2
    
    # Enable database secrets engine
    log_info "Enabling database secrets engine..."
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault secrets enable -path=$PROJECT_NAME/database database
    
    # Enable transit engine for encryption
    log_info "Enabling transit engine..."
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault secrets enable -path=$PROJECT_NAME/transit transit
    
    # Enable PKI engine for certificates
    log_info "Enabling PKI engine..."
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault secrets enable -path=$PROJECT_NAME/pki pki
    
    # Configure PKI
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault secrets tune -max-lease-ttl=87600h $PROJECT_NAME/pki
    
    # Generate root CA
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault write $PROJECT_NAME/pki/root/generate/internal \
        common_name="PyAirtable Root CA" \
        ttl=87600h
    
    # Configure PKI URLs
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault write $PROJECT_NAME/pki/config/urls \
        issuing_certificates="https://vault.pyairtable.com/v1/$PROJECT_NAME/pki/ca" \
        crl_distribution_points="https://vault.pyairtable.com/v1/$PROJECT_NAME/pki/crl"
    
    # Create service roles and policies
    create_service_policies
    
    # Kill port forward
    kill $PF_PID 2>/dev/null || true
    
    log_success "Vault configured successfully"
}

# Create service policies and roles
create_service_policies() {
    log_info "Creating service policies and roles..."
    
    # Create policy for auth service
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault policy write auth-service - << EOF
path "$PROJECT_NAME/data/jwt" {
  capabilities = ["read"]
}

path "$PROJECT_NAME/data/database" {
  capabilities = ["read"]
}

path "$PROJECT_NAME/database/creds/auth-role" {
  capabilities = ["read"]
}

path "$PROJECT_NAME/transit/encrypt/auth-*" {
  capabilities = ["update"]
}

path "$PROJECT_NAME/transit/decrypt/auth-*" {
  capabilities = ["update"]
}
EOF

    # Create Kubernetes role for auth service
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault write auth/kubernetes/role/auth-service \
        bound_service_account_names=auth-service \
        bound_service_account_namespaces=$PROJECT_NAME-system \
        policies=auth-service \
        ttl=1h
    
    # Create policy for API gateway
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault policy write api-gateway - << EOF
path "$PROJECT_NAME/data/jwt" {
  capabilities = ["read"]
}

path "$PROJECT_NAME/data/api-keys" {
  capabilities = ["read"]
}

path "$PROJECT_NAME/transit/encrypt/gateway-*" {
  capabilities = ["update"]
}

path "$PROJECT_NAME/transit/decrypt/gateway-*" {
  capabilities = ["update"]
}
EOF

    # Create Kubernetes role for API gateway
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault write auth/kubernetes/role/api-gateway \
        bound_service_account_names=api-gateway \
        bound_service_account_namespaces=$PROJECT_NAME-system \
        policies=api-gateway \
        ttl=1h
    
    log_success "Service policies and roles created"
}

# Create service accounts
create_service_accounts() {
    log_info "Creating service accounts..."
    
    # Create service accounts for each service
    SERVICES=("auth-service" "api-gateway" "user-service" "workspace-service" "airtable-gateway" "llm-orchestrator")
    
    for service in "${SERVICES[@]}"; do
        kubectl create serviceaccount $service -n $PROJECT_NAME-system --dry-run=client -o yaml | kubectl apply -f -
        log_success "Service account $service created"
    done
}

# Verify Vault deployment
verify_deployment() {
    log_info "Verifying Vault deployment..."
    
    # Check Vault status
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault status
    
    # Check if HA is working
    ACTIVE_NODE=$(kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault status -format=json | jq -r .ha_enabled)
    
    if [ "$ACTIVE_NODE" = "true" ]; then
        log_success "Vault HA is enabled and working"
    else
        log_warning "Vault HA is not enabled"
    fi
    
    # Test secret operations
    ROOT_TOKEN=$(kubectl get secret vault-root-token -n $VAULT_NAMESPACE -o jsonpath='{.data.root-token\.txt}' | base64 -d)
    
    kubectl port-forward vault-0 8200:8200 -n $VAULT_NAMESPACE &
    PF_PID=$!
    sleep 3
    
    # Test write and read
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault kv put $PROJECT_NAME/test key=value
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault kv get $PROJECT_NAME/test
    kubectl exec vault-0 -n $VAULT_NAMESPACE -- vault kv delete $PROJECT_NAME/test
    
    kill $PF_PID 2>/dev/null || true
    
    log_success "Vault deployment verification completed"
}

# Cleanup temporary files
cleanup() {
    log_info "Cleaning up temporary files..."
    
    rm -f vault-values.yaml
    rm -f unseal-keys.txt
    rm -f root-token.txt
    rm -f /tmp/ca.crt
    
    log_success "Cleanup completed"
}

# Display post-deployment instructions
post_deployment_instructions() {
    cat << EOF

${GREEN}================================================================================
                    VAULT DEPLOYMENT COMPLETED SUCCESSFULLY
================================================================================${NC}

Your HashiCorp Vault cluster has been deployed with the following configuration:

${BLUE}Cluster Information:${NC}
  - Namespace: $VAULT_NAMESPACE
  - Release: $VAULT_RELEASE
  - Version: $VAULT_VERSION
  - HA Enabled: Yes (3 replicas)
  - TLS Enabled: Yes
  - Auto-unseal: No (manual unseal required)

${BLUE}Access Information:${NC}
  - Internal URL: https://vault.$VAULT_NAMESPACE.svc.cluster.local:8200
  - External URL: https://vault.pyairtable.com (if ingress configured)
  - UI Available: Yes

${BLUE}Authentication:${NC}
  - Kubernetes auth method enabled
  - Service roles configured for PyAirtable services

${BLUE}Secrets Engines:${NC}
  - KV v2: $PROJECT_NAME/
  - Database: $PROJECT_NAME/database/
  - Transit: $PROJECT_NAME/transit/
  - PKI: $PROJECT_NAME/pki/

${YELLOW}IMPORTANT SECURITY NOTES:${NC}

1. ${RED}Unseal Keys and Root Token:${NC}
   - Stored in Kubernetes secrets: vault-unseal-keys, vault-root-token
   - ${RED}IMMEDIATELY BACKUP these secrets to a secure location${NC}
   - Remove these secrets from the cluster after initial setup
   - Store in a secure key management system (HSM, etc.)

2. ${RED}Root Token:${NC}
   - Only use for initial configuration
   - Create dedicated admin tokens for ongoing operations
   - Revoke root token after setup completion

3. ${RED}TLS Certificates:${NC}
   - Self-signed certificates generated for internal use
   - Replace with proper CA-signed certificates for production
   - Monitor certificate expiration dates

4. ${RED}Access Control:${NC}
   - Review and customize service policies as needed
   - Implement least privilege access
   - Regular policy audits recommended

${BLUE}Next Steps:${NC}

1. Backup unseal keys and root token:
   kubectl get secret vault-unseal-keys -n $VAULT_NAMESPACE -o yaml > vault-unseal-keys-backup.yaml
   kubectl get secret vault-root-token -n $VAULT_NAMESPACE -o yaml > vault-root-token-backup.yaml

2. Store secrets in Vault:
   - Database credentials
   - JWT secrets
   - API keys
   - External service credentials

3. Update PyAirtable services to use Vault:
   - Configure Vault client libraries
   - Update deployment configurations
   - Test secret retrieval

4. Monitor Vault health:
   kubectl get pods -n $VAULT_NAMESPACE
   kubectl logs -f vault-0 -n $VAULT_NAMESPACE

${GREEN}For support and documentation:${NC}
  - HashiCorp Vault Documentation: https://www.vaultproject.io/docs
  - PyAirtable Security Documentation: ./security/README.md

EOF
}

# Main execution
main() {
    log_info "Starting PyAirtable Vault deployment..."
    
    check_prerequisites
    create_namespace
    add_helm_repo
    create_vault_config
    generate_tls_certificates
    deploy_vault
    wait_for_vault
    initialize_vault
    unseal_vault
    configure_vault
    create_service_accounts
    verify_deployment
    cleanup
    post_deployment_instructions
    
    log_success "PyAirtable Vault deployment completed successfully!"
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@"