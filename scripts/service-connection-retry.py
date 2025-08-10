#!/usr/bin/env python3
"""
CRITICAL: Service Connection Retry Logic
Implements exponential backoff and circuit breaker patterns for service connections
ZERO TOLERANCE for connection failures without proper retry logic
"""

import asyncio
import logging
import time
import random
from typing import Optional, Callable, Any, Dict
from dataclasses import dataclass
from enum import Enum
from contextlib import asynccontextmanager
import aiohttp
import psycopg
import redis.asyncio as redis
from urllib.parse import urlparse


class ConnectionState(Enum):
    """Connection circuit breaker states"""
    CLOSED = "closed"      # Normal operation
    OPEN = "open"          # Failing, not attempting connections
    HALF_OPEN = "half_open"  # Testing if service recovered


@dataclass
class RetryConfig:
    """Configuration for retry logic with aggressive timeouts"""
    max_attempts: int = 5
    base_delay: float = 1.0
    max_delay: float = 30.0
    exponential_base: float = 2.0
    jitter: bool = True
    timeout: float = 10.0
    
    # Circuit breaker settings
    failure_threshold: int = 5
    recovery_timeout: float = 60.0
    half_open_max_calls: int = 3


@dataclass
class ConnectionResult:
    """Result of connection attempt"""
    success: bool
    error: Optional[str] = None
    response_time: float = 0.0
    attempt: int = 0


class ServiceConnectionError(Exception):
    """Custom exception for service connection failures"""
    pass


class CircuitBreaker:
    """Circuit breaker implementation for service connections"""
    
    def __init__(self, config: RetryConfig):
        self.config = config
        self.state = ConnectionState.CLOSED
        self.failure_count = 0
        self.last_failure_time = 0.0
        self.half_open_calls = 0
        
    def can_attempt(self) -> bool:
        """Check if connection attempt should be made"""
        now = time.time()
        
        if self.state == ConnectionState.CLOSED:
            return True
            
        elif self.state == ConnectionState.OPEN:
            if now - self.last_failure_time > self.config.recovery_timeout:
                self.state = ConnectionState.HALF_OPEN
                self.half_open_calls = 0
                return True
            return False
            
        elif self.state == ConnectionState.HALF_OPEN:
            return self.half_open_calls < self.config.half_open_max_calls
            
        return False
    
    def record_success(self) -> None:
        """Record successful connection"""
        self.failure_count = 0
        self.state = ConnectionState.CLOSED
        self.half_open_calls = 0
    
    def record_failure(self) -> None:
        """Record failed connection"""
        self.failure_count += 1
        self.last_failure_time = time.time()
        
        if self.state == ConnectionState.HALF_OPEN:
            self.state = ConnectionState.OPEN
        elif self.failure_count >= self.config.failure_threshold:
            self.state = ConnectionState.OPEN
            
        if self.state == ConnectionState.HALF_OPEN:
            self.half_open_calls += 1


