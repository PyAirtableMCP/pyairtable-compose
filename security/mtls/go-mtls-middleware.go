// Go mTLS Middleware for PyAirtable Services
// Production-ready mutual TLS implementation for service-to-service communication
// Security implementation for 3vantage organization

package security

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"net/http"
	"strings"

	"github.com/gofiber/fiber/v2"
	"go.uber.org/zap"
)

// MTLSConfig holds the mTLS configuration
type MTLSConfig struct {
	CertFile   string
	KeyFile    string
	CAFile     string
	MinVersion uint16
	MaxVersion uint16
	Verify     bool
	Logger     *zap.Logger
}

// DefaultMTLSConfig returns a secure default configuration
func DefaultMTLSConfig(logger *zap.Logger) *MTLSConfig {
	return &MTLSConfig{
		CertFile:   "/etc/certs/tls.crt",
		KeyFile:    "/etc/certs/tls.key",
		CAFile:     "/etc/certs/ca.crt",
		MinVersion: tls.VersionTLS12,
		MaxVersion: tls.VersionTLS13,
		Verify:     true,
		Logger:     logger,
	}
}

// LoadTLSConfig creates a TLS configuration for mTLS
func (m *MTLSConfig) LoadTLSConfig() (*tls.Config, error) {
	// Load server certificate
	cert, err := tls.LoadX509KeyPair(m.CertFile, m.KeyFile)
	if err != nil {
		return nil, fmt.Errorf("failed to load certificate pair: %w", err)
	}

	// Load CA certificate
	caCert, err := ioutil.ReadFile(m.CAFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read CA certificate: %w", err)
	}

	caCertPool := x509.NewCertPool()
	if !caCertPool.AppendCertsFromPEM(caCert) {
		return nil, fmt.Errorf("failed to parse CA certificate")
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		ClientAuth:   tls.RequireAndVerifyClientCert,
		ClientCAs:    caCertPool,
		RootCAs:      caCertPool,
		MinVersion:   m.MinVersion,
		MaxVersion:   m.MaxVersion,
		CipherSuites: []uint16{
			tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,
			tls.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,
		},
		PreferServerCipherSuites: false, // Let client choose for TLS 1.3
		CurvePreferences: []tls.CurveID{
			tls.X25519,
			tls.CurveP256,
			tls.CurveP384,
		},
	}

	return tlsConfig, nil
}

// CreateHTTPClient creates an HTTP client configured for mTLS
func (m *MTLSConfig) CreateHTTPClient() (*http.Client, error) {
	tlsConfig, err := m.LoadTLSConfig()
	if err != nil {
		return nil, err
	}

	transport := &http.Transport{
		TLSClientConfig: tlsConfig,
		// Security-focused transport settings
		DisableKeepAlives:     false,
		DisableCompression:    false,
		MaxIdleConns:          10,
		MaxIdleConnsPerHost:   10,
		IdleConnTimeout:       30,
		TLSHandshakeTimeout:   10,
		ExpectContinueTimeout: 1,
	}

	return &http.Client{
		Transport: transport,
		Timeout:   30, // 30 second timeout
	}, nil
}

// MTLSMiddleware creates a Fiber middleware for mTLS verification
func (m *MTLSConfig) MTLSMiddleware() fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Check if TLS is enabled
		if !c.Context().IsTLS() {
			m.Logger.Warn("Non-TLS request rejected",
				zap.String("remote_addr", c.IP()),
				zap.String("user_agent", c.Get("User-Agent")),
			)
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "TLS required",
				"code":  "TLS_REQUIRED",
			})
		}

		// Verify client certificate
		if m.Verify {
			clientCert := c.Get("X-SSL-Client-Cert")
			clientDN := c.Get("X-SSL-Client-DN")
			clientVerify := c.Get("X-SSL-Client-Verify")

			if clientVerify != "SUCCESS" {
				m.Logger.Error("Client certificate verification failed",
					zap.String("verify_status", clientVerify),
					zap.String("client_dn", clientDN),
					zap.String("remote_addr", c.IP()),
				)
				return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
					"error": "Client certificate verification failed",
					"code":  "MTLS_VERIFICATION_FAILED",
				})
			}

			// Extract service name from client certificate
			serviceName := extractServiceName(clientDN)
			if serviceName == "" {
				m.Logger.Error("Unable to extract service name from client certificate",
					zap.String("client_dn", clientDN),
					zap.String("remote_addr", c.IP()),
				)
				return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
					"error": "Invalid service identity",
					"code":  "INVALID_SERVICE_IDENTITY",
				})
			}

			// Store service identity in context for authorization
			c.Locals("service_name", serviceName)
			c.Locals("client_dn", clientDN)

			m.Logger.Info("mTLS authentication successful",
				zap.String("service_name", serviceName),
				zap.String("client_dn", clientDN),
				zap.String("remote_addr", c.IP()),
			)
		}

		return c.Next()
	}
}

// extractServiceName extracts service name from certificate DN
func extractServiceName(dn string) string {
	// Parse DN to extract CN (Common Name)
	parts := strings.Split(dn, ",")
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if strings.HasPrefix(part, "CN=") {
			cn := strings.TrimPrefix(part, "CN=")
			// Extract service name from FQDN
			if strings.Contains(cn, ".") {
				return strings.Split(cn, ".")[0]
			}
			return cn
		}
	}
	return ""
}

// ServiceAuthorizationMiddleware checks if the service is authorized to access the endpoint
func ServiceAuthorizationMiddleware(allowedServices []string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		serviceName, ok := c.Locals("service_name").(string)
		if !ok {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Service identity not found",
				"code":  "SERVICE_IDENTITY_MISSING",
			})
		}

		// Check if service is authorized
		authorized := false
		for _, allowed := range allowedServices {
			if serviceName == allowed {
				authorized = true
				break
			}
		}

		if !authorized {
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
				"error": "Service not authorized for this endpoint",
				"code":  "SERVICE_NOT_AUTHORIZED",
			})
		}

		return c.Next()
	}
}

// MTLSHealthCheck provides a health check endpoint that verifies mTLS configuration
func MTLSHealthCheck(config *MTLSConfig) fiber.Handler {
	return func(c *fiber.Ctx) error {
		health := fiber.Map{
			"status": "healthy",
			"mtls":   "enabled",
			"timestamp": c.Context().Time(),
		}

		// Add service identity if available
		if serviceName, ok := c.Locals("service_name").(string); ok {
			health["client_service"] = serviceName
		}

		if clientDN, ok := c.Locals("client_dn").(string); ok {
			health["client_dn"] = clientDN
		}

		return c.JSON(health)
	}
}