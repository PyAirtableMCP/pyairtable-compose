#!/bin/bash

# SSL Certificate Setup for Local Development
# Creates self-signed certificates for HTTPS in local environment

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Certificate configuration
CERT_DIR="nginx/certs"
DOMAINS=("pyairtable.local" "monitoring.local" "api.pyairtable.local")
KEY_SIZE=2048
DAYS_VALID=365

# Create certificate directory
mkdir -p "$CERT_DIR"

# Generate CA private key
print_status "Generating Certificate Authority (CA) private key..."
openssl genrsa -out "$CERT_DIR/ca-key.pem" 4096

# Generate CA certificate
print_status "Generating CA certificate..."
openssl req -new -x509 -days $DAYS_VALID -key "$CERT_DIR/ca-key.pem" \
    -sha256 -out "$CERT_DIR/ca.pem" -subj \
    "/C=US/ST=Development/L=Local/O=PyAirtable Dev/OU=Development/CN=PyAirtable Local CA"

# Generate server private key
print_status "Generating server private key..."
openssl genrsa -out "$CERT_DIR/server-key.pem" $KEY_SIZE

# Generate certificate signing request
print_status "Generating certificate signing request..."
openssl req -subj "/C=US/ST=Development/L=Local/O=PyAirtable Dev/OU=Development/CN=pyairtable.local" \
    -sha256 -new -key "$CERT_DIR/server-key.pem" -out "$CERT_DIR/server.csr"

# Create extensions file for SAN (Subject Alternative Names)
print_status "Creating certificate extensions..."
cat > "$CERT_DIR/server-extfile.cnf" <<EOF
subjectAltName = DNS:pyairtable.local,DNS:monitoring.local,DNS:api.pyairtable.local,DNS:localhost,IP:127.0.0.1
extendedKeyUsage = serverAuth
EOF

# Generate server certificate signed by CA
print_status "Generating server certificate..."
openssl x509 -req -days $DAYS_VALID -sha256 -in "$CERT_DIR/server.csr" \
    -CA "$CERT_DIR/ca.pem" -CAkey "$CERT_DIR/ca-key.pem" -out "$CERT_DIR/server.pem" \
    -extfile "$CERT_DIR/server-extfile.cnf" -CAcreateserial

# Set appropriate permissions
chmod 400 "$CERT_DIR/ca-key.pem" "$CERT_DIR/server-key.pem"
chmod 444 "$CERT_DIR/ca.pem" "$CERT_DIR/server.pem"

# Clean up temporary files
rm "$CERT_DIR/server.csr" "$CERT_DIR/server-extfile.cnf"

print_success "SSL certificates generated successfully!"

echo
print_status "Certificate Information:"
echo "  CA Certificate: $CERT_DIR/ca.pem"
echo "  Server Certificate: $CERT_DIR/server.pem"
echo "  Server Private Key: $CERT_DIR/server-key.pem"

echo
print_warning "To avoid browser security warnings:"
echo "  1. Add CA certificate to macOS Keychain:"
echo "     sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $PWD/$CERT_DIR/ca.pem"
echo "  2. Or manually import $PWD/$CERT_DIR/ca.pem into your browser"

echo
print_status "Verifying certificate..."
openssl x509 -in "$CERT_DIR/server.pem" -text -noout | grep -A 1 "Subject Alternative Name"

print_success "SSL setup complete!"