class ServiceConnector:
    """CRITICAL: Robust service connector with retry logic and circuit breaking"""
    
    def __init__(self, service_name: str, config: Optional[RetryConfig] = None):
        self.service_name = service_name
        self.config = config or RetryConfig()
        self.circuit_breaker = CircuitBreaker(self.config)
        self.logger = self._setup_logger()
        
    def _setup_logger(self) -> logging.Logger:
        """Setup logger with service-specific formatting"""
        logger = logging.getLogger(f"connector.{self.service_name}")
        if not logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter(
                f'[%(asctime)s] CONNECTOR[{self.service_name}] %(levelname)s: %(message)s'
            )
            handler.setFormatter(formatter)
            logger.addHandler(handler)
            logger.setLevel(logging.INFO)
        return logger
    
    def _calculate_delay(self, attempt: int) -> float:
        """Calculate delay with exponential backoff and jitter"""
        delay = min(
            self.config.base_delay * (self.config.exponential_base ** attempt),
            self.config.max_delay
        )
        
        if self.config.jitter:
            delay *= (0.5 + random.random() * 0.5)
            
        return delay
    
    async def _attempt_connection(self, connection_func: Callable, *args, **kwargs) -> ConnectionResult:
        """Attempt single connection with timeout"""
        start_time = time.time()
        
        try:
            # Apply timeout to the connection attempt
            result = await asyncio.wait_for(
                connection_func(*args, **kwargs),
                timeout=self.config.timeout
            )
            
            response_time = time.time() - start_time
            return ConnectionResult(
                success=True,
                response_time=response_time
            )
            
        except asyncio.TimeoutError:
            return ConnectionResult(
                success=False,
                error=f"Connection timeout after {self.config.timeout}s",
                response_time=time.time() - start_time
            )
            
        except Exception as e:
            return ConnectionResult(
                success=False,
                error=str(e),
                response_time=time.time() - start_time
            )
    
    async def connect_with_retry(self, connection_func: Callable, *args, **kwargs) -> Any:
        """
        CRITICAL: Connect with comprehensive retry logic and circuit breaking
        This is the main entry point for all service connections
        """
        last_error = None
        
        for attempt in range(1, self.config.max_attempts + 1):
            # Check circuit breaker
            if not self.circuit_breaker.can_attempt():
                self.logger.error(
                    f"Circuit breaker OPEN - blocking connection attempts to {self.service_name}"
                )
                raise ServiceConnectionError(
                    f"Circuit breaker OPEN for {self.service_name}. "
                    f"Service is considered DOWN. Last error: {last_error}"
                )
            
            self.logger.info(
                f"Attempting connection to {self.service_name} (attempt {attempt}/{self.config.max_attempts})"
            )
            
            # Attempt connection
            result = await self._attempt_connection(connection_func, *args, **kwargs)
            
            if result.success:
                self.logger.info(
                    f"Successfully connected to {self.service_name} "
                    f"(attempt {attempt}, {result.response_time:.2f}s)"
                )
                self.circuit_breaker.record_success()
                return True
            
            # Record failure
            last_error = result.error
            self.circuit_breaker.record_failure()
            
            self.logger.warning(
                f"Connection failed to {self.service_name}: {result.error} "
                f"(attempt {attempt}/{self.config.max_attempts}, {result.response_time:.2f}s)"
            )
            
            # Don't wait after the last attempt
            if attempt < self.config.max_attempts:
                delay = self._calculate_delay(attempt - 1)
                self.logger.info(f"Retrying in {delay:.2f}s...")
                await asyncio.sleep(delay)
        
        # All attempts failed
        self.logger.error(
            f"CRITICAL: Failed to connect to {self.service_name} after "
            f"{self.config.max_attempts} attempts. Final error: {last_error}"
        )
        
        raise ServiceConnectionError(
            f"Failed to connect to {self.service_name} after "
            f"{self.config.max_attempts} attempts. Last error: {last_error}"
        )


# Specific connection implementations
class DatabaseConnector(ServiceConnector):
    """PostgreSQL connection with retry logic"""
    
    def __init__(self, config: Optional[RetryConfig] = None):
        super().__init__("PostgreSQL", config)
    
    async def _connect_db(self, connection_string: str) -> None:
        """Attempt database connection"""
        async with psycopg.AsyncConnection.connect(connection_string) as conn:
            await conn.execute("SELECT 1")
    
    async def wait_for_database(self, connection_string: str) -> bool:
        """Wait for database to be ready with retry logic"""
        self.logger.info(f"Waiting for PostgreSQL database: {self._mask_connection_string(connection_string)}")
        
        return await self.connect_with_retry(
            self._connect_db,
            connection_string
        )
    
    def _mask_connection_string(self, conn_str: str) -> str:
        """Mask sensitive information in connection string"""
        try:
            parsed = urlparse(conn_str)
            if parsed.password:
                masked = conn_str.replace(parsed.password, "***")
                return masked
            return conn_str
        except:
            return "***masked***"


