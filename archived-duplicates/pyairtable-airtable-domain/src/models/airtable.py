"""Airtable-related data models."""

from datetime import datetime
from typing import Any, Dict, List, Optional
from uuid import UUID

from pydantic import BaseModel, Field, validator
from sqlalchemy import Column, String, Text, JSON, Integer, Boolean, DateTime
from sqlalchemy.dialects.postgresql import UUID as PGUUID

from ..database.base import Base


# SQLAlchemy Models

class AirtableBase(Base):
    """Airtable base information."""
    
    __tablename__ = "airtable_bases"
    
    airtable_id = Column(String(20), unique=True, nullable=False, index=True)
    name = Column(String(255), nullable=False)
    permission_level = Column(String(50), nullable=False)
    workspace_id = Column(String(20), nullable=True)
    schema_data = Column(JSON, nullable=True)
    last_schema_update = Column(DateTime(timezone=True), nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)


class AirtableTable(Base):
    """Airtable table information."""
    
    __tablename__ = "airtable_tables"
    
    airtable_id = Column(String(20), unique=True, nullable=False, index=True)
    base_airtable_id = Column(String(20), nullable=False, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    primary_field_id = Column(String(20), nullable=True)
    fields_data = Column(JSON, nullable=True)
    views_data = Column(JSON, nullable=True)
    last_schema_update = Column(DateTime(timezone=True), nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)


class AirtableOperation(Base):
    """Track Airtable API operations for auditing and rate limiting."""
    
    __tablename__ = "airtable_operations"
    
    operation_type = Column(String(50), nullable=False, index=True)  # GET, POST, PATCH, DELETE
    endpoint = Column(String(500), nullable=False)
    base_id = Column(String(20), nullable=True, index=True)
    table_id = Column(String(20), nullable=True, index=True)
    record_count = Column(Integer, nullable=True)
    response_status = Column(Integer, nullable=False)
    response_time_ms = Column(Integer, nullable=True)
    error_message = Column(Text, nullable=True)
    user_id = Column(String(255), nullable=True, index=True)
    request_id = Column(String(255), nullable=True, index=True)


# Pydantic Models

class AirtableBaseSchema(BaseModel):
    """Airtable base schema."""
    
    id: str = Field(..., description="Airtable base ID")
    name: str = Field(..., description="Base name")
    permission_level: str = Field(..., description="Permission level")
    
    class Config:
        from_attributes = True


class AirtableFieldSchema(BaseModel):
    """Airtable field schema."""
    
    id: str = Field(..., description="Field ID")
    name: str = Field(..., description="Field name")
    type: str = Field(..., description="Field type")
    description: Optional[str] = Field(None, description="Field description")
    options: Optional[Dict[str, Any]] = Field(None, description="Field options")
    
    class Config:
        from_attributes = True


class AirtableViewSchema(BaseModel):
    """Airtable view schema."""
    
    id: str = Field(..., description="View ID")
    name: str = Field(..., description="View name")
    type: str = Field(..., description="View type")
    
    class Config:
        from_attributes = True


class AirtableTableSchema(BaseModel):
    """Airtable table schema."""
    
    id: str = Field(..., description="Table ID")
    name: str = Field(..., description="Table name")
    description: Optional[str] = Field(None, description="Table description")
    primary_field_id: str = Field(..., description="Primary field ID")
    fields: List[AirtableFieldSchema] = Field(..., description="Table fields")
    views: List[AirtableViewSchema] = Field(..., description="Table views")
    
    class Config:
        from_attributes = True


class AirtableRecord(BaseModel):
    """Airtable record data."""
    
    id: str = Field(..., description="Record ID")
    fields: Dict[str, Any] = Field(..., description="Record fields")
    created_time: Optional[datetime] = Field(None, description="Record creation time")
    
    class Config:
        from_attributes = True


class AirtableRecordBatch(BaseModel):
    """Batch of Airtable records."""
    
    records: List[AirtableRecord] = Field(..., description="Records in the batch")
    offset: Optional[str] = Field(None, description="Pagination offset")
    
    class Config:
        from_attributes = True


class CreateRecordRequest(BaseModel):
    """Request to create records."""
    
    records: List[Dict[str, Any]] = Field(..., description="Records to create", max_items=10)
    typecast: bool = Field(False, description="Enable automatic type casting")
    
    @validator("records")
    def validate_records(cls, v):
        """Validate records structure."""
        if not v:
            raise ValueError("At least one record is required")
        return v


class UpdateRecordRequest(BaseModel):
    """Request to update records."""
    
    records: List[Dict[str, Any]] = Field(..., description="Records to update", max_items=10)
    typecast: bool = Field(False, description="Enable automatic type casting")
    
    @validator("records")
    def validate_records(cls, v):
        """Validate records structure."""
        if not v:
            raise ValueError("At least one record is required")
        
        for record in v:
            if "id" not in record:
                raise ValueError("Each record must have an 'id' field")
        
        return v


class DeleteRecordsRequest(BaseModel):
    """Request to delete records."""
    
    record_ids: List[str] = Field(..., description="Record IDs to delete", max_items=10)
    
    @validator("record_ids")
    def validate_record_ids(cls, v):
        """Validate record IDs."""
        if not v:
            raise ValueError("At least one record ID is required")
        return v


class AirtableOperationLog(BaseModel):
    """Airtable operation log entry."""
    
    id: UUID
    operation_type: str
    endpoint: str
    base_id: Optional[str]
    table_id: Optional[str]
    record_count: Optional[int]
    response_status: int
    response_time_ms: Optional[int]
    error_message: Optional[str]
    user_id: Optional[str]
    request_id: Optional[str]
    created_at: datetime
    
    class Config:
        from_attributes = True


class CacheInvalidationRequest(BaseModel):
    """Request to invalidate cache."""
    
    pattern: Optional[str] = Field(None, description="Cache key pattern to invalidate")
    base_id: Optional[str] = Field(None, description="Invalidate cache for specific base")
    table_id: Optional[str] = Field(None, description="Invalidate cache for specific table")