import os
import hashlib
import mimetypes
from datetime import datetime
from typing import List, Optional
from fastapi import UploadFile
from sqlalchemy.orm import Session
from sqlalchemy import and_

from ..models.files import File, FileStatus
from ..config import settings
from ..utils.file_utils import extract_file_content, validate_file_extension
from .workflow_service import WorkflowService
import json
import logging

logger = logging.getLogger(__name__)

class FileService:
    def __init__(self, db: Session):
        self.db = db
    
    async def upload_file(self, file: UploadFile) -> File:
        """Upload a file and create database record"""
        # Validate file
        if not file.filename:
            raise ValueError("No filename provided")
        
        # Check file extension
        if not validate_file_extension(file.filename, settings.allowed_extensions_list):
            raise ValueError(f"File type not allowed. Allowed types: {settings.allowed_extensions}")
        
        # Check file size
        content = await file.read()
        if len(content) > settings.max_file_size_bytes:
            raise ValueError(f"File too large. Maximum size: {settings.max_file_size}")
        
        # Create upload directory if it doesn't exist
        os.makedirs(settings.upload_dir, exist_ok=True)
        
        # Generate unique filename
        file_hash = hashlib.sha256(content).hexdigest()
        file_extension = file.filename.split('.')[-1] if '.' in file.filename else ''
        unique_filename = f"{file_hash}.{file_extension}" if file_extension else file_hash
        file_path = os.path.join(settings.upload_dir, unique_filename)
        
        # Save file to disk
        with open(file_path, 'wb') as f:
            f.write(content)
        
        # Determine MIME type
        mime_type, _ = mimetypes.guess_type(file.filename)
        if not mime_type:
            mime_type = 'application/octet-stream'
        
        # Create database record
        file_record = File(
            filename=unique_filename,
            original_filename=file.filename,
            file_path=file_path,
            mime_type=mime_type,
            file_size=len(content),
            file_hash=file_hash,
            status=FileStatus.UPLOADED
        )
        
        self.db.add(file_record)
        self.db.commit()
        self.db.refresh(file_record)
        
        logger.info(f"File uploaded: {file_record.id} - {file.filename}")
        return file_record
    
    def get_file(self, file_id: int) -> Optional[File]:
        """Get file by ID"""
        return self.db.query(File).filter(
            and_(File.id == file_id, File.status != FileStatus.DELETED)
        ).first()
    
    def list_files(self, status: Optional[str] = None, limit: int = 100, offset: int = 0) -> List[File]:
        """List files with optional filtering"""
        query = self.db.query(File).filter(File.status != FileStatus.DELETED)
        
        if status:
            try:
                status_enum = FileStatus(status)
                query = query.filter(File.status == status_enum)
            except ValueError:
                pass  # Invalid status, ignore filter
        
        return query.offset(offset).limit(limit).all()
    
    async def process_file_async(self, file_id: int, extract_content: bool = True, trigger_workflows: bool = True):
        """Process file asynchronously"""
        try:
            file_record = self.get_file(file_id)
            if not file_record or not file_record.is_processable:
                return
            
            # Update status to processing
            file_record.status = FileStatus.PROCESSING
            self.db.commit()
            
            logger.info(f"Processing file: {file_id}")
            
            # Extract content if requested
            if extract_content:
                try:
                    content, metadata = extract_file_content(file_record.file_path, file_record.mime_type)
                    file_record.extracted_content = content
                    file_record.extraction_metadata = json.dumps(metadata) if metadata else None
                except Exception as e:
                    logger.error(f"Content extraction failed for file {file_id}: {str(e)}")
            
            # Update status to processed
            file_record.status = FileStatus.PROCESSED
            file_record.processed_at = datetime.utcnow()
            file_record.error_message = None
            self.db.commit()
            
            logger.info(f"File processed successfully: {file_id}")
            
            # Trigger workflows if requested
            if trigger_workflows:
                await self._trigger_file_workflows(file_record)
                
        except Exception as e:
            logger.error(f"File processing failed for {file_id}: {str(e)}")
            file_record = self.get_file(file_id)
            if file_record:
                file_record.status = FileStatus.FAILED
                file_record.error_message = str(e)
                file_record.retry_count += 1
                self.db.commit()
    
    async def _trigger_file_workflows(self, file_record: File):
        """Trigger workflows that should run on file upload"""
        try:
            workflow_service = WorkflowService(self.db)
            workflows = workflow_service.get_file_trigger_workflows(file_record.file_extension)
            
            triggered_workflow_ids = []
            
            for workflow in workflows:
                try:
                    execution = workflow_service.create_execution(
                        workflow_id=workflow.id,
                        trigger_type="file_upload",
                        trigger_data={
                            "file_id": file_record.id,
                            "filename": file_record.filename,
                            "file_extension": file_record.file_extension
                        }
                    )
                    
                    # Execute workflow in background
                    await workflow_service.execute_workflow_async(execution.id)
                    triggered_workflow_ids.append(workflow.id)
                    
                except Exception as e:
                    logger.error(f"Failed to trigger workflow {workflow.id} for file {file_record.id}: {str(e)}")
            
            # Update file record with triggered workflows
            if triggered_workflow_ids:
                file_record.triggered_workflows = json.dumps(triggered_workflow_ids)
                self.db.commit()
                
                logger.info(f"Triggered {len(triggered_workflow_ids)} workflows for file {file_record.id}")
                
        except Exception as e:
            logger.error(f"Failed to trigger workflows for file {file_record.id}: {str(e)}")
    
    def delete_file(self, file_id: int) -> bool:
        """Delete file (soft delete)"""
        file_record = self.get_file(file_id)
        if not file_record:
            return False
        
        # Soft delete
        file_record.status = FileStatus.DELETED
        file_record.deleted_at = datetime.utcnow()
        
        # Optionally delete physical file
        try:
            if os.path.exists(file_record.file_path):
                os.remove(file_record.file_path)
        except Exception as e:
            logger.error(f"Failed to delete physical file {file_record.file_path}: {str(e)}")
        
        self.db.commit()
        logger.info(f"File deleted: {file_id}")
        return True