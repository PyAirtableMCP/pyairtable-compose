// Go Vault Client Library for PyAirtable Services
// Production-ready HashiCorp Vault integration for secrets management
// Security implementation for 3vantage organization

package vault

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/hashicorp/vault/api"
	"github.com/hashicorp/vault/api/auth/kubernetes"
	"go.uber.org/zap"
)

// VaultClient wraps the Vault API client with additional functionality
type VaultClient struct {
	client    *api.Client
	logger    *zap.Logger
	config    *Config
	authToken string
}

// Config holds Vault client configuration
type Config struct {
	Address          string
	CACertPath       string
	ClientCertPath   string
	ClientKeyPath    string
	ServiceAccount   string
	Role             string
	Mount            string
	TokenPath        string
	RenewToken       bool
	TokenRenewBuffer time.Duration
}

// DefaultConfig returns a secure default configuration for Kubernetes environment
func DefaultConfig(serviceName string) *Config {
	return &Config{
		Address:          getEnvOrDefault("VAULT_ADDR", "https://vault.vault-system.svc.cluster.local:8200"),
		CACertPath:       getEnvOrDefault("VAULT_CACERT", "/etc/certs/ca.crt"),
		ClientCertPath:   getEnvOrDefault("VAULT_CLIENT_CERT", "/etc/certs/tls.crt"),
		ClientKeyPath:    getEnvOrDefault("VAULT_CLIENT_KEY", "/etc/certs/tls.key"),
		ServiceAccount:   serviceName,
		Role:             fmt.Sprintf("%s-role", serviceName),
		Mount:            "kubernetes",
		TokenPath:        "/var/run/secrets/kubernetes.io/serviceaccount/token",
		RenewToken:       true,
		TokenRenewBuffer: 5 * time.Minute,
	}
}

// NewVaultClient creates a new Vault client with mTLS and Kubernetes authentication
func NewVaultClient(config *Config, logger *zap.Logger) (*VaultClient, error) {
	if logger == nil {
		logger = zap.NewNop()
	}

	// Configure Vault client
	vaultConfig := api.DefaultConfig()
	vaultConfig.Address = config.Address

	// Configure TLS
	tlsConfig := &api.TLSConfig{
		CACert:     config.CACertPath,
		ClientCert: config.ClientCertPath,
		ClientKey:  config.ClientKeyPath,
		Insecure:   false,
	}

	if err := vaultConfig.ConfigureTLS(tlsConfig); err != nil {
		return nil, fmt.Errorf("failed to configure TLS: %w", err)
	}

	// Create client
	client, err := api.NewClient(vaultConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create Vault client: %w", err)
	}

	vaultClient := &VaultClient{
		client: client,
		logger: logger,
		config: config,
	}

	// Authenticate with Kubernetes
	if err := vaultClient.authenticateKubernetes(); err != nil {
		return nil, fmt.Errorf("failed to authenticate with Vault: %w", err)
	}

	// Start token renewal if enabled
	if config.RenewToken {
		go vaultClient.startTokenRenewal()
	}

	logger.Info("Vault client initialized successfully",
		zap.String("address", config.Address),
		zap.String("role", config.Role),
	)

	return vaultClient, nil
}

// authenticateKubernetes performs Kubernetes authentication with Vault
func (vc *VaultClient) authenticateKubernetes() error {
	// Read Kubernetes service account token
	jwt, err := os.ReadFile(vc.config.TokenPath)
	if err != nil {
		return fmt.Errorf("failed to read service account token: %w", err)
	}

	// Configure Kubernetes authentication
	k8sAuth, err := kubernetes.NewKubernetesAuth(
		vc.config.Role,
		kubernetes.WithServiceAccountToken(string(jwt)),
		kubernetes.WithMountPath(vc.config.Mount),
	)
	if err != nil {
		return fmt.Errorf("failed to create Kubernetes auth: %w", err)
	}

	// Authenticate
	authInfo, err := vc.client.Auth().Login(context.Background(), k8sAuth)
	if err != nil {
		return fmt.Errorf("failed to authenticate: %w", err)
	}

	if authInfo == nil || authInfo.Auth == nil {
		return fmt.Errorf("authentication failed: no auth info returned")
	}

	vc.authToken = authInfo.Auth.ClientToken
	vc.client.SetToken(vc.authToken)

	vc.logger.Info("Kubernetes authentication successful",
		zap.String("role", vc.config.Role),
		zap.Duration("lease_duration", time.Duration(authInfo.Auth.LeaseDuration)*time.Second),
	)

	return nil
}

