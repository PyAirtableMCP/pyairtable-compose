"""
Python Vault Client Library for PyAirtable Services
Production-ready HashiCorp Vault integration for secrets management
Security implementation for 3vantage organization
"""

import os
import json
import time
import logging
import threading
from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta
import requests
import hvac
from hvac.adapters import JSONAdapter
from hvac.api.auth_methods import Kubernetes


class VaultConfig:
    """Configuration class for Vault client"""
    
    def __init__(
        self,
        address: str = None,
        ca_cert_path: str = "/etc/certs/ca.crt",
        client_cert_path: str = "/etc/certs/tls.crt", 
        client_key_path: str = "/etc/certs/tls.key",
        service_account: str = None,
        role: str = None,
        mount_point: str = "kubernetes",
        token_path: str = "/var/run/secrets/kubernetes.io/serviceaccount/token",
        renew_token: bool = True,
        token_renew_buffer: int = 300  # 5 minutes in seconds
    ):
        self.address = address or os.getenv("VAULT_ADDR", "https://vault.vault-system.svc.cluster.local:8200")
        self.ca_cert_path = ca_cert_path
        self.client_cert_path = client_cert_path
        self.client_key_path = client_key_path
        self.service_account = service_account
        self.role = role or f"{service_account}-role" if service_account else None
        self.mount_point = mount_point
        self.token_path = token_path
        self.renew_token = renew_token
        self.token_renew_buffer = token_renew_buffer
        
        # Validate configuration
        self._validate_config()
    
    def _validate_config(self):
        """Validate configuration parameters"""
        if not self.service_account:
            raise ValueError("service_account is required")
        
        if not self.role:
            raise ValueError("role is required")
        
        # Check certificate files exist
        for cert_file, name in [
            (self.ca_cert_path, "CA certificate"),
            (self.client_cert_path, "Client certificate"),
            (self.client_key_path, "Client key"),
            (self.token_path, "Service account token")
        ]:
            if not os.path.exists(cert_file):
                raise FileNotFoundError(f"{name} not found at {cert_file}")


