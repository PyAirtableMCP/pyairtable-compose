from sqlalchemy import Column, Integer, String, DateTime, Text, Enum, BigInteger
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func
from enum import Enum as PyEnum
from datetime import datetime

Base = declarative_base()

class FileStatus(PyEnum):
    UPLOADED = "uploaded"
    PROCESSING = "processing"
    PROCESSED = "processed"
    FAILED = "failed"
    DELETED = "deleted"

class File(Base):
    __tablename__ = "files"
    
    id = Column(Integer, primary_key=True, index=True)
    filename = Column(String(255), nullable=False)
    original_filename = Column(String(255), nullable=False)
    file_path = Column(String(500), nullable=False)
    mime_type = Column(String(100), nullable=False)
    file_size = Column(BigInteger, nullable=False)  # Size in bytes
    file_hash = Column(String(64), nullable=True)  # SHA-256 hash
    
    # Processing status
    status = Column(Enum(FileStatus), default=FileStatus.UPLOADED, nullable=False)
    
    # Extracted content
    extracted_content = Column(Text, nullable=True)
    extraction_metadata = Column(Text, nullable=True)  # JSON string
    
    # Error handling
    error_message = Column(Text, nullable=True)
    retry_count = Column(Integer, default=0)
    
    # Workflow integration
    triggered_workflows = Column(Text, nullable=True)  # JSON array of workflow IDs
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    processed_at = Column(DateTime(timezone=True), nullable=True)
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    
    def __repr__(self):
        return f"<File(id={self.id}, filename='{self.filename}', status='{self.status.value}')>"
    
    @property
    def is_processable(self) -> bool:
        """Check if file can be processed"""
        return self.status in [FileStatus.UPLOADED, FileStatus.FAILED] and self.retry_count < 3
    
    @property
    def file_extension(self) -> str:
        """Get file extension"""
        return self.original_filename.split('.')[-1].lower() if '.' in self.original_filename else ""