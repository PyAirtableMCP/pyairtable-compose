import os
import hashlib
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, BackgroundTasks
from sqlalchemy.orm import Session
from pydantic import BaseModel

from ..database import get_db
from ..models.files import File as FileModel, FileStatus
from ..services.file_service import FileService
from ..utils.auth import verify_api_key

router = APIRouter()

# Pydantic models for API
class FileResponse(BaseModel):
    id: int
    filename: str
    original_filename: str
    mime_type: str
    file_size: int
    status: str
    extracted_content: Optional[str] = None
    created_at: str
    updated_at: str
    processed_at: Optional[str] = None

class FileUploadResponse(BaseModel):
    id: int
    filename: str
    message: str
    status: str

class ProcessFileRequest(BaseModel):
    extract_content: bool = True
    trigger_workflows: bool = True

@router.post("/upload", response_model=FileUploadResponse)
async def upload_file(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Upload a file for processing"""
    file_service = FileService(db)
    
    try:
        # Create file record and save to disk
        file_record = await file_service.upload_file(file)
        
        # Schedule background processing
        background_tasks.add_task(
            file_service.process_file_async,
            file_record.id
        )
        
        return FileUploadResponse(
            id=file_record.id,
            filename=file_record.filename,
            message="File uploaded successfully",
            status=file_record.status.value
        )
        
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

@router.get("/{file_id}", response_model=FileResponse)
async def get_file(
    file_id: int,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Get file information"""
    file_service = FileService(db)
    file_record = file_service.get_file(file_id)
    
    if not file_record:
        raise HTTPException(status_code=404, detail="File not found")
    
    return FileResponse(
        id=file_record.id,
        filename=file_record.filename,
        original_filename=file_record.original_filename,
        mime_type=file_record.mime_type,
        file_size=file_record.file_size,
        status=file_record.status.value,
        extracted_content=file_record.extracted_content,
        created_at=file_record.created_at.isoformat(),
        updated_at=file_record.updated_at.isoformat(),
        processed_at=file_record.processed_at.isoformat() if file_record.processed_at else None
    )

@router.post("/{file_id}/process")
async def process_file(
    file_id: int,
    background_tasks: BackgroundTasks,
    request: ProcessFileRequest = ProcessFileRequest(),
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Process an uploaded file"""
    file_service = FileService(db)
    file_record = file_service.get_file(file_id)
    
    if not file_record:
        raise HTTPException(status_code=404, detail="File not found")
    
    if not file_record.is_processable:
        raise HTTPException(
            status_code=400, 
            detail=f"File cannot be processed (status: {file_record.status.value})"
        )
    
    # Schedule background processing
    background_tasks.add_task(
        file_service.process_file_async,
        file_id,
        request.extract_content,
        request.trigger_workflows
    )
    
    return {"message": "File processing started", "file_id": file_id}

@router.get("/{file_id}/extract")
async def extract_file_content(
    file_id: int,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Extract content from a processed file"""
    file_service = FileService(db)
    file_record = file_service.get_file(file_id)
    
    if not file_record:
        raise HTTPException(status_code=404, detail="File not found")
    
    if file_record.status != FileStatus.PROCESSED:
        raise HTTPException(
            status_code=400,
            detail=f"File not processed yet (status: {file_record.status.value})"
        )
    
    return {
        "file_id": file_id,
        "content": file_record.extracted_content,
        "metadata": file_record.extraction_metadata
    }

@router.delete("/{file_id}")
async def delete_file(
    file_id: int,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Delete a file"""
    file_service = FileService(db)
    
    if not file_service.delete_file(file_id):
        raise HTTPException(status_code=404, detail="File not found")
    
    return {"message": "File deleted successfully", "file_id": file_id}

@router.get("", response_model=List[FileResponse])
async def list_files(
    status: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """List files with optional filtering"""
    file_service = FileService(db)
    files = file_service.list_files(status=status, limit=limit, offset=offset)
    
    return [
        FileResponse(
            id=f.id,
            filename=f.filename,
            original_filename=f.original_filename,
            mime_type=f.mime_type,
            file_size=f.file_size,
            status=f.status.value,
            extracted_content=f.extracted_content,
            created_at=f.created_at.isoformat(),
            updated_at=f.updated_at.isoformat(),
            processed_at=f.processed_at.isoformat() if f.processed_at else None
        )
        for f in files
    ]