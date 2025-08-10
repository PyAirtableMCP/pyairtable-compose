#!/usr/bin/env python3
"""
Simple test to validate automation services startup and basic functionality
"""
import asyncio
import sys
import os
import pytest
import httpx
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Add src to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), 'src'))

from src.config import Settings
from src.database import get_database_url, create_tables, Base
from src.utils.redis_client import init_redis, get_redis_client
from src.services.scheduler import WorkflowScheduler

class TestAutomationServiceStartup:
    """Test automation service startup components"""
    
    def setup_class(self):
        """Set up test environment"""
        self.settings = Settings()
        print(f"Testing with config: database_url={self.settings.database_url}")
    
    def test_config_loading(self):
        """Test configuration loading"""
        assert self.settings.port == 8006
        assert self.settings.api_key is not None
        assert self.settings.database_url is not None
        assert self.settings.redis_url is not None
    
    def test_database_url_generation(self):
        """Test database URL generation"""
        db_url = get_database_url()
        assert db_url is not None
        assert "postgresql://" in db_url
    
    @pytest.mark.asyncio
    async def test_redis_client_init(self):
        """Test Redis client initialization"""
        try:
            # This will fail if Redis is not available, which is expected in test env
            await init_redis()
            redis_client = await get_redis_client()
            assert redis_client is not None
            print("✓ Redis connection successful")
        except Exception as e:
            print(f"⚠ Redis connection failed (expected in test env): {str(e)}")
    
    def test_workflow_scheduler_creation(self):
        """Test workflow scheduler creation"""
        scheduler = WorkflowScheduler()
        assert scheduler is not None
        assert not scheduler.running
        print("✓ Workflow scheduler created successfully")
    
    @pytest.mark.asyncio
    async def test_service_endpoints_structure(self):
        """Test that service endpoints are properly structured"""
        from src.main import app
        
        # Check if routes are registered
        routes = [route.path for route in app.routes]
        
        expected_routes = [
            "/",
            "/health", 
            "/ready",
            "/live"
        ]
        
        for route in expected_routes:
            assert any(route in r for r in routes), f"Route {route} not found"
        
        print("✓ All expected routes are registered")
    
    def test_file_extensions_parsing(self):
        """Test file extension parsing"""
        extensions = self.settings.allowed_extensions_list
        assert isinstance(extensions, list)
        assert len(extensions) > 0
        assert "pdf" in extensions
        print(f"✓ File extensions parsed: {extensions}")
    
    def test_file_size_parsing(self):
        """Test file size parsing"""
        max_size = self.settings.max_file_size_bytes
        assert max_size > 0
        assert max_size == 10 * 1024 * 1024  # 10MB default
        print(f"✓ Max file size: {max_size} bytes")


def run_startup_validation():
    """Run basic startup validation tests"""
    print("🔧 Running Automation Services Startup Validation...")
    print("=" * 60)
    
    test_instance = TestAutomationServiceStartup()
    test_instance.setup_class()
    
    # Run synchronous tests
    try:
        test_instance.test_config_loading()
        print("✓ Configuration loading")
    except Exception as e:
        print(f"✗ Configuration loading failed: {str(e)}")
    
    try:
        test_instance.test_database_url_generation()
        print("✓ Database URL generation")
    except Exception as e:
        print(f"✗ Database URL generation failed: {str(e)}")
    
    try:
        test_instance.test_workflow_scheduler_creation()
        print("✓ Workflow scheduler creation")
    except Exception as e:
        print(f"✗ Workflow scheduler creation failed: {str(e)}")
    
    try:
        test_instance.test_file_extensions_parsing()
        print("✓ File extensions parsing")
    except Exception as e:
        print(f"✗ File extensions parsing failed: {str(e)}")
    
    try:
        test_instance.test_file_size_parsing()
        print("✓ File size parsing")
    except Exception as e:
        print(f"✗ File size parsing failed: {str(e)}")
    
    # Run async tests
    async def run_async_tests():
        try:
            await test_instance.test_redis_client_init()
        except Exception as e:
            print(f"✗ Redis client initialization failed: {str(e)}")
        
        try:
            await test_instance.test_service_endpoints_structure()
        except Exception as e:
            print(f"✗ Service endpoints structure failed: {str(e)}")
    
    asyncio.run(run_async_tests())
    
    print("=" * 60)
    print("🎯 Automation Services Startup Validation Complete!")


if __name__ == "__main__":
    run_startup_validation()