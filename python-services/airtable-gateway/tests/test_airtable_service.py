"""Unit tests for Airtable service"""
import pytest
import asyncio
from unittest.mock import AsyncMock, Mock, patch, MagicMock
import httpx
import json
from redis import asyncio as aioredis

from src.services.airtable import (
    AirtableService,
    AirtableError,
    AirtableAuthError,
    AirtableRateLimitError,
    AirtableNotFoundError,
    AirtableValidationError
)
from src.config import Settings


@pytest.fixture
def mock_settings():
    """Mock settings for testing"""
    settings = Settings(
        airtable_token="pat12345678901234567890123456789012345678901234567890",
        airtable_rate_limit=5,
        airtable_timeout=30,
        airtable_retry_attempts=3,
        airtable_retry_delay=1.0,
        redis_url="redis://localhost:6379/0",
        cache_ttl=3600
    )
    return settings


@pytest.fixture
def mock_redis():
    """Mock Redis client"""
    redis_mock = AsyncMock(spec=aioredis.Redis)
    redis_mock.get.return_value = None
    redis_mock.setex.return_value = None
    redis_mock.delete.return_value = None
    redis_mock.scan.return_value = (0, [])
    return redis_mock


@pytest.fixture
def airtable_service(mock_redis, mock_settings):
    """Create AirtableService instance with mocked dependencies"""
    with patch('src.services.airtable.get_settings', return_value=mock_settings):
        service = AirtableService(mock_redis)
        return service


class TestAirtableServiceInit:
    """Test AirtableService initialization"""
    
    def test_init_with_valid_settings(self, mock_redis, mock_settings):
        """Test service initialization with valid settings"""
        with patch('src.services.airtable.get_settings', return_value=mock_settings):
            service = AirtableService(mock_redis)
            
            assert service.redis == mock_redis
            assert service.base_url == "https://api.airtable.com/v0"
            assert service.headers["Authorization"] == f"Bearer {mock_settings.airtable_token}"
            assert service.headers["Content-Type"] == "application/json"
            assert not service._api_key_validated


