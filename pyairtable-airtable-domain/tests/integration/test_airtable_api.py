"""Integration tests for Airtable API endpoints."""

import pytest
from unittest.mock import AsyncMock, patch
from fastapi.testclient import TestClient


@pytest.mark.integration
class TestAirtableAPI:
    """Test Airtable API integration endpoints."""
    
    def test_list_bases_endpoint(self, test_client: TestClient, auth_headers):
        """Test list bases endpoint."""
        with patch("src.services.airtable_service.AirtableService.list_bases") as mock_list_bases:
            mock_list_bases.return_value = [
                {"id": "app123", "name": "Test Base", "permissionLevel": "create"}
            ]
            
            response = test_client.get("/api/v1/airtable/bases", headers=auth_headers)
            
            assert response.status_code == 200
            data = response.json()
            assert len(data) == 1
            assert data[0]["id"] == "app123"
            assert data[0]["name"] == "Test Base"
    
    def test_get_base_schema_endpoint(self, test_client: TestClient, auth_headers):
        """Test get base schema endpoint."""
        base_id = "app123456789"
        
        with patch("src.services.airtable_service.AirtableService.get_base_schema") as mock_schema:
            mock_schema.return_value = {
                "tables": [
                    {
                        "id": "tbl123",
                        "name": "Test Table",
                        "fields": []
                    }
                ]
            }
            
            response = test_client.get(
                f"/api/v1/airtable/bases/{base_id}/schema",
                headers=auth_headers
            )
            
            assert response.status_code == 200
            data = response.json()
            assert "tables" in data
            assert len(data["tables"]) == 1
    
    def test_list_records_endpoint(self, test_client: TestClient, auth_headers):
        """Test list records endpoint."""
        base_id = "app123456789"
        table_id = "tbl123456789"
        
        with patch("src.services.airtable_service.AirtableService.list_records") as mock_records:
            mock_records.return_value = {
                "records": [
                    {
                        "id": "rec123",
                        "fields": {"Name": "Test Record"},
                        "createdTime": "2023-01-01T00:00:00.000Z"
                    }
                ]
            }
            
            response = test_client.get(
                f"/api/v1/airtable/bases/{base_id}/tables/{table_id}/records",
                headers=auth_headers
            )
            
            assert response.status_code == 200
            data = response.json()
            assert "records" in data
            assert len(data["records"]) == 1
    
    def test_list_records_with_filters(self, test_client: TestClient, auth_headers):
        """Test list records with query parameters."""
        base_id = "app123456789"
        table_id = "tbl123456789"
        
        with patch("src.services.airtable_service.AirtableService.list_records") as mock_records:
            mock_records.return_value = {"records": []}
            
            response = test_client.get(
                f"/api/v1/airtable/bases/{base_id}/tables/{table_id}/records",
                params={
                    "max_records": 10,
                    "view": "Grid view",
                    "sort_field": "Name",
                    "sort_direction": "desc"
                },
                headers=auth_headers
            )
            
            assert response.status_code == 200
            
            # Verify the service was called with correct parameters
            mock_records.assert_called_once()
            call_kwargs = mock_records.call_args.kwargs
            assert call_kwargs["max_records"] == 10
            assert call_kwargs["view"] == "Grid view"
            assert call_kwargs["sort"] == [{"field": "Name", "direction": "desc"}]
    
    def test_get_single_record(self, test_client: TestClient, auth_headers):
        """Test get single record endpoint."""
        base_id = "app123456789"
        table_id = "tbl123456789"
        record_id = "rec123456789"
        
        with patch("src.services.airtable_service.AirtableService.get_record") as mock_record:
            mock_record.return_value = {
                "id": record_id,
                "fields": {"Name": "Test Record"},
                "createdTime": "2023-01-01T00:00:00.000Z"
            }
            
            response = test_client.get(
                f"/api/v1/airtable/bases/{base_id}/tables/{table_id}/records/{record_id}",
                headers=auth_headers
            )
            
            assert response.status_code == 200
            data = response.json()
            assert data["id"] == record_id
            assert data["fields"]["Name"] == "Test Record"
    
    def test_create_records(self, test_client: TestClient, auth_headers):
        """Test create records endpoint."""
        base_id = "app123456789"
        table_id = "tbl123456789"
        
        request_data = {
            "records": [
                {"Name": "New Record", "Status": "Active"}
            ],
            "typecast": False
        }
        
        with patch("src.services.airtable_service.AirtableService.create_records") as mock_create:
            mock_create.return_value = {
                "records": [
                    {
                        "id": "rec_new_123",
                        "fields": {"Name": "New Record", "Status": "Active"},
                        "createdTime": "2023-01-01T00:00:00.000Z"
                    }
                ]
            }
            
            response = test_client.post(
                f"/api/v1/airtable/bases/{base_id}/tables/{table_id}/records",
                json=request_data,
                headers=auth_headers
            )
            
            assert response.status_code == 200
            data = response.json()
            assert "records" in data
            assert len(data["records"]) == 1
    
    def test_update_records(self, test_client: TestClient, auth_headers):
        """Test update records endpoint."""
        base_id = "app123456789"
        table_id = "tbl123456789"
        
        request_data = {
            "records": [
                {"id": "rec123", "Name": "Updated Record", "Status": "Inactive"}
            ],
            "typecast": False
        }
        
        with patch("src.services.airtable_service.AirtableService.update_records") as mock_update:
            mock_update.return_value = {
                "records": [
                    {
                        "id": "rec123",
                        "fields": {"Name": "Updated Record", "Status": "Inactive"},
                        "createdTime": "2023-01-01T00:00:00.000Z"
                    }
                ]
            }
            
            response = test_client.patch(
                f"/api/v1/airtable/bases/{base_id}/tables/{table_id}/records",
                json=request_data,
                headers=auth_headers
            )
            
            assert response.status_code == 200
            data = response.json()
            assert "records" in data
    
    def test_delete_records(self, test_client: TestClient, auth_headers):
        """Test delete records endpoint."""
        base_id = "app123456789"
        table_id = "tbl123456789"
        
        request_data = {
            "record_ids": ["rec123", "rec456"]
        }
        
        with patch("src.services.airtable_service.AirtableService.delete_records") as mock_delete:
            mock_delete.return_value = {
                "records": [
                    {"id": "rec123", "deleted": True},
                    {"id": "rec456", "deleted": True}
                ]
            }
            
            response = test_client.delete(
                f"/api/v1/airtable/bases/{base_id}/tables/{table_id}/records",
                json=request_data,
                headers=auth_headers
            )
            
            assert response.status_code == 200
            data = response.json()
            assert "records" in data
            assert len(data["records"]) == 2
    
    def test_invalidate_cache(self, test_client: TestClient, auth_headers):
        """Test cache invalidation endpoint."""
        request_data = {
            "pattern": "test_pattern",
            "base_id": "app123",
            "table_id": "tbl123"
        }
        
        with patch("src.services.airtable_service.AirtableService.invalidate_cache") as mock_invalidate:
            mock_invalidate.return_value = 5  # 5 keys deleted
            
            response = test_client.post(
                "/api/v1/airtable/cache/invalidate",
                json=request_data,
                headers=auth_headers
            )
            
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "success"
            assert data["deleted_count"] == 5
    
    def test_get_operation_stats(self, test_client: TestClient, auth_headers):
        """Test operation statistics endpoint."""
        with patch("src.services.airtable_service.AirtableService.get_operation_stats") as mock_stats:
            mock_stats.return_value = {
                "total_operations": 100,
                "success_rate": 95.0,
                "average_response_time": 250,
                "operations_by_type": {"GET": 60, "POST": 40},
                "error_summary": {}
            }
            
            response = test_client.get(
                "/api/v1/airtable/stats",
                headers=auth_headers
            )
            
            assert response.status_code == 200
            data = response.json()
            assert data["total_operations"] == 100
            assert data["success_rate"] == 95.0
    
    def test_error_handling(self, test_client: TestClient, auth_headers):
        """Test error handling in API endpoints."""
        base_id = "app123456789"
        
        with patch("src.services.airtable_service.AirtableService.get_base_schema") as mock_schema:
            mock_schema.side_effect = Exception("Airtable API error")
            
            response = test_client.get(
                f"/api/v1/airtable/bases/{base_id}/schema",
                headers=auth_headers
            )
            
            assert response.status_code == 500
            data = response.json()
            assert "detail" in data
    
    def test_validation_error_handling(self, test_client: TestClient, auth_headers):
        """Test validation error handling."""
        base_id = "app123456789"
        table_id = "tbl123456789"
        
        # Invalid request data (empty records)
        request_data = {
            "records": [],
            "typecast": False
        }
        
        response = test_client.post(
            f"/api/v1/airtable/bases/{base_id}/tables/{table_id}/records",
            json=request_data,
            headers=auth_headers
        )
        
        assert response.status_code == 422  # Validation error