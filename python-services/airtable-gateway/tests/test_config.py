"""Unit tests for configuration validation"""
import pytest
from pydantic import ValidationError
from src.config import Settings


class TestSettingsValidation:
    """Test configuration validation"""
    
    def test_valid_config(self):
        """Test valid configuration"""
        settings = Settings(
            airtable_token="patABCD1234567890123456789012345678901234567890",
            airtable_rate_limit=5,
            airtable_retry_attempts=3
        )
        
        assert settings.airtable_token.startswith("pat")
        assert settings.airtable_rate_limit == 5
        assert settings.airtable_retry_attempts == 3
    
    def test_empty_airtable_token(self):
        """Test empty Airtable token raises validation error"""
        with pytest.raises(ValidationError) as exc_info:
            Settings(airtable_token="")
        
        error = exc_info.value.errors()[0]
        assert error["type"] == "value_error"
        assert "AIRTABLE_TOKEN is required" in str(error["msg"])
    
    def test_invalid_airtable_token_format(self):
        """Test invalid Airtable token format"""
        with pytest.raises(ValidationError) as exc_info:
            Settings(airtable_token="invalid_token")
        
        error = exc_info.value.errors()[0]
        assert error["type"] == "value_error"
        assert "Invalid Airtable token format" in str(error["msg"])
    
    def test_short_airtable_token(self):
        """Test too short Airtable token"""
        with pytest.raises(ValidationError) as exc_info:
            Settings(airtable_token="pat123")
        
        error = exc_info.value.errors()[0]
        assert error["type"] == "value_error"
        assert "too short" in str(error["msg"])
    
    def test_old_api_key_format(self):
        """Test old API key format is accepted"""
        settings = Settings(
            airtable_token="keyABCD1234567890123456789012345678901234567890"
        )
        
        assert settings.airtable_token.startswith("key")
    
    def test_invalid_rate_limit(self):
        """Test invalid rate limit values"""
        with pytest.raises(ValidationError) as exc_info:
            Settings(
                airtable_token="patABCD1234567890123456789012345678901234567890",
                airtable_rate_limit=0
            )
        
        error = exc_info.value.errors()[0]
        assert error["type"] == "value_error"
        assert "between 1 and 100" in str(error["msg"])
        
        with pytest.raises(ValidationError) as exc_info:
            Settings(
                airtable_token="patABCD1234567890123456789012345678901234567890",
                airtable_rate_limit=101
            )
        
        error = exc_info.value.errors()[0]
        assert error["type"] == "value_error"
        assert "between 1 and 100" in str(error["msg"])
    
    def test_invalid_retry_attempts(self):
        """Test invalid retry attempts values"""
        with pytest.raises(ValidationError) as exc_info:
            Settings(
                airtable_token="patABCD1234567890123456789012345678901234567890",
                airtable_retry_attempts=-1
            )
        
        error = exc_info.value.errors()[0]
        assert error["type"] == "value_error"
        assert "between 0 and 10" in str(error["msg"])
        
        with pytest.raises(ValidationError) as exc_info:
            Settings(
                airtable_token="patABCD1234567890123456789012345678901234567890",
                airtable_retry_attempts=11
            )
        
        error = exc_info.value.errors()[0]
        assert error["type"] == "value_error"
        assert "between 0 and 10" in str(error["msg"])
    
    def test_get_masked_token(self):
        """Test token masking for logging"""
        settings = Settings(
            airtable_token="patABCD1234567890123456789012345678901234567890"
        )
        
        masked = settings.get_masked_token()
        assert masked.startswith("patA")
        assert masked.endswith("7890")
        assert "***" in masked
        assert len(masked) < len(settings.airtable_token)
    
    def test_get_masked_token_short(self):
        """Test token masking for short tokens"""
        settings = Settings(
            airtable_token="patABCD123456789012345"  # Minimum length
        )
        
        masked = settings.get_masked_token()
        assert masked == "***" or (masked.startswith("patA") and masked.endswith("2345"))


if __name__ == "__main__":
    pytest.main([__file__])