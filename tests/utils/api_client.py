"""
API Client Utilities for PyAirtable Integration Tests
Provides shared HTTP client functionality with authentication, retries, and logging
"""

import asyncio
import httpx
import logging
from typing import Dict, Any, Optional, Union, List
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import json
from urllib.parse import urljoin

logger = logging.getLogger(__name__)

@dataclass
class APIResponse:
    """Standardized API response wrapper"""
    status_code: int
    data: Dict[str, Any] = field(default_factory=dict)
    headers: Dict[str, str] = field(default_factory=dict)
    error: Optional[str] = None
    duration: float = 0.0
    endpoint: str = ""
    
    @property
    def is_success(self) -> bool:
        return 200 <= self.status_code < 300
    
    @property
    def is_client_error(self) -> bool:
        return 400 <= self.status_code < 500
    
    @property
    def is_server_error(self) -> bool:
        return self.status_code >= 500

@dataclass
class ServiceConfig:
    """Service configuration"""
    name: str
    base_url: str
    health_endpoint: str = "/health"
    timeout: float = 30.0
    max_retries: int = 3
    retry_delay: float = 1.0

class PyAirtableAPIClient:
    """Enhanced HTTP client for PyAirtable service testing"""
    
    def __init__(self, base_timeout: float = 30.0):
        self.http_client: Optional[httpx.AsyncClient] = None
        self.base_timeout = base_timeout
        self.access_token: Optional[str] = None
        self.request_count = 0
        self.error_count = 0
        
        # Service configurations
        self.services = {
            "api_gateway": ServiceConfig(
                name="API Gateway",
                base_url="http://localhost:8000",
                health_endpoint="/api/health"
            ),
            "airtable_gateway": ServiceConfig(
                name="Airtable Gateway", 
                base_url="http://localhost:8002"
            ),
            "llm_orchestrator": ServiceConfig(
                name="LLM Orchestrator",
                base_url="http://localhost:8003"
            ),
            "platform_services": ServiceConfig(
                name="Platform Services",
                base_url="http://localhost:8007"
            ),
            "auth_service": ServiceConfig(
                name="Auth Service",
                base_url="http://localhost:8009"
            ),
            "user_service": ServiceConfig(
                name="User Service",
                base_url="http://localhost:8010"
            ),
            "workspace_service": ServiceConfig(
                name="Workspace Service",
                base_url="http://localhost:8011"
            )
        }
    
    async def __aenter__(self):
        """Async context manager entry"""
        self.http_client = httpx.AsyncClient(
            timeout=httpx.Timeout(self.base_timeout),
            limits=httpx.Limits(max_keepalive_connections=20, max_connections=100),
            verify=False  # For local testing
        )
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        if self.http_client:
            await self.http_client.aclose()
    
    async def authenticate(self, email: str, password: str, 
                          service: str = "auth_service") -> bool:
        """Authenticate and store access token"""
        try:
            service_config = self.services[service]
            login_data = {"email": email, "password": password}
            
            response = await self._request(
                "POST",
                f"{service_config.base_url}/auth/login",
                json=login_data,
                service_name=service
            )
            
            if response.is_success and "access_token" in response.data:
                self.access_token = response.data["access_token"]
                logger.info(f"Successfully authenticated as {email}")
                return True
            elif response.is_success and "token" in response.data:
                self.access_token = response.data["token"]
                logger.info(f"Successfully authenticated as {email}")
                return True
            else:
                logger.warning(f"Authentication failed: {response.data}")
                return False
                
        except Exception as e:
            logger.error(f"Authentication error: {str(e)}")
            return False
    
    def get_auth_headers(self) -> Dict[str, str]:
        """Get authentication headers"""
        if self.access_token:
            return {"Authorization": f"Bearer {self.access_token}"}
        return {}
    
    async def health_check(self, service: str) -> APIResponse:
        """Check service health"""
        service_config = self.services.get(service)
        if not service_config:
            return APIResponse(
                status_code=0,
                error=f"Unknown service: {service}",
                endpoint=service
            )
        
        endpoint = f"{service_config.base_url}{service_config.health_endpoint}"
        return await self._request("GET", endpoint, service_name=service)
    
    async def health_check_all(self) -> Dict[str, APIResponse]:
        """Check health of all services concurrently"""
        tasks = {
            service: self.health_check(service)
            for service in self.services.keys()
        }
        
        results = {}
        for service, task in tasks.items():
            try:
                results[service] = await task
            except Exception as e:
                results[service] = APIResponse(
                    status_code=0,
                    error=str(e),
                    endpoint=service
                )
        
        return results
    
    async def register_user(self, user_data: Dict[str, str], 
                           service: str = "auth_service") -> APIResponse:
        """Register a new user"""
        service_config = self.services[service]
        endpoint = f"{service_config.base_url}/auth/register"
        
        return await self._request(
            "POST",
            endpoint,
            json=user_data,
            service_name=service
        )
    
    async def get_user_profile(self, service: str = "user_service") -> APIResponse:
        """Get user profile (requires authentication)"""
        service_config = self.services[service]
        endpoint = f"{service_config.base_url}/profile"
        
        return await self._request(
            "GET",
            endpoint,
            headers=self.get_auth_headers(),
            service_name=service
        )
    
    async def list_airtable_bases(self, service: str = "airtable_gateway") -> APIResponse:
        """List available Airtable bases"""
        service_config = self.services[service]
        endpoint = f"{service_config.base_url}/bases"
        
        return await self._request(
            "GET",
            endpoint,
            headers=self.get_auth_headers(),
            service_name=service
        )
    
    async def analyze_airtable_schema(self, base_id: str = None, 
                                     service: str = "airtable_gateway") -> APIResponse:
        """Analyze Airtable schema"""
        service_config = self.services[service]
        endpoint = f"{service_config.base_url}/schema/analyze"
        
        params = {}
        if base_id:
            params["base_id"] = base_id
        
        return await self._request(
            "GET",
            endpoint,
            headers=self.get_auth_headers(),
            params=params,
            service_name=service
        )
    
    async def get_llm_status(self, service: str = "llm_orchestrator") -> APIResponse:
        """Get LLM orchestrator status"""
        service_config = self.services[service]
        endpoint = f"{service_config.base_url}/status"
        
        return await self._request(
            "GET",
            endpoint,
            headers=self.get_auth_headers(),
            service_name=service
        )
    
    async def generate_content(self, prompt: str, max_tokens: int = 100,
                             service: str = "llm_orchestrator") -> APIResponse:
        """Generate AI content"""
        service_config = self.services[service]
        endpoint = f"{service_config.base_url}/generate"
        
        data = {
            "prompt": prompt,
            "max_tokens": max_tokens
        }
        
        return await self._request(
            "POST",
            endpoint,
            headers=self.get_auth_headers(),
            json=data,
            service_name=service
        )
    
    async def test_api_gateway_routing(self) -> Dict[str, APIResponse]:
        """Test API Gateway routing to different services"""
        gateway_config = self.services["api_gateway"]
        auth_headers = self.get_auth_headers()
        
        routes = {
            "health": "/api/health",
            "user_profile": "/api/user/profile", 
            "airtable_bases": "/api/airtable/bases",
            "llm_status": "/api/llm/status",
            "platform_status": "/api/platform/status"
        }
        
        results = {}
        for route_name, route_path in routes.items():
            endpoint = f"{gateway_config.base_url}{route_path}"
            results[route_name] = await self._request(
                "GET",
                endpoint,
                headers=auth_headers,
                service_name="api_gateway"
            )
        
        return results
    
    async def _request(self, method: str, url: str, 
                       headers: Optional[Dict[str, str]] = None,
                       params: Optional[Dict[str, Any]] = None,
                       json: Optional[Dict[str, Any]] = None,
                       service_name: str = "unknown",
                       max_retries: Optional[int] = None) -> APIResponse:
        """Make HTTP request with retries and error handling"""
        if not self.http_client:
            raise RuntimeError("API client not initialized. Use as async context manager.")
        
        service_config = self.services.get(service_name)
        retry_count = max_retries or (service_config.max_retries if service_config else 3)
        retry_delay = service_config.retry_delay if service_config else 1.0
        
        start_time = datetime.now()
        last_error = None
        
        for attempt in range(retry_count + 1):
            try:
                self.request_count += 1
                
                logger.debug(f"{method} {url} (attempt {attempt + 1}/{retry_count + 1})")
                
                response = await self.http_client.request(
                    method=method,
                    url=url,
                    headers=headers,
                    params=params,
                    json=json
                )
                
                duration = (datetime.now() - start_time).total_seconds()
                
                # Try to parse JSON response
                try:
                    response_data = response.json() if response.content else {}
                except (json.JSONDecodeError, ValueError):
                    response_data = {"raw_content": response.text[:1000]}
                
                api_response = APIResponse(
                    status_code=response.status_code,
                    data=response_data,
                    headers=dict(response.headers),
                    duration=duration,
                    endpoint=url
                )
                
                # Log response
                if api_response.is_success:
                    logger.debug(f"Success: {method} {url} -> {response.status_code} ({duration:.2f}s)")
                else:
                    logger.warning(f"Error: {method} {url} -> {response.status_code} ({duration:.2f}s)")
                    self.error_count += 1
                
                return api_response
                
            except (httpx.RequestError, httpx.TimeoutException, asyncio.TimeoutError) as e:
                last_error = str(e)
                logger.warning(f"Request failed (attempt {attempt + 1}/{retry_count + 1}): {last_error}")
                
                if attempt < retry_count:
                    await asyncio.sleep(retry_delay * (2 ** attempt))  # Exponential backoff
                else:
                    self.error_count += 1
            
            except Exception as e:
                last_error = str(e)
                logger.error(f"Unexpected error: {last_error}")
                self.error_count += 1
                break
        
        # Return error response
        duration = (datetime.now() - start_time).total_seconds()
        return APIResponse(
            status_code=0,
            error=last_error or "Request failed after all retries",
            duration=duration,
            endpoint=url
        )
    
    def get_stats(self) -> Dict[str, Any]:
        """Get client statistics"""
        return {
            "total_requests": self.request_count,
            "total_errors": self.error_count,
            "success_rate": f"{((self.request_count - self.error_count) / max(self.request_count, 1)) * 100:.1f}%",
            "authenticated": self.access_token is not None
        }
    
    async def wait_for_service(self, service: str, timeout: int = 60, 
                              check_interval: float = 5.0) -> bool:
        """Wait for service to become healthy"""
        start_time = datetime.now()
        
        while (datetime.now() - start_time).total_seconds() < timeout:
            health_response = await self.health_check(service)
            
            if health_response.is_success:
                logger.info(f"Service {service} is healthy")
                return True
            
            logger.debug(f"Waiting for {service} to become healthy... (status: {health_response.status_code})")
            await asyncio.sleep(check_interval)
        
        logger.warning(f"Service {service} did not become healthy within {timeout}s")
        return False
    
    async def wait_for_all_services(self, timeout: int = 120, 
                                   required_services: Optional[List[str]] = None) -> Dict[str, bool]:
        """Wait for multiple services to become healthy"""
        services_to_check = required_services or list(self.services.keys())
        
        tasks = {
            service: self.wait_for_service(service, timeout)
            for service in services_to_check
        }
        
        results = {}
        for service, task in tasks.items():
            try:
                results[service] = await task
            except Exception as e:
                logger.error(f"Error waiting for {service}: {e}")
                results[service] = False
        
        return results

