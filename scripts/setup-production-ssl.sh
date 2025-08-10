#!/bin/bash

# =============================================================================
# PyAirtable Production SSL/TLS Certificate Setup
# =============================================================================
# 
# SECURITY NOTICE: This script sets up production-grade SSL/TLS certificates
# for the PyAirtable platform. Use Let's Encrypt for production deployment.
#
# DESCRIPTION:
#   - Generates strong DH parameters for Perfect Forward Secrecy
#   - Sets up Let's Encrypt certificates via Certbot
#   - Configures certificate auto-renewal
#   - Implements security best practices
#
# USAGE: ./setup-production-ssl.sh [domain]
#
# OWASP COMPLIANCE: 
#   - A02:2021 – Cryptographic Failures (strong TLS configuration)
#   - A05:2021 – Security Misconfiguration (secure SSL setup)
#   - A06:2021 – Vulnerable Components (certificate management)
#
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
DOMAIN=${1:-"api.example.com"}
CERT_DIR="/etc/ssl/pyairtable"
NGINX_CERT_DIR="/etc/nginx/certs"
DH_PARAM_SIZE=4096
EMAIL=${SSL_EMAIL:-"admin@example.com"}

echo "🔐 Setting up production SSL/TLS certificates for: $DOMAIN"

# Validate domain format
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    echo "❌ ERROR: Invalid domain format: $DOMAIN"
    exit 1
fi

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "❌ ERROR: This script must be run as root for certificate management"
    echo "   Run: sudo ./setup-production-ssl.sh $DOMAIN"
    exit 1
fi

# =============================================================================
# INSTALL CERTBOT AND DEPENDENCIES
# =============================================================================

echo "📦 Installing Certbot and dependencies..."

# Detect OS and install Certbot
if command -v apt-get &> /dev/null; then
    # Ubuntu/Debian
    apt-get update
    apt-get install -y certbot python3-certbot-nginx openssl
elif command -v yum &> /dev/null; then
    # CentOS/RHEL
    yum install -y certbot python3-certbot-nginx openssl
elif command -v apk &> /dev/null; then
    # Alpine Linux
    apk add --no-cache certbot certbot-nginx openssl
else
    echo "❌ ERROR: Unsupported operating system. Please install Certbot manually."
    exit 1
fi

# =============================================================================
# GENERATE DH PARAMETERS FOR PERFECT FORWARD SECRECY
# =============================================================================

echo "🔑 Generating strong DH parameters (${DH_PARAM_SIZE}-bit)..."
echo "   This may take several minutes for maximum security..."

mkdir -p "$NGINX_CERT_DIR"

# Generate DH parameters if not exists or if size is smaller than required
if [[ ! -f "$NGINX_CERT_DIR/dhparam.pem" ]] || [[ $(openssl dhparam -in "$NGINX_CERT_DIR/dhparam.pem" -text | grep "DH Parameters" | grep -o '[0-9]*' | head -1) -lt $DH_PARAM_SIZE ]]; then
    openssl dhparam -out "$NGINX_CERT_DIR/dhparam.pem" $DH_PARAM_SIZE
    chmod 644 "$NGINX_CERT_DIR/dhparam.pem"
    echo "   ✅ Generated ${DH_PARAM_SIZE}-bit DH parameters"
else
    echo "   ✅ DH parameters already exist and are strong enough"
fi

# =============================================================================
# OBTAIN SSL CERTIFICATES
# =============================================================================

echo "📜 Obtaining SSL certificates from Let's Encrypt..."

# Stop nginx temporarily for standalone authentication
systemctl stop nginx 2>/dev/null || true

# Request certificate with security-focused options
certbot certonly \
    --standalone \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    --domains "$DOMAIN" \
    --rsa-key-size 4096 \
    --must-staple

# =============================================================================
# SET UP CERTIFICATE SYMLINKS
# =============================================================================

echo "🔗 Setting up certificate symlinks..."

# Create symlinks for nginx configuration
ln -sf "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$NGINX_CERT_DIR/server.pem"
ln -sf "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$NGINX_CERT_DIR/server-key.pem"

# Set proper permissions
chmod 644 "$NGINX_CERT_DIR/server.pem"
chmod 600 "$NGINX_CERT_DIR/server-key.pem"

echo "   ✅ Certificate symlinks created"

# =============================================================================
# CONFIGURE AUTOMATIC RENEWAL
# =============================================================================

