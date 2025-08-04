"""
Python mTLS Client Library for PyAirtable Services
Production-ready mutual TLS implementation for service-to-service communication
Security implementation for 3vantage organization
"""

import ssl
import socket
import logging
import requests
import asyncio
import aiohttp
from typing import Optional, Dict, Any, Union
from urllib3.util.ssl_ import create_urllib3_context
from requests.adapters import HTTPAdapter
from urllib3.adapters import HTTPAdapter as OriginalHTTPAdapter
import certifi
import os


class MTLSConfig:
    """Configuration class for mTLS settings"""
    
    def __init__(
        self,
        cert_file: str = "/etc/certs/tls.crt",
        key_file: str = "/etc/certs/tls.key", 
        ca_file: str = "/etc/certs/ca.crt",
        verify_hostname: bool = True,
        verify_peer: bool = True,
        min_tls_version: str = "TLSv1.2",
        max_tls_version: str = "TLSv1.3"
    ):
        self.cert_file = cert_file
        self.key_file = key_file
        self.ca_file = ca_file
        self.verify_hostname = verify_hostname
        self.verify_peer = verify_peer
        self.min_tls_version = getattr(ssl, f"PROTOCOL_{min_tls_version.replace('.', '_')}")
        self.max_tls_version = getattr(ssl, f"PROTOCOL_{max_tls_version.replace('.', '_')}")
        
        # Validate certificate files exist
        self._validate_cert_files()
        
        self.logger = logging.getLogger(__name__)

    def _validate_cert_files(self) -> None:
        """Validate that all certificate files exist and are readable"""
        for file_path, name in [
            (self.cert_file, "certificate"),
            (self.key_file, "private key"),
            (self.ca_file, "CA certificate")
        ]:
            if not os.path.exists(file_path):
                raise FileNotFoundError(f"{name} file not found: {file_path}")
            if not os.access(file_path, os.R_OK):
                raise PermissionError(f"{name} file not readable: {file_path}")

    def create_ssl_context(self) -> ssl.SSLContext:
        """Create a secure SSL context for mTLS"""
        context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
        
        # Load CA certificates
        context.load_verify_locations(self.ca_file)
        
        # Load client certificate and key
        context.load_cert_chain(self.cert_file, self.key_file)
        
        # Security settings
        context.check_hostname = self.verify_hostname
        context.verify_mode = ssl.CERT_REQUIRED if self.verify_peer else ssl.CERT_NONE
        
        # Set minimum TLS version
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.maximum_version = ssl.TLSVersion.TLSv1_3
        
        # Secure cipher configuration
        context.set_ciphers('ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS')
        
        # Disable weak protocols and features
        context.options |= ssl.OP_NO_SSLv2
        context.options |= ssl.OP_NO_SSLv3
        context.options |= ssl.OP_NO_TLSv1
        context.options |= ssl.OP_NO_TLSv1_1
        context.options |= ssl.OP_NO_COMPRESSION
        context.options |= ssl.OP_CIPHER_SERVER_PREFERENCE
        context.options |= ssl.OP_SINGLE_DH_USE
        context.options |= ssl.OP_SINGLE_ECDH_USE
        
        return context


class MTLSHTTPAdapter(HTTPAdapter):
    """Custom HTTP adapter for mTLS connections"""
    
    def __init__(self, mtls_config: MTLSConfig, *args, **kwargs):
        self.mtls_config = mtls_config
        super().__init__(*args, **kwargs)

    def init_poolmanager(self, *args, **kwargs):
        ssl_context = self.mtls_config.create_ssl_context()
        kwargs['ssl_context'] = ssl_context
        return super().init_poolmanager(*args, **kwargs)


class MTLSClient:
    """HTTP client with mTLS support for service-to-service communication"""
    
    def __init__(
        self,
        mtls_config: Optional[MTLSConfig] = None,
        timeout: int = 30,
        max_retries: int = 3,
        backoff_factor: float = 0.3
    ):
        self.mtls_config = mtls_config or MTLSConfig()
        self.timeout = timeout
        self.max_retries = max_retries
        self.backoff_factor = backoff_factor
        self.logger = logging.getLogger(__name__)
        
        # Create session with mTLS adapter
        self.session = requests.Session()
        adapter = MTLSHTTPAdapter(
            self.mtls_config,
            max_retries=requests.adapters.Retry(
                total=max_retries,
                backoff_factor=backoff_factor,
                status_forcelist=[500, 502, 503, 504]
            )
        )
        self.session.mount("https://", adapter)

    def request(
        self,
        method: str,
        url: str,
        headers: Optional[Dict[str, str]] = None,
        data: Optional[Union[str, bytes, Dict]] = None,
        json: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, str]] = None,
        **kwargs
    ) -> requests.Response:
        """Make an mTLS-secured HTTP request"""
        
        # Add security headers
        if headers is None:
            headers = {}
        
        headers.update({
            'User-Agent': 'PyAirtable-mTLS-Client/1.0',
            'X-Content-Type-Options': 'nosniff',
            'X-Frame-Options': 'DENY'
        })
        
        try:
            self.logger.info(f"Making mTLS request: {method} {url}")
            
            response = self.session.request(
                method=method,
                url=url,
                headers=headers,
                data=data,
                json=json,
                params=params,
                timeout=self.timeout,
                **kwargs
            )
            
            # Log response details (excluding sensitive data)
            self.logger.info(
                f"mTLS request completed: {method} {url} -> {response.status_code}"
            )
            
            return response
            
        except requests.exceptions.SSLError as e:
            self.logger.error(f"mTLS SSL error for {method} {url}: {e}")
            raise
        except requests.exceptions.RequestException as e:
            self.logger.error(f"mTLS request error for {method} {url}: {e}")
            raise

    def get(self, url: str, **kwargs) -> requests.Response:
        """Make a GET request with mTLS"""
        return self.request("GET", url, **kwargs)

    def post(self, url: str, **kwargs) -> requests.Response:
        """Make a POST request with mTLS"""
        return self.request("POST", url, **kwargs)

    def put(self, url: str, **kwargs) -> requests.Response:
        """Make a PUT request with mTLS"""
        return self.request("PUT", url, **kwargs)

    def delete(self, url: str, **kwargs) -> requests.Response:
        """Make a DELETE request with mTLS"""
        return self.request("DELETE", url, **kwargs)

    def patch(self, url: str, **kwargs) -> requests.Response:
        """Make a PATCH request with mTLS"""
        return self.request("PATCH", url, **kwargs)