class TestAirtableServiceValidation:
    """Test API key validation"""
    
    @pytest.mark.asyncio
    async def test_validate_api_key_success(self, airtable_service):
        """Test successful API key validation"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"bases": []}
        
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value.__aenter__.return_value.get.return_value = mock_response
            
            result = await airtable_service.validate_api_key()
            
            assert result is True
            assert airtable_service._api_key_validated is True
    
    @pytest.mark.asyncio
    async def test_validate_api_key_invalid_token(self, airtable_service):
        """Test API key validation with invalid token"""
        mock_response = Mock()
        mock_response.status_code = 401
        
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value.__aenter__.return_value.get.return_value = mock_response
            
            result = await airtable_service.validate_api_key()
            
            assert result is False
            assert airtable_service._api_key_validated is False
    
    @pytest.mark.asyncio
    async def test_validate_api_key_timeout(self, airtable_service):
        """Test API key validation timeout"""
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value.__aenter__.return_value.get.side_effect = httpx.TimeoutException("Timeout")
            
            result = await airtable_service.validate_api_key()
            
            assert result is False


class TestAirtableServiceErrorParsing:
    """Test error parsing functionality"""
    
    def test_parse_airtable_error_auth_error(self, airtable_service):
        """Test parsing authentication error"""
        mock_response = Mock()
        mock_response.status_code = 401
        mock_response.json.return_value = {
            "error": {
                "type": "AUTHENTICATION_REQUIRED",
                "message": "Invalid API token"
            }
        }
        
        error = airtable_service._parse_airtable_error(mock_response)
        
        assert isinstance(error, AirtableAuthError)
        assert error.status_code == 401
        assert "Invalid API token" in error.message
    
    def test_parse_airtable_error_not_found(self, airtable_service):
        """Test parsing not found error"""
        mock_response = Mock()
        mock_response.status_code = 404
        mock_response.json.return_value = {
            "error": {
                "type": "NOT_FOUND",
                "message": "Could not find table"
            }
        }
        
        error = airtable_service._parse_airtable_error(mock_response)
        
        assert isinstance(error, AirtableNotFoundError)
        assert error.status_code == 404
        assert "Could not find table" in error.message
    
    def test_parse_airtable_error_rate_limit(self, airtable_service):
        """Test parsing rate limit error"""
        mock_response = Mock()
        mock_response.status_code = 429
        mock_response.json.return_value = {
            "error": {
                "type": "RATE_LIMIT_EXCEEDED",
                "message": "Too many requests"
            }
        }
        
        error = airtable_service._parse_airtable_error(mock_response)
        
        assert isinstance(error, AirtableRateLimitError)
        assert error.status_code == 429
    
    def test_parse_airtable_error_validation(self, airtable_service):
        """Test parsing validation error"""
        mock_response = Mock()
        mock_response.status_code = 422
        mock_response.json.return_value = {
            "error": {
                "type": "INVALID_REQUEST_UNKNOWN_FIELD_NAME",
                "message": "Unknown field name"
            }
        }
        
        error = airtable_service._parse_airtable_error(mock_response)
        
        assert isinstance(error, AirtableValidationError)
        assert error.status_code == 422
    
    def test_parse_airtable_error_invalid_json(self, airtable_service):
        """Test parsing error with invalid JSON response"""
        mock_response = Mock()
        mock_response.status_code = 500
        mock_response.json.side_effect = json.JSONDecodeError("Invalid JSON", "", 0)
        mock_response.text = "Internal Server Error"
        
        error = airtable_service._parse_airtable_error(mock_response)
        
        assert isinstance(error, AirtableError)
        assert error.status_code == 500
        assert "HTTP 500" in error.message


class TestAirtableServiceRequests:
    """Test request handling"""
    
    @pytest.mark.asyncio
    async def test_make_request_success(self, airtable_service):
        """Test successful request"""
        # Mock successful validation
        airtable_service._api_key_validated = True
        
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"records": []}
        
        with patch.object(airtable_service, '_make_request_with_retry', return_value=mock_response):
            result = await airtable_service._make_request("GET", "test/path")
            
            assert result == {"records": []}
    
    @pytest.mark.asyncio
    async def test_make_request_auth_error(self, airtable_service):
        """Test request with authentication error"""
        # Mock failed validation
        with patch.object(airtable_service, 'validate_api_key', return_value=False):
            with pytest.raises(AirtableAuthError) as exc_info:
                await airtable_service._make_request("GET", "test/path")
            
            assert "Invalid API key" in str(exc_info.value)
    
    @pytest.mark.asyncio
    async def test_make_request_with_cache_hit(self, airtable_service, mock_redis):
        """Test request with cache hit"""
        airtable_service._api_key_validated = True
        cached_data = {"cached": True}
        
        with patch.object(airtable_service, '_get_from_cache', return_value=cached_data):
            result = await airtable_service._make_request("GET", "test/path")
            
            assert result == cached_data
    
    @pytest.mark.asyncio
    async def test_make_request_with_retry_logic(self, airtable_service):
        """Test request retry logic"""
        airtable_service._api_key_validated = True
        
        # Mock first call fails with 500, second succeeds
        mock_responses = [
            Mock(status_code=500, json=lambda: {"error": {"message": "Server error"}}),
            Mock(status_code=200, json=lambda: {"success": True})
        ]
        
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value.__aenter__.return_value.request.side_effect = mock_responses
            
            # Mock sleep to avoid waiting in tests
            with patch('asyncio.sleep'):
                result = await airtable_service._make_request("GET", "test/path")
                
                assert result == {"success": True}


class TestAirtableServiceOperations:
    """Test CRUD operations"""
    
    @pytest.mark.asyncio
    async def test_list_bases(self, airtable_service):
        """Test listing bases"""
        expected_response = {"bases": [{"id": "app123", "name": "Test Base"}]}
        
        with patch.object(airtable_service, '_make_request', return_value=expected_response):
            result = await airtable_service.list_bases()
            
            assert result == [{"id": "app123", "name": "Test Base"}]
    
    @pytest.mark.asyncio
    async def test_get_base_schema(self, airtable_service):
        """Test getting base schema"""
        expected_response = {"tables": [{"id": "tbl123", "name": "Test Table"}]}
        
        with patch.object(airtable_service, '_make_request', return_value=expected_response) as mock_request:
            result = await airtable_service.get_base_schema("app123")
            
            mock_request.assert_called_once_with("GET", "meta/bases/app123/tables")
            assert result == expected_response
    
    @pytest.mark.asyncio
    async def test_list_records(self, airtable_service):
        """Test listing records"""
        expected_response = {"records": [{"id": "rec123", "fields": {"Name": "Test"}}]}
        
        with patch.object(airtable_service, '_make_request', return_value=expected_response) as mock_request:
            result = await airtable_service.list_records(
                base_id="app123",
                table_id="tbl123",
                max_records=10,
                fields=["Name"]
            )
            
            # Verify correct parameters are passed
            call_args = mock_request.call_args
            assert call_args[0] == ("GET", "app123/tbl123")
            assert call_args[1]["params"]["maxRecords"] == 10
            assert call_args[1]["params"]["fields[]"] == ["Name"]
            assert result == expected_response
    
    @pytest.mark.asyncio
    async def test_create_records(self, airtable_service):
        """Test creating records"""
        records = [{"Name": "Test Record"}]
        expected_response = {"records": [{"id": "rec123", "fields": {"Name": "Test Record"}}]}
        
        with patch.object(airtable_service, '_make_request', return_value=expected_response) as mock_request:
            result = await airtable_service.create_records("app123", "tbl123", records)
            
            # Verify POST request with correct data
            call_args = mock_request.call_args
            assert call_args[0] == ("POST", "app123/tbl123")
            assert call_args[1]["data"]["records"] == records
            assert call_args[1]["use_cache"] is False
            assert result == expected_response
    
    @pytest.mark.asyncio
    async def test_update_records(self, airtable_service):
        """Test updating records"""
        records = [{"id": "rec123", "fields": {"Name": "Updated"}}]
        expected_response = {"records": records}
        
        with patch.object(airtable_service, '_make_request', return_value=expected_response) as mock_request:
            result = await airtable_service.update_records("app123", "tbl123", records, replace=False)
            
            # Verify PATCH request (not PUT)
            call_args = mock_request.call_args
            assert call_args[0] == ("PATCH", "app123/tbl123")
            assert call_args[1]["use_cache"] is False
            assert result == expected_response
    
    @pytest.mark.asyncio
    async def test_delete_records(self, airtable_service):
        """Test deleting records"""
        record_ids = ["rec123", "rec456"]
        expected_response = {"records": [{"deleted": True, "id": "rec123"}]}
        
        with patch.object(airtable_service, '_make_request', return_value=expected_response) as mock_request:
            result = await airtable_service.delete_records("app123", "tbl123", record_ids)
            
            # Verify DELETE request with record IDs as parameters
            call_args = mock_request.call_args
            assert call_args[0] == ("DELETE", "app123/tbl123")
            assert call_args[1]["params"]["records[]"] == record_ids
            assert call_args[1]["use_cache"] is False
            assert result == expected_response


class TestAirtableServiceCaching:
    """Test caching functionality"""
    
    @pytest.mark.asyncio
    async def test_cache_operations(self, airtable_service, mock_redis):
        """Test cache get and set operations"""
        test_data = {"test": "data"}
        cache_key = "test:key"
        
        # Test cache set
        await airtable_service._set_cache(cache_key, test_data, 3600)
        mock_redis.setex.assert_called_once_with(cache_key, 3600, json.dumps(test_data))
        
        # Test cache get with valid data
        mock_redis.get.return_value = json.dumps(test_data)
        result = await airtable_service._get_from_cache(cache_key)
        assert result == test_data
        
        # Test cache get with invalid JSON
        mock_redis.get.return_value = "invalid json"
        result = await airtable_service._get_from_cache(cache_key)
        assert result is None
        mock_redis.delete.assert_called_once_with(cache_key)
    
    @pytest.mark.asyncio
    async def test_invalidate_cache(self, airtable_service, mock_redis):
        """Test cache invalidation"""
        # Mock scan results
        mock_redis.scan.return_value = (0, ["airtable:key1", "airtable:key2"])
        
        await airtable_service.invalidate_cache()
        
        # Verify scan and delete calls
        mock_redis.scan.assert_called()
        mock_redis.delete.assert_called_with("airtable:key1", "airtable:key2")
    
    @pytest.mark.asyncio
    async def test_invalidate_cache_with_pattern(self, airtable_service, mock_redis):
        """Test cache invalidation with specific pattern"""
        pattern = "bases:*"
        mock_redis.scan.return_value = (0, ["airtable:bases:app123"])
        
        await airtable_service.invalidate_cache(pattern)
        
        # Verify scan with pattern
        mock_redis.scan.assert_called_with(0, match=f"airtable:{pattern}*")
        mock_redis.delete.assert_called_with("airtable:bases:app123")


if __name__ == "__main__":
    pytest.main([__file__])