class VaultClient:
    """HashiCorp Vault client with mTLS and Kubernetes authentication"""
    
    def __init__(self, config: VaultConfig, logger: logging.Logger = None):
        self.config = config
        self.logger = logger or logging.getLogger(__name__)
        self._client = None
        self._auth_token = None
        self._token_lease_duration = None
        self._last_renewal = None
        self._renewal_thread = None
        self._shutdown_event = threading.Event()
        
        # Initialize client
        self._initialize_client()
        
        # Authenticate
        self._authenticate_kubernetes()
        
        # Start token renewal if enabled
        if config.renew_token:
            self._start_token_renewal()
    
    def _initialize_client(self):
        """Initialize Vault client with mTLS configuration"""
        try:
            # Create custom adapter for mTLS
            adapter = JSONAdapter()
            adapter.mount("https://", self._create_mtls_adapter())
            
            self._client = hvac.Client(
                url=self.config.address,
                adapter=adapter,
                verify=self.config.ca_cert_path
            )
            
            self.logger.info(f"Vault client initialized for {self.config.address}")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize Vault client: {e}")
            raise
    
    def _create_mtls_adapter(self):
        """Create HTTP adapter with mTLS configuration"""
        from requests.adapters import HTTPAdapter
        from requests.packages.urllib3.util.ssl_ import create_urllib3_context
        import ssl
        
        class MTLSAdapter(HTTPAdapter):
            def __init__(self, cert_file, key_file, ca_file):
                self.cert_file = cert_file
                self.key_file = key_file
                self.ca_file = ca_file
                super().__init__()
            
            def init_poolmanager(self, *args, **kwargs):
                context = create_urllib3_context()
                context.load_cert_chain(self.cert_file, self.key_file)
                context.load_verify_locations(self.ca_file)
                context.check_hostname = True
                context.verify_mode = ssl.CERT_REQUIRED
                context.minimum_version = ssl.TLSVersion.TLSv1_2
                kwargs['ssl_context'] = context
                return super().init_poolmanager(*args, **kwargs)
        
        return MTLSAdapter(
            self.config.client_cert_path,
            self.config.client_key_path,
            self.config.ca_cert_path
        )
    
    def _authenticate_kubernetes(self):
        """Authenticate with Vault using Kubernetes auth method"""
        try:
            # Read service account token
            with open(self.config.token_path, 'r') as f:
                jwt_token = f.read().strip()
            
            # Authenticate using Kubernetes auth method
            response = self._client.auth.kubernetes.login(
                role=self.config.role,
                jwt=jwt_token,
                mount_point=self.config.mount_point
            )
            
            # Extract authentication details
            auth_info = response.get('auth', {})
            self._auth_token = auth_info.get('client_token')
            self._token_lease_duration = auth_info.get('lease_duration', 3600)
            self._last_renewal = datetime.now()
            
            # Set token on client
            self._client.token = self._auth_token
            
            self.logger.info(
                f"Kubernetes authentication successful for role {self.config.role}, "
                f"lease duration: {self._token_lease_duration}s"
            )
            
        except Exception as e:
            self.logger.error(f"Kubernetes authentication failed: {e}")
            raise
    
    def _start_token_renewal(self):
        """Start background token renewal thread"""
        self._renewal_thread = threading.Thread(
            target=self._token_renewal_loop,
            daemon=True
        )
        self._renewal_thread.start()
        self.logger.info("Token renewal thread started")
    
    def _token_renewal_loop(self):
        """Background token renewal loop"""
        while not self._shutdown_event.is_set():
            try:
                # Calculate next renewal time
                renewal_interval = max(
                    self._token_lease_duration - self.config.token_renew_buffer,
                    60  # Minimum 1 minute
                )
                
                # Wait for renewal time or shutdown
                if self._shutdown_event.wait(renewal_interval):
                    break
                
                # Renew token
                self._renew_token()
                
            except Exception as e:
                self.logger.error(f"Token renewal failed: {e}")
                # Try to re-authenticate
                try:
                    self._authenticate_kubernetes()
                except Exception as auth_error:
                    self.logger.error(f"Re-authentication failed: {auth_error}")
                    time.sleep(60)  # Wait before retry
    
    def _renew_token(self):
        """Renew the current Vault token"""
        try:
            response = self._client.auth.token.renew_self(increment=3600)
            auth_info = response.get('auth', {})
            self._token_lease_duration = auth_info.get('lease_duration', 3600)
            self._last_renewal = datetime.now()
            
            self.logger.debug(f"Token renewed successfully, lease duration: {self._token_lease_duration}s")
            
        except Exception as e:
            self.logger.error(f"Token renewal failed: {e}")
            raise
    
    def get_secret(self, path: str) -> Dict[str, Any]:
        """Retrieve a secret from Vault KV store"""
        try:
            response = self._client.secrets.kv.v2.read_secret_version(path=path)
            return response['data']['data']
        except Exception as e:
            self.logger.error(f"Failed to read secret at {path}: {e}")
            raise
    
    def get_secret_value(self, path: str, key: str) -> str:
        """Retrieve a specific value from a secret"""
        data = self.get_secret(path)
        if key not in data:
            raise KeyError(f"Key '{key}' not found in secret at {path}")
        return data[key]
    
    def put_secret(self, path: str, data: Dict[str, Any]) -> None:
        """Store a secret in Vault KV store"""
        try:
            self._client.secrets.kv.v2.create_or_update_secret(
                path=path,
                secret=data
            )
            self.logger.info(f"Secret stored successfully at {path}")
        except Exception as e:
            self.logger.error(f"Failed to store secret at {path}: {e}")
            raise
    
    def get_database_credentials(self, role: str) -> Dict[str, Any]:
        """Retrieve dynamic database credentials"""
        try:
            path = f"pyairtable/database/creds/{role}"
            response = self._client.read(path)
            
            if not response or 'data' not in response:
                raise ValueError(f"No credentials found for role: {role}")
            
            data = response['data']
            return {
                'username': data['username'],
                'password': data['password'],
                'lease_duration': response.get('lease_duration', 3600),
                'lease_id': response.get('lease_id')
            }
            
        except Exception as e:
            self.logger.error(f"Failed to get database credentials for role {role}: {e}")
            raise
    
    def encrypt(self, key_name: str, plaintext: str, context: Dict[str, str] = None) -> str:
        """Encrypt data using Vault's Transit engine"""
        try:
            data = {'plaintext': plaintext}
            if context:
                data['context'] = context
            
            response = self._client.secrets.transit.encrypt_data(
                name=key_name,
                **data
            )
            return response['data']['ciphertext']
            
        except Exception as e:
            self.logger.error(f"Failed to encrypt data with key {key_name}: {e}")
            raise
    
    def decrypt(self, key_name: str, ciphertext: str, context: Dict[str, str] = None) -> str:
        """Decrypt data using Vault's Transit engine"""
        try:
            data = {'ciphertext': ciphertext}
            if context:
                data['context'] = context
            
            response = self._client.secrets.transit.decrypt_data(
                name=key_name,
                **data
            )
            return response['data']['plaintext']
            
        except Exception as e:
            self.logger.error(f"Failed to decrypt data with key {key_name}: {e}")
            raise
    
    def issue_certificate(
        self,
        role: str,
        common_name: str,
        alt_names: List[str] = None,
        ttl: str = "24h"
    ) -> Dict[str, str]:
        """Issue a certificate using Vault's PKI engine"""
        try:
            data = {
                'common_name': common_name,
                'ttl': ttl
            }
            
            if alt_names:
                data['alt_names'] = ','.join(alt_names)
            
            response = self._client.write(f'pyairtable/pki/issue/{role}', **data)
            
            return {
                'certificate': response['data']['certificate'],
                'private_key': response['data']['private_key'],
                'serial_number': response['data']['serial_number']
            }
            
        except Exception as e:
            self.logger.error(f"Failed to issue certificate for {common_name}: {e}")
            raise
    
    def is_healthy(self) -> bool:
        """Check if Vault is healthy and unsealed"""
        try:
            health = self._client.sys.read_health_status()
            return not health.get('sealed', True)
        except Exception as e:
            self.logger.error(f"Health check failed: {e}")
            return False
    
    def close(self):
        """Clean up resources and close client"""
        # Signal shutdown
        self._shutdown_event.set()
        
        # Wait for renewal thread to finish
        if self._renewal_thread and self._renewal_thread.is_alive():
            self._renewal_thread.join(timeout=5)
        
        # Revoke token if available
        if self._auth_token and self._client:
            try:
                self._client.auth.token.revoke_self()
                self.logger.info("Token revoked successfully")
            except Exception as e:
                self.logger.warning(f"Failed to revoke token: {e}")
        
        self.logger.info("Vault client closed")
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