class RedisConnector(ServiceConnector):
    """Redis connection with retry logic"""
    
    def __init__(self, config: Optional[RetryConfig] = None):
        super().__init__("Redis", config)
    
    async def _connect_redis(self, redis_url: str) -> None:
        """Attempt Redis connection"""
        client = redis.from_url(redis_url)
        try:
            # Test connection with ping and basic operations
            await client.ping()
            await client.set("connection_test", "ok", ex=10)
            result = await client.get("connection_test")
            if result != b"ok":
                raise Exception("Redis operation test failed")
            await client.delete("connection_test")
        finally:
            await client.aclose()
    
    async def wait_for_redis(self, redis_url: str) -> bool:
        """Wait for Redis to be ready with retry logic"""
        self.logger.info(f"Waiting for Redis: {self._mask_redis_url(redis_url)}")
        
        return await self.connect_with_retry(
            self._connect_redis,
            redis_url
        )
    
    def _mask_redis_url(self, redis_url: str) -> str:
        """Mask password in Redis URL"""
        try:
            parsed = urlparse(redis_url)
            if parsed.password:
                masked = redis_url.replace(parsed.password, "***")
                return masked
            return redis_url
        except:
            return "***masked***"


class HTTPConnector(ServiceConnector):
    """HTTP service connection with retry logic"""
    
    def __init__(self, service_name: str, config: Optional[RetryConfig] = None):
        super().__init__(service_name, config)
    
    async def _connect_http(self, url: str, expected_status: int = 200) -> None:
        """Attempt HTTP connection"""
        async with aiohttp.ClientSession() as session:
            async with session.get(url) as response:
                if response.status != expected_status:
                    raise Exception(f"HTTP {response.status}: {await response.text()}")
    
    async def wait_for_service(self, url: str, expected_status: int = 200) -> bool:
        """Wait for HTTP service to be ready"""
        self.logger.info(f"Waiting for HTTP service at: {url}")
        
        return await self.connect_with_retry(
            self._connect_http,
            url,
            expected_status
        )


# Convenience functions for easy integration
async def wait_for_postgres(connection_string: str, config: Optional[RetryConfig] = None) -> bool:
    """Convenience function to wait for PostgreSQL"""
    connector = DatabaseConnector(config)
    return await connector.wait_for_database(connection_string)


async def wait_for_redis(redis_url: str, config: Optional[RetryConfig] = None) -> bool:
    """Convenience function to wait for Redis"""
    connector = RedisConnector(config)
    return await connector.wait_for_redis(redis_url)


async def wait_for_http_service(service_name: str, url: str, config: Optional[RetryConfig] = None) -> bool:
    """Convenience function to wait for HTTP service"""
    connector = HTTPConnector(service_name, config)
    return await connector.wait_for_service(url)


# CLI interface for use in Docker containers
async def main():
    """CLI interface for service waiting"""
    import argparse
    import os
    
    parser = argparse.ArgumentParser(description='Wait for services with retry logic')
    parser.add_argument('--type', required=True, choices=['postgres', 'redis', 'http'],
                       help='Service type')
    parser.add_argument('--url', required=True, help='Service URL/connection string')
    parser.add_argument('--service-name', help='Service name (for HTTP services)')
    parser.add_argument('--max-attempts', type=int, default=10, help='Maximum retry attempts')
    parser.add_argument('--timeout', type=float, default=10.0, help='Connection timeout')
    parser.add_argument('--base-delay', type=float, default=1.0, help='Base retry delay')
    parser.add_argument('--max-delay', type=float, default=30.0, help='Maximum retry delay')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    
    args = parser.parse_args()
    
    # Setup logging
    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format='[%(asctime)s] %(levelname)s: %(message)s'
    )
    
    # Create retry configuration
    config = RetryConfig(
        max_attempts=args.max_attempts,
        timeout=args.timeout,
        base_delay=args.base_delay,
        max_delay=args.max_delay
    )
    
    try:
        if args.type == 'postgres':
            await wait_for_postgres(args.url, config)
            
        elif args.type == 'redis':
            await wait_for_redis(args.url, config)
            
        elif args.type == 'http':
            service_name = args.service_name or 'HTTP Service'
            await wait_for_http_service(service_name, args.url, config)
        
        print(f"✅ {args.type.upper()} service is ready!")
        return 0
        
    except ServiceConnectionError as e:
        print(f"❌ Service connection failed: {e}")
        return 1
    
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(asyncio.run(main()))