// startTokenRenewal starts automatic token renewal
func (vc *VaultClient) startTokenRenewal() {
	ticker := time.NewTicker(vc.config.TokenRenewBuffer)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			if err := vc.renewToken(); err != nil {
				vc.logger.Error("Failed to renew token", zap.Error(err))
				// Attempt re-authentication
				if err := vc.authenticateKubernetes(); err != nil {
					vc.logger.Error("Failed to re-authenticate", zap.Error(err))
				}
			}
		}
	}
}

// renewToken renews the current Vault token
func (vc *VaultClient) renewToken() error {
	secret, err := vc.client.Auth().Token().RenewSelf(3600) // Renew for 1 hour
	if err != nil {
		return fmt.Errorf("failed to renew token: %w", err)
	}

	vc.logger.Debug("Token renewed successfully",
		zap.Duration("lease_duration", time.Duration(secret.Auth.LeaseDuration)*time.Second),
	)

	return nil
}

// GetSecret retrieves a secret from Vault KV store
func (vc *VaultClient) GetSecret(path string) (map[string]interface{}, error) {
	secret, err := vc.client.Logical().Read(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read secret at %s: %w", path, err)
	}

	if secret == nil {
		return nil, fmt.Errorf("secret not found at path: %s", path)
	}

	// Handle KV v2 format
	if data, ok := secret.Data["data"].(map[string]interface{}); ok {
		return data, nil
	}

	return secret.Data, nil
}

// GetSecretString retrieves a string value from a secret
func (vc *VaultClient) GetSecretString(path, key string) (string, error) {
	data, err := vc.GetSecret(path)
	if err != nil {
		return "", err
	}

	value, ok := data[key].(string)
	if !ok {
		return "", fmt.Errorf("key %s not found or not a string in secret %s", key, path)
	}

	return value, nil
}

// PutSecret stores a secret in Vault KV store
func (vc *VaultClient) PutSecret(path string, data map[string]interface{}) error {
	// Wrap data for KV v2
	secretData := map[string]interface{}{
		"data": data,
	}

	_, err := vc.client.Logical().Write(path, secretData)
	if err != nil {
		return fmt.Errorf("failed to write secret at %s: %w", path, err)
	}

	vc.logger.Info("Secret stored successfully", zap.String("path", path))
	return nil
}

// GetDatabaseCredentials retrieves dynamic database credentials
func (vc *VaultClient) GetDatabaseCredentials(role string) (*DatabaseCredentials, error) {
	path := fmt.Sprintf("pyairtable/database/creds/%s", role)
	secret, err := vc.client.Logical().Read(path)
	if err != nil {
		return nil, fmt.Errorf("failed to get database credentials: %w", err)
	}

	if secret == nil {
		return nil, fmt.Errorf("no credentials found for role: %s", role)
	}

	username, ok := secret.Data["username"].(string)
	if !ok {
		return nil, fmt.Errorf("username not found in database credentials")
	}

	password, ok := secret.Data["password"].(string)
	if !ok {
		return nil, fmt.Errorf("password not found in database credentials")
	}

	return &DatabaseCredentials{
		Username:      username,
		Password:      password,
		LeaseDuration: time.Duration(secret.LeaseDuration) * time.Second,
		LeaseID:       secret.LeaseID,
	}, nil
}

// DatabaseCredentials holds dynamic database credentials
type DatabaseCredentials struct {
	Username      string
	Password      string
	LeaseDuration time.Duration
	LeaseID       string
}