# Utility functions for common test scenarios
async def create_test_client() -> PyAirtableAPIClient:
    """Create a configured test API client"""
    return PyAirtableAPIClient(base_timeout=30.0)

async def perform_health_checks() -> Dict[str, bool]:
    """Perform health checks on all services"""
    async with create_test_client() as client:
        health_results = await client.health_check_all()
        return {
            service: response.is_success
            for service, response in health_results.items()
        }

async def test_complete_authentication_flow(email: str, password: str) -> bool:
    """Test complete authentication flow"""
    async with create_test_client() as client:
        # Register user (might fail if user exists)
        user_data = {
            "email": email,
            "password": password,
            "first_name": "Test",
            "last_name": "User"
        }
        
        register_response = await client.register_user(user_data)
        logger.info(f"Registration: {register_response.status_code}")
        
        # Authenticate
        auth_success = await client.authenticate(email, password)
        if not auth_success:
            return False
        
        # Test protected endpoint
        profile_response = await client.get_user_profile()
        logger.info(f"Profile access: {profile_response.status_code}")
        
        return auth_success and (profile_response.is_success or profile_response.status_code == 404)

# Example usage for debugging
if __name__ == "__main__":
    async def main():
        print("🚀 PyAirtable API Client Test")
        
        async with create_test_client() as client:
            # Health checks
            print("\n🏥 Checking service health...")
            health_results = await client.health_check_all()
            
            for service, response in health_results.items():
                status = "✅" if response.is_success else "❌"
                print(f"   {status} {service}: {response.status_code}")
            
            # Test authentication
            print("\n🔐 Testing authentication...")
            test_email = "test@example.com"
            test_password = "test_password"
            
            auth_success = await test_complete_authentication_flow(test_email, test_password)
            print(f"   {'✅' if auth_success else '❌'} Authentication: {auth_success}")
            
            # Client stats
            print("\n📊 Client Statistics:")
            stats = client.get_stats()
            for key, value in stats.items():
                print(f"   {key}: {value}")
    
    asyncio.run(main())