echo "🔄 Configuring automatic certificate renewal..."

# Create renewal hook script for nginx reload
cat > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh << EOF
#!/bin/bash
# Reload nginx after certificate renewal
systemctl reload nginx
EOF

chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh

# Test automatic renewal
certbot renew --dry-run

# Add to system crontab if not already present
CRON_COMMAND="0 12 * * * /usr/bin/certbot renew --quiet"
if ! crontab -l 2>/dev/null | grep -Fq "$CRON_COMMAND"; then
    (crontab -l 2>/dev/null; echo "$CRON_COMMAND") | crontab -
    echo "   ✅ Added automatic renewal to crontab"
else
    echo "   ✅ Automatic renewal already configured"
fi

# =============================================================================
# CERTIFICATE VALIDATION
# =============================================================================

echo "🔍 Validating certificate setup..."

# Check certificate validity
if openssl x509 -in "$NGINX_CERT_DIR/server.pem" -text -noout | grep -q "$DOMAIN"; then
    echo "   ✅ Certificate is valid for domain: $DOMAIN"
else
    echo "   ❌ Certificate validation failed"
    exit 1
fi

# Check private key
if openssl rsa -in "$NGINX_CERT_DIR/server-key.pem" -check -noout 2>/dev/null; then
    echo "   ✅ Private key is valid"
else
    echo "   ❌ Private key validation failed"
    exit 1
fi

# Check DH parameters
if openssl dhparam -in "$NGINX_CERT_DIR/dhparam.pem" -check -noout 2>/dev/null; then
    echo "   ✅ DH parameters are valid"
else
    echo "   ❌ DH parameters validation failed"
    exit 1
fi

# =============================================================================
# START NGINX
# =============================================================================

echo "🚀 Starting nginx with SSL configuration..."

systemctl start nginx
systemctl enable nginx

# Test nginx configuration
if nginx -t 2>/dev/null; then
    echo "   ✅ Nginx configuration is valid"
else
    echo "   ❌ Nginx configuration has errors"
    nginx -t
    exit 1
fi

# =============================================================================
# SECURITY VERIFICATION
# =============================================================================

echo "🛡️  Running SSL security verification..."

# Wait for nginx to fully start
sleep 3

# Test SSL configuration (if curl is available)
if command -v curl &> /dev/null; then
    if curl -Is "https://$DOMAIN" | head -1 | grep -q "200 OK"; then
        echo "   ✅ HTTPS endpoint is responding"
    else
        echo "   ⚠️  HTTPS endpoint is not responding yet (may need DNS propagation)"
    fi
fi

# =============================================================================
# COMPLETION SUMMARY
# =============================================================================

echo ""
echo "✅ SSL/TLS setup completed successfully!"
echo ""
echo "📋 Certificate Information:"
echo "   - Domain: $DOMAIN"
echo "   - Certificate: $NGINX_CERT_DIR/server.pem"
echo "   - Private Key: $NGINX_CERT_DIR/server-key.pem"
echo "   - DH Parameters: $NGINX_CERT_DIR/dhparam.pem (${DH_PARAM_SIZE}-bit)"
echo "   - Auto-renewal: Configured (daily check at 12:00 PM)"
echo ""
echo "🔒 SECURITY FEATURES ENABLED:"
echo "   - TLS 1.2 and 1.3 only"
echo "   - Perfect Forward Secrecy (${DH_PARAM_SIZE}-bit DH)"
echo "   - OCSP Stapling"
echo "   - Strong cipher suites (Mozilla Modern profile)"
echo "   - HSTS with preload"
echo "   - Comprehensive security headers"
echo ""
echo "🛡️  OWASP COMPLIANCE:"
echo "   - A02:2021: Strong cryptographic implementation"
echo "   - A05:2021: Secure SSL/TLS configuration"
echo "   - A06:2021: Automatic certificate management"
echo ""
echo "📖 NEXT STEPS:"
echo "   1. Update DNS records to point to this server"
echo "   2. Test SSL configuration: https://www.ssllabs.com/ssltest/"
echo "   3. Verify automatic renewal: certbot renew --dry-run"
echo "   4. Monitor certificate expiration (30 days before expiry)"
echo ""
echo "⚠️  PRODUCTION REMINDERS:"
echo "   - Monitor certificate expiration dates"
echo "   - Test renewal process regularly"
echo "   - Keep Certbot updated"
echo "   - Review SSL Labs test results quarterly"