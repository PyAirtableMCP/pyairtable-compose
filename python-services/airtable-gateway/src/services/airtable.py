"""Airtable API service with caching and rate limiting"""
import asyncio
import json
import logging
from typing import Any, Dict, List, Optional
from datetime import datetime, timedelta
import httpx
from redis import asyncio as aioredis
import hashlib
from enum import Enum

from ..config import get_settings

# Configure logger
logger = logging.getLogger(__name__)


class AirtableError(Exception):
    """Base exception for Airtable API errors"""
    def __init__(self, message: str, status_code: Optional[int] = None, error_type: Optional[str] = None):
        self.message = message
        self.status_code = status_code
        self.error_type = error_type
        super().__init__(self.message)


class AirtableAuthError(AirtableError):
    """Authentication error with Airtable API"""
    pass


class AirtableRateLimitError(AirtableError):
    """Rate limit exceeded error"""
    pass


class AirtableNotFoundError(AirtableError):
    """Resource not found error"""
    pass


class AirtableValidationError(AirtableError):
    """Request validation error"""
    pass


class AirtableService:
    """Service for interacting with Airtable API"""
    
    def __init__(self, redis_client: aioredis.Redis):
        self.settings = get_settings()
        self.redis = redis_client
        self.base_url = "https://api.airtable.com/v0"
        self.headers = {
            "Authorization": f"Bearer {self.settings.airtable_token}",
            "Content-Type": "application/json",
            "User-Agent": f"{self.settings.service_name}/{self.settings.service_version}"
        }
        self._rate_limiter = asyncio.Semaphore(self.settings.airtable_rate_limit)
        self._api_key_validated = False
        
        logger.info(
            f"Initialized Airtable service with token: {self.settings.get_masked_token()}, "
            f"rate_limit: {self.settings.airtable_rate_limit}/s"
        )
        
    def _cache_key(self, method: str, path: str, params: Optional[Dict] = None) -> str:
        """Generate cache key for request"""
        key_data = f"{method}:{path}:{json.dumps(params or {}, sort_keys=True)}"
        return f"airtable:{hashlib.md5(key_data.encode()).hexdigest()}"
    
    async def _get_from_cache(self, key: str) -> Optional[Dict]:
        """Get data from cache"""
        try:
            data = await self.redis.get(key)
            if data:
                return json.loads(data)
        except json.JSONDecodeError as e:
            logger.warning(f"Invalid JSON in cache for key {key}: {e}")
            # Remove invalid cache entry
            try:
                await self.redis.delete(key)
            except:
                pass
        except Exception as e:
            logger.warning(f"Cache get error for key {key}: {e}")
        return None
    
    async def _set_cache(self, key: str, data: Dict, ttl: Optional[int] = None):
        """Set data in cache"""
        try:
            ttl = ttl or self.settings.cache_ttl
            await self.redis.setex(key, ttl, json.dumps(data))
        except Exception as e:
            logger.warning(f"Cache set error for key {key}: {e}")
            # Don't fail the request if caching fails
    
    async def validate_api_key(self) -> bool:
        """Validate the Airtable API key by making a test request"""
        try:
            logger.info("Validating Airtable API key...")
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(
                    f"{self.base_url}/meta/bases",
                    headers=self.headers
                )
                
                if response.status_code == 200:
                    logger.info("Airtable API key validation successful")
                    self._api_key_validated = True
                    return True
                elif response.status_code == 401:
                    logger.error(f"Airtable API key validation failed: Invalid token ({self.settings.get_masked_token()})")
                    return False
                else:
                    logger.warning(f"Airtable API key validation returned unexpected status: {response.status_code}")
                    return False
                    
        except httpx.TimeoutException:
            logger.error("Airtable API key validation timed out")
            return False
        except Exception as e:
            logger.error(f"Airtable API key validation error: {str(e)}")
            return False

    def _parse_airtable_error(self, response: httpx.Response) -> AirtableError:
        """Parse Airtable API error response and return appropriate exception"""
        try:
            error_data = response.json()
            error_message = error_data.get('error', {}).get('message', 'Unknown error')
            error_type = error_data.get('error', {}).get('type', 'UNKNOWN_ERROR')
        except:
            error_message = f"HTTP {response.status_code}: {response.text}"
            error_type = "HTTP_ERROR"
        
        # Map HTTP status codes to specific exceptions
        if response.status_code == 401:
            return AirtableAuthError(
                f"Authentication failed: {error_message}. Please verify your AIRTABLE_TOKEN.",
                status_code=response.status_code,
                error_type=error_type
            )
        elif response.status_code == 403:
            return AirtableAuthError(
                f"Access forbidden: {error_message}. Check your token permissions.",
                status_code=response.status_code,
                error_type=error_type
            )
        elif response.status_code == 404:
            return AirtableNotFoundError(
                f"Resource not found: {error_message}",
                status_code=response.status_code,
                error_type=error_type
            )
        elif response.status_code == 422:
            return AirtableValidationError(
                f"Validation error: {error_message}",
                status_code=response.status_code,
                error_type=error_type
            )
        elif response.status_code == 429:
            return AirtableRateLimitError(
                f"Rate limit exceeded: {error_message}",
                status_code=response.status_code,
                error_type=error_type
            )
        else:
            return AirtableError(
                f"API error: {error_message}",
                status_code=response.status_code,
                error_type=error_type
            )

    async def _make_request_with_retry(
        self,
        method: str,
        url: str,
        headers: Dict,
        params: Optional[Dict] = None,
        json_data: Optional[Dict] = None
    ) -> httpx.Response:
        """Make HTTP request with exponential backoff retry logic"""
        last_exception = None
        
        for attempt in range(self.settings.airtable_retry_attempts + 1):
            try:
                async with httpx.AsyncClient(timeout=self.settings.airtable_timeout) as client:
                    response = await client.request(
                        method=method,
                        url=url,
                        headers=headers,
                        params=params,
                        json=json_data
                    )
                    
                    # Don't retry on client errors (4xx) except rate limiting
                    if response.status_code < 500 and response.status_code != 429:
                        return response
                    
                    # For server errors (5xx) or rate limiting (429), retry
                    if attempt < self.settings.airtable_retry_attempts:
                        retry_delay = self.settings.airtable_retry_delay * (2 ** attempt)
                        logger.warning(
                            f"Request failed with status {response.status_code}, "
                            f"retrying in {retry_delay}s (attempt {attempt + 1}/{self.settings.airtable_retry_attempts})"
                        )
                        await asyncio.sleep(retry_delay)
                        continue
                    
                    return response
                    
            except (httpx.TimeoutException, httpx.ConnectError, httpx.RequestError) as e:
                last_exception = e
                if attempt < self.settings.airtable_retry_attempts:
                    retry_delay = self.settings.airtable_retry_delay * (2 ** attempt)
                    logger.warning(
                        f"Request failed with {type(e).__name__}: {str(e)}, "
                        f"retrying in {retry_delay}s (attempt {attempt + 1}/{self.settings.airtable_retry_attempts})"
                    )
                    await asyncio.sleep(retry_delay)
                    continue
                else:
                    raise AirtableError(f"Request failed after {self.settings.airtable_retry_attempts} retries: {str(e)}")
        
        # If we get here, all retries failed
        if last_exception:
            raise AirtableError(f"Request failed after {self.settings.airtable_retry_attempts} retries: {str(last_exception)}")

    async def _make_request(
        self,
        method: str,
        path: str,
        params: Optional[Dict] = None,
        data: Optional[Dict] = None,
        use_cache: bool = True
    ) -> Dict[str, Any]:
        """Make request to Airtable API with rate limiting, caching, and retry logic"""
        
        # Validate API key on first request
        if not self._api_key_validated:
            is_valid = await self.validate_api_key()
            if not is_valid:
                raise AirtableAuthError(
                    f"Invalid API key: {self.settings.get_masked_token()}. "
                    "Please verify your AIRTABLE_TOKEN environment variable."
                )
        
        # Check cache for GET requests
        cache_key = self._cache_key(method, path, params)
        if method == "GET" and use_cache:
            cached_data = await self._get_from_cache(cache_key)
            if cached_data:
                logger.debug(f"Cache hit for {method} {path}")
                return cached_data
        
        # Rate limiting
        async with self._rate_limiter:
            url = f"{self.base_url}/{path}"
            
            logger.debug(f"Making {method} request to {url}")
            
            response = await self._make_request_with_retry(
                method=method,
                url=url,
                headers=self.headers,
                params=params,
                json_data=data
            )
            
            # Handle errors
            if response.status_code >= 400:
                error = self._parse_airtable_error(response)
                logger.error(f"Airtable API error: {error.message}")
                raise error
            
            # Parse response
            try:
                result = response.json()
            except json.JSONDecodeError:
                raise AirtableError(f"Invalid JSON response from Airtable API: {response.text}")
            
            # Cache successful GET requests
            if method == "GET" and use_cache:
                await self._set_cache(cache_key, result)
                logger.debug(f"Cached response for {method} {path}")
            
            logger.debug(f"Successfully completed {method} request to {path}")
            return result
    
    async def list_bases(self) -> List[Dict[str, Any]]:
        """List all accessible bases"""
        result = await self._make_request("GET", "meta/bases")
        return result.get("bases", [])
    
    async def get_base_schema(self, base_id: str) -> Dict[str, Any]:
        """Get base schema"""
        return await self._make_request("GET", f"meta/bases/{base_id}/tables")
    
    async def list_records(
        self,
        base_id: str,
        table_id: str,
        view: Optional[str] = None,
        max_records: Optional[int] = None,
        page_size: Optional[int] = None,
        offset: Optional[str] = None,
        fields: Optional[List[str]] = None,
        filter_by_formula: Optional[str] = None,
        sort: Optional[List[Dict[str, str]]] = None
    ) -> Dict[str, Any]:
        """List records from a table"""
        params = {}
        
        if view:
            params["view"] = view
        if max_records:
            params["maxRecords"] = max_records
        if page_size:
            params["pageSize"] = page_size
        if offset:
            params["offset"] = offset
        if fields:
            params["fields[]"] = fields
        if filter_by_formula:
            params["filterByFormula"] = filter_by_formula
        if sort:
            for i, s in enumerate(sort):
                params[f"sort[{i}][field]"] = s["field"]
                params[f"sort[{i}][direction]"] = s.get("direction", "asc")
        
        return await self._make_request("GET", f"{base_id}/{table_id}", params=params)
    
    async def get_record(self, base_id: str, table_id: str, record_id: str) -> Dict[str, Any]:
        """Get a single record"""
        return await self._make_request("GET", f"{base_id}/{table_id}/{record_id}")
    
    async def create_records(
        self,
        base_id: str,
        table_id: str,
        records: List[Dict[str, Any]],
        typecast: bool = False
    ) -> Dict[str, Any]:
        """Create multiple records"""
        data = {
            "records": records,
            "typecast": typecast
        }
        return await self._make_request("POST", f"{base_id}/{table_id}", data=data, use_cache=False)
    
    async def update_records(
        self,
        base_id: str,
        table_id: str,
        records: List[Dict[str, Any]],
        typecast: bool = False,
        replace: bool = False
    ) -> Dict[str, Any]:
        """Update multiple records"""
        method = "PUT" if replace else "PATCH"
        data = {
            "records": records,
            "typecast": typecast
        }
        return await self._make_request(method, f"{base_id}/{table_id}", data=data, use_cache=False)
    
    async def delete_records(
        self,
        base_id: str,
        table_id: str,
        record_ids: List[str]
    ) -> Dict[str, Any]:
        """Delete multiple records"""
        params = {"records[]": record_ids}
        return await self._make_request("DELETE", f"{base_id}/{table_id}", params=params, use_cache=False)
    
    async def invalidate_cache(self, pattern: Optional[str] = None):
        """Invalidate cache entries"""
        if pattern:
            # Delete specific pattern
            cursor = 0
            while True:
                cursor, keys = await self.redis.scan(cursor, match=f"airtable:{pattern}*")
                if keys:
                    await self.redis.delete(*keys)
                if cursor == 0:
                    break
        else:
            # Delete all airtable cache
            cursor = 0
            while True:
                cursor, keys = await self.redis.scan(cursor, match="airtable:*")
                if keys:
                    await self.redis.delete(*keys)
                if cursor == 0:
                    break