// Encrypt encrypts data using Vault's Transit engine
func (vc *VaultClient) Encrypt(keyName, plaintext string) (string, error) {
	path := fmt.Sprintf("pyairtable/transit/encrypt/%s", keyName)
	data := map[string]interface{}{
		"plaintext": plaintext,
	}

	secret, err := vc.client.Logical().Write(path, data)
	if err != nil {
		return "", fmt.Errorf("failed to encrypt data: %w", err)
	}

	ciphertext, ok := secret.Data["ciphertext"].(string)
	if !ok {
		return "", fmt.Errorf("ciphertext not found in response")
	}

	return ciphertext, nil
}

// Decrypt decrypts data using Vault's Transit engine
func (vc *VaultClient) Decrypt(keyName, ciphertext string) (string, error) {
	path := fmt.Sprintf("pyairtable/transit/decrypt/%s", keyName)
	data := map[string]interface{}{
		"ciphertext": ciphertext,
	}

	secret, err := vc.client.Logical().Write(path, data)
	if err != nil {
		return "", fmt.Errorf("failed to decrypt data: %w", err)
	}

	plaintext, ok := secret.Data["plaintext"].(string)
	if !ok {
		return "", fmt.Errorf("plaintext not found in response")
	}

	return plaintext, nil
}

// IssueCertificate issues a certificate using Vault's PKI engine
func (vc *VaultClient) IssueCertificate(role, commonName string, altNames []string, ttl string) (*CertificateData, error) {
	path := fmt.Sprintf("pyairtable/pki/issue/%s", role)
	data := map[string]interface{}{
		"common_name": commonName,
		"ttl":         ttl,
	}

	if len(altNames) > 0 {
		data["alt_names"] = altNames
	}

	secret, err := vc.client.Logical().Write(path, data)
	if err != nil {
		return nil, fmt.Errorf("failed to issue certificate: %w", err)
	}

	certificate, ok := secret.Data["certificate"].(string)
	if !ok {
		return nil, fmt.Errorf("certificate not found in response")
	}

	privateKey, ok := secret.Data["private_key"].(string)
	if !ok {
		return nil, fmt.Errorf("private key not found in response")
	}

	return &CertificateData{
		Certificate: certificate,
		PrivateKey:  privateKey,
		SerialNumber: secret.Data["serial_number"].(string),
	}, nil
}

// CertificateData holds certificate information
type CertificateData struct {
	Certificate  string
	PrivateKey   string
	SerialNumber string
}

// Health checks Vault health
func (vc *VaultClient) Health() (bool, error) {
	health, err := vc.client.Sys().Health()
	if err != nil {
		return false, fmt.Errorf("failed to check Vault health: %w", err)
	}

	return !health.Sealed, nil
}

// Close cleans up the Vault client
func (vc *VaultClient) Close() error {
	// Revoke token if needed
	if vc.authToken != "" {
		if err := vc.client.Auth().Token().RevokeSelf(vc.authToken); err != nil {
			vc.logger.Warn("Failed to revoke token", zap.Error(err))
		}
	}

	vc.logger.Info("Vault client closed")
	return nil
}

// Utility function to get environment variable with default
func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// Example usage for PyAirtable services
func ExampleUsage() {
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	// Create Vault client for auth service
	config := DefaultConfig("auth-service")
	vaultClient, err := NewVaultClient(config, logger)
	if err != nil {
		logger.Fatal("Failed to create Vault client", zap.Error(err))
	}
	defer vaultClient.Close()

	// Get JWT secret
	jwtSecret, err := vaultClient.GetSecretString("pyairtable/data/jwt", "secret")
	if err != nil {
		logger.Fatal("Failed to get JWT secret", zap.Error(err))
	}

	// Get database credentials
	dbCreds, err := vaultClient.GetDatabaseCredentials("pyairtable-db-role")
	if err != nil {
		logger.Fatal("Failed to get database credentials", zap.Error(err))
	}

	logger.Info("Retrieved secrets successfully",
		zap.String("db_username", dbCreds.Username),
		zap.Duration("db_lease_duration", dbCreds.LeaseDuration),
	)
}