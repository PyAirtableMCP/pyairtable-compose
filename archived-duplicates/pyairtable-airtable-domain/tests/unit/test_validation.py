"""Unit tests for validation utilities."""

import pytest

from src.utils.validation import (
    is_valid_uuid,
    is_valid_email,
    is_valid_url,
    is_valid_airtable_id,
    validate_airtable_record_fields,
    validate_batch_size,
    validate_pagination_params,
    sanitize_string,
    get_nested_depth,
)


@pytest.mark.unit
class TestValidationUtils:
    """Test validation utility functions."""
    
    def test_is_valid_uuid(self):
        """Test UUID validation."""
        # Valid UUIDs
        assert is_valid_uuid("550e8400-e29b-41d4-a716-446655440000")
        assert is_valid_uuid("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
        
        # Invalid UUIDs
        assert not is_valid_uuid("not-a-uuid")
        assert not is_valid_uuid("550e8400-e29b-41d4-a716")
        assert not is_valid_uuid("")
        assert not is_valid_uuid("123")
    
    def test_is_valid_email(self):
        """Test email validation."""
        # Valid emails
        assert is_valid_email("test@example.com")
        assert is_valid_email("user.name+tag@domain.co.uk")
        assert is_valid_email("user123@test-domain.org")
        
        # Invalid emails
        assert not is_valid_email("not-an-email")
        assert not is_valid_email("@domain.com")
        assert not is_valid_email("user@")
        assert not is_valid_email("")
    
    def test_is_valid_url(self):
        """Test URL validation."""
        # Valid URLs
        assert is_valid_url("https://example.com")
        assert is_valid_url("http://test.org/path?param=value")
        assert is_valid_url("https://sub.domain.com:8080/path")
        
        # Invalid URLs
        assert not is_valid_url("not-a-url")
        assert not is_valid_url("ftp://example.com")  # Only http/https
        assert not is_valid_url("example.com")  # Missing protocol
        assert not is_valid_url("")
    
    def test_is_valid_airtable_id(self):
        """Test Airtable ID validation."""
        # Valid IDs
        assert is_valid_airtable_id("app12345678901234", "base")
        assert is_valid_airtable_id("tbl12345678901234", "table")
        assert is_valid_airtable_id("rec12345678901234", "record")
        assert is_valid_airtable_id("fld12345678901234", "field")
        assert is_valid_airtable_id("viw12345678901234", "view")
        
        # Any type
        assert is_valid_airtable_id("app12345678901234", "any")
        assert is_valid_airtable_id("tbl12345678901234", "any")
        
        # Invalid IDs
        assert not is_valid_airtable_id("invalid", "base")
        assert not is_valid_airtable_id("app123", "base")  # Too short
        assert not is_valid_airtable_id("tbl12345678901234", "base")  # Wrong type
        assert not is_valid_airtable_id("", "any")
    
    def test_validate_airtable_record_fields(self):
        """Test Airtable record fields validation."""
        # Valid fields
        valid_fields = {"Name": "Test", "Status": "Active"}
        is_valid, errors = validate_airtable_record_fields(valid_fields)
        assert is_valid
        assert len(errors) == 0
        
        # Empty fields
        is_valid, errors = validate_airtable_record_fields({})
        assert not is_valid
        assert "cannot be empty" in errors[0]
        
        # Field name too long
        long_name = "x" * 300
        is_valid, errors = validate_airtable_record_fields({long_name: "value"})
        assert not is_valid
        assert "too long" in errors[0]
        
        # Field value too long
        long_value = "x" * 200000
        is_valid, errors = validate_airtable_record_fields({"field": long_value})
        assert not is_valid
        assert "too long" in errors[0]
    
    def test_validate_batch_size(self):
        """Test batch size validation."""
        # Valid batches
        is_valid, message = validate_batch_size([1, 2, 3], max_size=10)
        assert is_valid
        assert message == ""
        
        # Empty batch
        is_valid, message = validate_batch_size([], max_size=10)
        assert not is_valid
        assert "cannot be empty" in message
        
        # Too large batch
        is_valid, message = validate_batch_size([1] * 15, max_size=10)
        assert not is_valid
        assert "exceeds maximum" in message
    
    def test_validate_pagination_params(self):
        """Test pagination parameters validation."""
        # Valid params
        is_valid, errors = validate_pagination_params(10, 0)
        assert is_valid
        assert len(errors) == 0
        
        # Invalid limit
        is_valid, errors = validate_pagination_params(0, 0)
        assert not is_valid
        assert "at least 1" in errors[0]
        
        is_valid, errors = validate_pagination_params(200, 0)
        assert not is_valid
        assert "cannot exceed 100" in errors[0]
        
        # Invalid offset
        is_valid, errors = validate_pagination_params(10, -1)
        assert not is_valid
        assert "cannot be negative" in errors[0]
    
    def test_sanitize_string(self):
        """Test string sanitization."""
        # Basic sanitization
        assert sanitize_string("  test  ") == "test"
        assert sanitize_string("test\x00control") == "testcontrol"
        
        # Length limiting
        long_string = "x" * 100
        assert len(sanitize_string(long_string, max_length=10)) == 10
        
        # Non-string input
        assert sanitize_string(123) == "123"
    
    def test_get_nested_depth(self):
        """Test nested depth calculation."""
        # Simple structures
        assert get_nested_depth({}) == 0
        assert get_nested_depth([]) == 0
        assert get_nested_depth({"a": 1}) == 0
        
        # Nested structures
        assert get_nested_depth({"a": {"b": 1}}) == 1
        assert get_nested_depth({"a": {"b": {"c": 1}}}) == 2
        assert get_nested_depth([[[]]]) == 2
        
        # Mixed structures
        nested_dict = {"a": {"b": [{"c": {"d": 1}}]}}
        assert get_nested_depth(nested_dict) == 3