class AsyncMTLSClient:
    """Async HTTP client with mTLS support"""
    
    def __init__(
        self,
        mtls_config: Optional[MTLSConfig] = None,
        timeout: int = 30,
        connector_limit: int = 100
    ):
        self.mtls_config = mtls_config or MTLSConfig()
        self.timeout = aiohttp.ClientTimeout(total=timeout)
        self.connector_limit = connector_limit
        self.logger = logging.getLogger(__name__)
        self._session: Optional[aiohttp.ClientSession] = None

    async def _get_session(self) -> aiohttp.ClientSession:
        """Get or create async session with mTLS"""
        if self._session is None or self._session.closed:
            ssl_context = self.mtls_config.create_ssl_context()
            
            connector = aiohttp.TCPConnector(
                ssl_context=ssl_context,
                limit=self.connector_limit,
                enable_cleanup_closed=True,
                force_close=True,
                ttl_dns_cache=300,
                use_dns_cache=True
            )
            
            self._session = aiohttp.ClientSession(
                connector=connector,
                timeout=self.timeout,
                headers={
                    'User-Agent': 'PyAirtable-Async-mTLS-Client/1.0',
                    'X-Content-Type-Options': 'nosniff',
                    'X-Frame-Options': 'DENY'
                }
            )
        
        return self._session

    async def request(
        self,
        method: str,
        url: str,
        headers: Optional[Dict[str, str]] = None,
        data: Optional[Union[str, bytes]] = None,
        json: Optional[Dict[str, Any]] = None,
        params: Optional[Dict[str, str]] = None,
        **kwargs
    ) -> aiohttp.ClientResponse:
        """Make an async mTLS-secured HTTP request"""
        
        session = await self._get_session()
        
        try:
            self.logger.info(f"Making async mTLS request: {method} {url}")
            
            async with session.request(
                method=method,
                url=url,
                headers=headers,
                data=data,
                json=json,
                params=params,
                **kwargs
            ) as response:
                self.logger.info(
                    f"Async mTLS request completed: {method} {url} -> {response.status}"
                )
                return response
                
        except aiohttp.ClientSSLError as e:
            self.logger.error(f"Async mTLS SSL error for {method} {url}: {e}")
            raise
        except aiohttp.ClientError as e:
            self.logger.error(f"Async mTLS request error for {method} {url}: {e}")
            raise

    async def get(self, url: str, **kwargs) -> aiohttp.ClientResponse:
        """Make an async GET request with mTLS"""
        return await self.request("GET", url, **kwargs)

    async def post(self, url: str, **kwargs) -> aiohttp.ClientResponse:
        """Make an async POST request with mTLS"""
        return await self.request("POST", url, **kwargs)

    async def put(self, url: str, **kwargs) -> aiohttp.ClientResponse:
        """Make an async PUT request with mTLS"""
        return await self.request("PUT", url, **kwargs)

    async def delete(self, url: str, **kwargs) -> aiohttp.ClientResponse:
        """Make an async DELETE request with mTLS"""
        return await self.request("DELETE", url, **kwargs)

    async def patch(self, url: str, **kwargs) -> aiohttp.ClientResponse:
        """Make an async PATCH request with mTLS"""
        return await self.request("PATCH", url, **kwargs)

    async def close(self):
        """Close the async session"""
        if self._session and not self._session.closed:
            await self._session.close()


# Service Discovery Helper
class ServiceDiscovery:
    """Helper class for service discovery in Kubernetes environment"""
    
    @staticmethod
    def get_service_url(
        service_name: str,
        namespace: str = "pyairtable-system",
        port: int = 443,
        protocol: str = "https"
    ) -> str:
        """Get service URL for Kubernetes DNS"""
        return f"{protocol}://{service_name}.{namespace}.svc.cluster.local:{port}"


# Example usage and testing
def create_mtls_client() -> MTLSClient:
    """Create a configured mTLS client for PyAirtable services"""
    config = MTLSConfig()
    return MTLSClient(config)


async def create_async_mtls_client() -> AsyncMTLSClient:
    """Create a configured async mTLS client for PyAirtable services"""
    config = MTLSConfig()
    return AsyncMTLSClient(config)


# Health check utility
def check_mtls_connectivity(service_url: str) -> bool:
    """Check mTLS connectivity to a service"""
    try:
        client = create_mtls_client()
        response = client.get(f"{service_url}/health")
        return response.status_code == 200
    except Exception as e:
        logging.error(f"mTLS connectivity check failed for {service_url}: {e}")
        return False