"""Unit tests for API routes"""
import pytest
from unittest.mock import AsyncMock, patch, Mock
from fastapi import HTTPException
from fastapi.testclient import TestClient
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.main import app
from src.services.airtable import (
    AirtableAuthError,
    AirtableNotFoundError,
    AirtableValidationError,
    AirtableRateLimitError,
    AirtableError
)
from src.routes.airtable import handle_airtable_error

# Create test client
client = TestClient(app)


class TestErrorHandling:
    """Test error handling functions"""
    
    def test_handle_airtable_auth_error(self):
        """Test authentication error handling"""
        error = AirtableAuthError("Invalid token", status_code=401, error_type="AUTH_ERROR")
        http_exception = handle_airtable_error(error)
        
        assert isinstance(http_exception, HTTPException)
        assert http_exception.status_code == 401
        assert http_exception.detail["error"] == "Authentication Error"
        assert http_exception.detail["message"] == "Invalid token"
        assert http_exception.detail["type"] == "AUTH_ERROR"
    
    def test_handle_airtable_not_found_error(self):
        """Test not found error handling"""
        error = AirtableNotFoundError("Table not found", status_code=404)
        http_exception = handle_airtable_error(error)
        
        assert http_exception.status_code == 404
        assert http_exception.detail["error"] == "Not Found"
        assert http_exception.detail["message"] == "Table not found"
    
    def test_handle_airtable_validation_error(self):
        """Test validation error handling"""
        error = AirtableValidationError("Invalid field", status_code=422)
        http_exception = handle_airtable_error(error)
        
        assert http_exception.status_code == 422
        assert http_exception.detail["error"] == "Validation Error"
    
    def test_handle_airtable_rate_limit_error(self):
        """Test rate limit error handling"""
        error = AirtableRateLimitError("Rate limit exceeded", status_code=429)
        http_exception = handle_airtable_error(error)
        
        assert http_exception.status_code == 429
        assert http_exception.detail["error"] == "Rate Limit Exceeded"
    
    def test_handle_generic_airtable_error(self):
        """Test generic Airtable error handling"""
        error = AirtableError("Generic error", status_code=503)
        http_exception = handle_airtable_error(error)
        
        assert http_exception.status_code == 503
        assert http_exception.detail["error"] == "Airtable API Error"
    
    def test_handle_unexpected_error(self):
        """Test unexpected error handling"""
        error = ValueError("Unexpected error")
        http_exception = handle_airtable_error(error)
        
        assert http_exception.status_code == 500
        assert http_exception.detail["error"] == "Internal Server Error"
        assert http_exception.detail["type"] == "INTERNAL_ERROR"