class VaultSecretManager:
    """High-level secret manager for PyAirtable services"""
    
    def __init__(self, service_name: str, logger: logging.Logger = None):
        self.service_name = service_name
        self.logger = logger or logging.getLogger(__name__)
        
        config = VaultConfig(service_account=service_name)
        self.vault_client = VaultClient(config, logger)
    
    def get_jwt_secret(self) -> str:
        """Get JWT signing secret"""
        return self.vault_client.get_secret_value("pyairtable/data/jwt", "secret")
    
    def get_database_url(self) -> str:
        """Get database connection URL with dynamic credentials"""
        creds = self.vault_client.get_database_credentials("pyairtable-db-role")
        
        # Get database host from static config
        db_config = self.vault_client.get_secret("pyairtable/data/database")
        host = db_config.get("host", "postgres.pyairtable-system.svc.cluster.local")
        port = db_config.get("port", "5432")
        database = db_config.get("database", "pyairtable")
        
        return f"postgresql://{creds['username']}:{creds['password']}@{host}:{port}/{database}?sslmode=require"
    
    def get_external_api_key(self, service: str) -> str:
        """Get external API key (e.g., 'airtable', 'gemini', 'openai')"""
        return self.vault_client.get_secret_value("pyairtable/data/external-apis", f"{service}_api_key")
    
    def encrypt_sensitive_data(self, data: str) -> str:
        """Encrypt sensitive data for storage"""
        return self.vault_client.encrypt("pyairtable-encryption", data)
    
    def decrypt_sensitive_data(self, encrypted_data: str) -> str:
        """Decrypt sensitive data"""
        return self.vault_client.decrypt("pyairtable-encryption", encrypted_data)
    
    def close(self):
        """Close vault client"""
        self.vault_client.close()
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


# Example usage
def example_usage():
    """Example usage of VaultSecretManager"""
    import logging
    
    # Configure logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    # Use secret manager
    with VaultSecretManager("llm-orchestrator", logger) as secret_manager:
        # Get JWT secret
        jwt_secret = secret_manager.get_jwt_secret()
        
        # Get database URL
        db_url = secret_manager.get_database_url()
        
        # Get external API key
        openai_key = secret_manager.get_external_api_key("openai")
        
        # Encrypt sensitive data
        encrypted = secret_manager.encrypt_sensitive_data("sensitive information")
        decrypted = secret_manager.decrypt_sensitive_data(encrypted)
        
        logger.info("Successfully retrieved and used secrets")


if __name__ == "__main__":
    example_usage()