"""Enhanced Airtable API service with caching, rate limiting, and monitoring."""

import asyncio
import hashlib
import json
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from ..core.config import get_airtable_settings
from ..core.logging import get_logger
from ..models.airtable import AirtableOperationLog
from ..utils.redis_client import RedisCache
from ..database.connection import get_session
from ..models.airtable import AirtableOperation

logger = get_logger(__name__)


class RateLimiter:
    """Rate limiter for Airtable API calls."""
    
    def __init__(self, max_requests: int, time_window: int = 1):
        self.max_requests = max_requests
        self.time_window = time_window
        self.requests = []
        self._lock = asyncio.Lock()
    
    async def acquire(self) -> None:
        """Acquire rate limit token."""
        async with self._lock:
            now = datetime.now()
            # Remove old requests outside the time window
            self.requests = [
                req_time for req_time in self.requests
                if (now - req_time).total_seconds() < self.time_window
            ]
            
            if len(self.requests) >= self.max_requests:
                # Calculate how long to wait
                oldest_request = min(self.requests)
                wait_time = self.time_window - (now - oldest_request).total_seconds()
                if wait_time > 0:
                    await asyncio.sleep(wait_time)
                    return await self.acquire()
            
            self.requests.append(now)


class AirtableService:
    """Enhanced Airtable API service with comprehensive features."""
    
    def __init__(self, cache: Optional[RedisCache] = None):
        self.settings = get_airtable_settings()
        self.cache = cache or RedisCache()
        self.base_url = "https://api.airtable.com/v0"
        self.headers = {
            "Authorization": f"Bearer {self.settings.token}",
            "Content-Type": "application/json",
            "User-Agent": "PyAirtable-Domain-Service/1.0.0",
        }
        self.rate_limiter = RateLimiter(self.settings.rate_limit)
        
        # HTTP client with connection pooling
        self.http_client = httpx.AsyncClient(
            timeout=httpx.Timeout(self.settings.timeout),
            limits=httpx.Limits(max_keepalive_connections=10, max_connections=20),
        )
    
    async def close(self) -> None:
        """Close HTTP client."""
        await self.http_client.aclose()
    
    def _cache_key(self, method: str, path: str, params: Optional[Dict] = None) -> str:
        """Generate cache key for request."""
        key_data = f"{method}:{path}:{json.dumps(params or {}, sort_keys=True)}"
        return f"airtable:{hashlib.md5(key_data.encode()).hexdigest()}"
    
    async def _log_operation(
        self,
        operation_type: str,
        endpoint: str,
        base_id: Optional[str] = None,
        table_id: Optional[str] = None,
        record_count: Optional[int] = None,
        response_status: int = 200,
        response_time_ms: Optional[int] = None,
        error_message: Optional[str] = None,
        user_id: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> None:
        """Log operation to database for auditing."""
        try:
            async with get_session() as session:
                operation = AirtableOperation(
                    operation_type=operation_type,
                    endpoint=endpoint,
                    base_id=base_id,
                    table_id=table_id,
                    record_count=record_count,
                    response_status=response_status,
                    response_time_ms=response_time_ms,
                    error_message=error_message,
                    user_id=user_id,
                    request_id=request_id,
                )
                session.add(operation)
                await session.commit()
        except Exception as e:
            logger.error("Failed to log operation", error=str(e))
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        reraise=True,
    )
    async def _make_request(
        self,
        method: str,
        path: str,
        params: Optional[Dict] = None,
        data: Optional[Dict] = None,
        use_cache: bool = True,
        user_id: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Tuple[Dict[str, Any], int]:
        """Make request to Airtable API with comprehensive error handling."""
        
        # Check cache for GET requests
        cache_key = self._cache_key(method, path, params)
        if method == "GET" and use_cache:
            cached_data = await self.cache.get(cache_key)
            if cached_data:
                logger.debug("Cache hit", cache_key=cache_key)
                return cached_data, 200
        
        # Rate limiting
        await self.rate_limiter.acquire()
        
        # Make request
        start_time = datetime.now()
        url = f"{self.base_url}/{path}"
        
        try:
            response = await self.http_client.request(
                method=method,
                url=url,
                headers=self.headers,
                params=params,
                json=data,
            )
            
            response_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
            
            # Parse base_id and table_id from path
            path_parts = path.split("/")
            base_id = path_parts[0] if len(path_parts) > 0 and path_parts[0] != "meta" else None
            table_id = path_parts[1] if len(path_parts) > 1 and path_parts[0] != "meta" else None
            
            # Log operation
            await self._log_operation(
                operation_type=method,
                endpoint=path,
                base_id=base_id,
                table_id=table_id,
                record_count=self._extract_record_count(data) if data else None,
                response_status=response.status_code,
                response_time_ms=response_time_ms,
                user_id=user_id,
                request_id=request_id,
            )
            
            if response.status_code >= 400:
                error_data = response.json() if response.content else {"error": "Unknown error"}
                error_message = str(error_data)
                
                # Log error
                await self._log_operation(
                    operation_type=method,
                    endpoint=path,
                    base_id=base_id,
                    table_id=table_id,
                    response_status=response.status_code,
                    response_time_ms=response_time_ms,
                    error_message=error_message,
                    user_id=user_id,
                    request_id=request_id,
                )
                
                raise httpx.HTTPStatusError(
                    f"Airtable API error: {error_message}",
                    request=response.request,
                    response=response,
                )
            
            result = response.json()
            
            # Cache successful GET requests
            if method == "GET" and use_cache:
                await self.cache.set(cache_key, result, ttl=self.settings.cache_ttl)
                logger.debug("Cached response", cache_key=cache_key)
            
            return result, response.status_code
            
        except httpx.HTTPStatusError:
            raise
        except Exception as e:
            response_time_ms = int((datetime.now() - start_time).total_seconds() * 1000)
            
            # Log error
            await self._log_operation(
                operation_type=method,
                endpoint=path,
                response_status=500,
                response_time_ms=response_time_ms,
                error_message=str(e),
                user_id=user_id,
                request_id=request_id,
            )
            
            raise e
    
    def _extract_record_count(self, data: Dict[str, Any]) -> Optional[int]:
        """Extract record count from request data."""
        if isinstance(data, dict) and "records" in data:
            records = data["records"]
            if isinstance(records, list):
                return len(records)
        return None
    
    async def list_bases(
        self,
        user_id: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """List all accessible bases."""
        result, _ = await self._make_request(
            "GET", "meta/bases", user_id=user_id, request_id=request_id
        )
        return result.get("bases", [])
    
    async def get_base_schema(
        self,
        base_id: str,
        user_id: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Get base schema."""
        result, _ = await self._make_request(
            "GET", f"meta/bases/{base_id}/tables", user_id=user_id, request_id=request_id
        )
        return result
    
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
        sort: Optional[List[Dict[str, str]]] = None,
        user_id: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """List records from a table."""
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
        
        result, _ = await self._make_request(
            "GET", f"{base_id}/{table_id}", params=params, user_id=user_id, request_id=request_id
        )
        return result
    
    async def get_record(
        self,
        base_id: str,
        table_id: str,
        record_id: str,
        user_id: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Get a single record."""
        result, _ = await self._make_request(
            "GET", f"{base_id}/{table_id}/{record_id}", user_id=user_id, request_id=request_id
        )
        return result
    
    async def create_records(
        self,
        base_id: str,
        table_id: str,
        records: List[Dict[str, Any]],
        typecast: bool = False,
        user_id: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Create multiple records."""
        # Split into batches if necessary
        if len(records) > self.settings.max_batch_size:
            raise ValueError(f"Maximum batch size is {self.settings.max_batch_size}")
        
        data = {
            "records": records,
            "typecast": typecast,
        }
        
        result, _ = await self._make_request(
            "POST", f"{base_id}/{table_id}", data=data, use_cache=False,
            user_id=user_id, request_id=request_id
        )
        
        # Invalidate cache for this table
        await self.invalidate_cache(base_id=base_id, table_id=table_id)
        
        return result
    
    async def update_records(
        self,
        base_id: str,
        table_id: str,
        records: List[Dict[str, Any]],
        typecast: bool = False,
        replace: bool = False,
        user_id: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Update multiple records."""
        if len(records) > self.settings.max_batch_size:
            raise ValueError(f"Maximum batch size is {self.settings.max_batch_size}")
        
        method = "PUT" if replace else "PATCH"
        data = {
            "records": records,
            "typecast": typecast,
        }
        
        result, _ = await self._make_request(
            method, f"{base_id}/{table_id}", data=data, use_cache=False,
            user_id=user_id, request_id=request_id
        )
        
        # Invalidate cache for this table
        await self.invalidate_cache(base_id=base_id, table_id=table_id)
        
        return result
    
    async def delete_records(
        self,
        base_id: str,
        table_id: str,
        record_ids: List[str],
        user_id: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Delete multiple records."""
        if len(record_ids) > self.settings.max_batch_size:
            raise ValueError(f"Maximum batch size is {self.settings.max_batch_size}")
        
        params = {"records[]": record_ids}
        
        result, _ = await self._make_request(
            "DELETE", f"{base_id}/{table_id}", params=params, use_cache=False,
            user_id=user_id, request_id=request_id
        )
        
        # Invalidate cache for this table
        await self.invalidate_cache(base_id=base_id, table_id=table_id)
        
        return result
    
    async def invalidate_cache(
        self,
        pattern: Optional[str] = None,
        base_id: Optional[str] = None,
        table_id: Optional[str] = None,
    ) -> int:
        """Invalidate cache entries."""
        if pattern:
            # Use provided pattern
            cache_pattern = f"airtable:{pattern}*"
        elif base_id and table_id:
            # Invalidate specific table
            cache_pattern = f"airtable:*{base_id}/{table_id}*"
        elif base_id:
            # Invalidate entire base
            cache_pattern = f"airtable:*{base_id}*"
        else:
            # Invalidate all airtable cache
            cache_pattern = "airtable:*"
        
        deleted_count = await self.cache.delete_pattern(cache_pattern)
        logger.info("Cache invalidated", pattern=cache_pattern, deleted_count=deleted_count)
        
        return deleted_count
    
    async def get_operation_stats(
        self,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        base_id: Optional[str] = None,
        user_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Get operation statistics."""
        # This would query the AirtableOperation table
        # Implementation depends on your specific analytics needs
        return {
            "total_operations": 0,
            "success_rate": 100.0,
            "average_response_time": 0,
            "operations_by_type": {},
            "error_summary": {},
        }