class TestAirtableRoutes:
    """Test Airtable API routes"""
    
    def setup_method(self):
        """Setup method called before each test"""
        self.mock_service = AsyncMock()
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_list_bases_success(self, mock_get_service):
        """Test successful bases listing"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.list_bases.return_value = [
            {"id": "app123", "name": "Test Base"}
        ]
        
        response = client.get("/api/v1/airtable/bases")
        
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 1
        assert data[0]["id"] == "app123"
        assert data[0]["name"] == "Test Base"
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_list_bases_auth_error(self, mock_get_service):
        """Test bases listing with authentication error"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.list_bases.side_effect = AirtableAuthError("Invalid token")
        
        response = client.get("/api/v1/airtable/bases")
        
        assert response.status_code == 401
        data = response.json()
        assert data["detail"]["error"] == "Authentication Error"
        assert "Invalid token" in data["detail"]["message"]
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_get_base_schema_success(self, mock_get_service):
        """Test successful base schema retrieval"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.get_base_schema.return_value = {
            "tables": [{"id": "tbl123", "name": "Test Table"}]
        }
        
        response = client.get("/api/v1/airtable/bases/app123/schema")
        
        assert response.status_code == 200
        data = response.json()
        assert "tables" in data
        assert len(data["tables"]) == 1
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_get_base_schema_not_found(self, mock_get_service):
        """Test base schema retrieval with not found error"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.get_base_schema.side_effect = AirtableNotFoundError("Base not found")
        
        response = client.get("/api/v1/airtable/bases/nonexistent/schema")
        
        assert response.status_code == 404
        data = response.json()
        assert data["detail"]["error"] == "Not Found"
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_list_records_success(self, mock_get_service):
        """Test successful records listing"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.list_records.return_value = {
            "records": [{"id": "rec123", "fields": {"Name": "Test"}}]
        }
        
        response = client.get("/api/v1/airtable/bases/app123/tables/tbl123/records")
        
        assert response.status_code == 200
        data = response.json()
        assert "records" in data
        assert len(data["records"]) == 1
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_list_records_with_parameters(self, mock_get_service):
        """Test records listing with query parameters"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.list_records.return_value = {"records": []}
        
        response = client.get(
            "/api/v1/airtable/bases/app123/tables/tbl123/records"
            "?max_records=10&fields=Name&fields=Email&sort_field=Name&sort_direction=desc"
        )
        
        assert response.status_code == 200
        
        # Verify the service was called with correct parameters
        call_args = self.mock_service.list_records.call_args
        assert call_args[1]["max_records"] == 10
        assert call_args[1]["fields"] == ["Name", "Email"]
        assert call_args[1]["sort"] == [{"field": "Name", "direction": "desc"}]
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_get_record_success(self, mock_get_service):
        """Test successful single record retrieval"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.get_record.return_value = {
            "id": "rec123",
            "fields": {"Name": "Test Record"}
        }
        
        response = client.get("/api/v1/airtable/bases/app123/tables/tbl123/records/rec123")
        
        assert response.status_code == 200
        data = response.json()
        assert data["id"] == "rec123"
        assert data["fields"]["Name"] == "Test Record"
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_create_records_success(self, mock_get_service):
        """Test successful record creation"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.create_records.return_value = {
            "records": [{"id": "rec123", "fields": {"Name": "New Record"}}]
        }
        
        payload = [{"Name": "New Record"}]
        response = client.post("/api/v1/airtable/bases/app123/tables/tbl123/records", json=payload)
        
        assert response.status_code == 200
        data = response.json()
        assert "records" in data
        
        # Verify the service was called with formatted records
        call_args = self.mock_service.create_records.call_args
        formatted_records = call_args[0][2]  # Third positional argument
        assert formatted_records[0]["fields"]["Name"] == "New Record"
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_create_records_validation_error(self, mock_get_service):
        """Test record creation with validation error"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.create_records.side_effect = AirtableValidationError("Invalid field")
        
        payload = [{"InvalidField": "value"}]
        response = client.post("/api/v1/airtable/bases/app123/tables/tbl123/records", json=payload)
        
        assert response.status_code == 422
        data = response.json()
        assert data["detail"]["error"] == "Validation Error"
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_update_records_success(self, mock_get_service):
        """Test successful record update"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.update_records.return_value = {
            "records": [{"id": "rec123", "fields": {"Name": "Updated Record"}}]
        }
        
        payload = [{"id": "rec123", "Name": "Updated Record"}]
        response = client.patch("/api/v1/airtable/bases/app123/tables/tbl123/records", json=payload)
        
        assert response.status_code == 200
        data = response.json()
        assert "records" in data
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_update_records_missing_id(self, mock_get_service):
        """Test record update with missing ID"""
        mock_get_service.return_value = self.mock_service
        
        payload = [{"Name": "Updated Record"}]  # Missing ID
        response = client.patch("/api/v1/airtable/bases/app123/tables/tbl123/records", json=payload)
        
        assert response.status_code == 400
        data = response.json()
        assert "id" in data["detail"]
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_replace_records_success(self, mock_get_service):
        """Test successful record replacement"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.update_records.return_value = {"records": []}
        
        payload = [{"id": "rec123", "Name": "Replaced Record"}]
        response = client.put("/api/v1/airtable/bases/app123/tables/tbl123/records", json=payload)
        
        assert response.status_code == 200
        
        # Verify replace=True was passed
        call_args = self.mock_service.update_records.call_args
        assert call_args[1]["replace"] is True
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_delete_records_success(self, mock_get_service):
        """Test successful record deletion"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.delete_records.return_value = {
            "records": [{"deleted": True, "id": "rec123"}]
        }
        
        response = client.delete(
            "/api/v1/airtable/bases/app123/tables/tbl123/records"
            "?record_ids=rec123&record_ids=rec456"
        )
        
        assert response.status_code == 200
        data = response.json()
        assert "records" in data
        
        # Verify the service was called with correct record IDs
        call_args = self.mock_service.delete_records.call_args
        assert call_args[0][2] == ["rec123", "rec456"]  # Third positional argument
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_delete_records_rate_limit(self, mock_get_service):
        """Test record deletion with rate limit error"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.delete_records.side_effect = AirtableRateLimitError("Rate limit exceeded")
        
        response = client.delete(
            "/api/v1/airtable/bases/app123/tables/tbl123/records?record_ids=rec123"
        )
        
        assert response.status_code == 429
        data = response.json()
        assert data["detail"]["error"] == "Rate Limit Exceeded"
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_invalidate_cache_success(self, mock_get_service):
        """Test successful cache invalidation"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.invalidate_cache.return_value = None
        
        response = client.post("/api/v1/airtable/cache/invalidate")
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "success"
        assert "all" in data["message"]
    
    @patch('src.routes.airtable.get_airtable_service')
    def test_invalidate_cache_with_pattern(self, mock_get_service):
        """Test cache invalidation with pattern"""
        mock_get_service.return_value = self.mock_service
        self.mock_service.invalidate_cache.return_value = None
        
        response = client.post("/api/v1/airtable/cache/invalidate?pattern=bases:*")
        
        assert response.status_code == 200
        data = response.json()
        assert "bases:*" in data["message"]
        
        # Verify the service was called with the pattern
        call_args = self.mock_service.invalidate_cache.call_args
        assert call_args[0][0] == "bases:*"  # First positional argument


if __name__ == "__main__":
    pytest.main([__file__])