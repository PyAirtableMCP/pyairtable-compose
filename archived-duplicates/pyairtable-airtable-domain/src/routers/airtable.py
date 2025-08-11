"""Airtable API routes with enhanced features."""

from typing import List, Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, Body, Request
from fastapi.responses import JSONResponse

from ..services.airtable_service import AirtableService
from ..utils.redis_client import RedisCache
from ..models.airtable import (
    CreateRecordRequest,
    UpdateRecordRequest,
    DeleteRecordsRequest,
    CacheInvalidationRequest,
    AirtableRecord,
    AirtableRecordBatch,
    AirtableBaseSchema,
    AirtableTableSchema,
)
from ..core.logging import get_logger

logger = get_logger(__name__)
router = APIRouter()


async def get_airtable_service() -> AirtableService:
    """Get Airtable service instance."""
    cache = RedisCache()
    return AirtableService(cache)


def get_request_context(request: Request) -> tuple[Optional[str], Optional[str]]:
    """Extract user ID and request ID from request."""
    user_id = getattr(request.state, "user_id", None)
    request_id = getattr(request.state, "request_id", str(uuid4()))
    return user_id, request_id


@router.get("/bases", response_model=List[AirtableBaseSchema])
async def list_bases(
    request: Request,
    service: AirtableService = Depends(get_airtable_service)
):
    """List all accessible Airtable bases."""
    user_id, request_id = get_request_context(request)
    
    try:
        bases = await service.list_bases(user_id=user_id, request_id=request_id)
        return bases
    except Exception as e:
        logger.error("Failed to list bases", error=str(e), user_id=user_id, request_id=request_id)
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await service.close()


@router.get("/bases/{base_id}/schema", response_model=dict)
async def get_base_schema(
    base_id: str,
    request: Request,
    service: AirtableService = Depends(get_airtable_service)
):
    """Get schema for a specific base."""
    user_id, request_id = get_request_context(request)
    
    try:
        schema = await service.get_base_schema(base_id, user_id=user_id, request_id=request_id)
        return schema
    except Exception as e:
        logger.error(
            "Failed to get base schema",
            error=str(e),
            base_id=base_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await service.close()


@router.get("/bases/{base_id}/tables/{table_id}/records", response_model=AirtableRecordBatch)
async def list_records(
    base_id: str,
    table_id: str,
    request: Request,
    view: Optional[str] = Query(None, description="View name or ID"),
    max_records: Optional[int] = Query(None, ge=1, le=100, description="Maximum records to return"),
    page_size: Optional[int] = Query(None, ge=1, le=100, description="Page size"),
    offset: Optional[str] = Query(None, description="Pagination offset"),
    fields: Optional[List[str]] = Query(None, description="Fields to include"),
    filter_by_formula: Optional[str] = Query(None, description="Filter formula"),
    sort_field: Optional[str] = Query(None, description="Sort field"),
    sort_direction: Optional[str] = Query("asc", regex="^(asc|desc)$", description="Sort direction"),
    service: AirtableService = Depends(get_airtable_service)
):
    """List records from a table with advanced filtering and pagination."""
    user_id, request_id = get_request_context(request)
    
    try:
        sort = None
        if sort_field:
            sort = [{"field": sort_field, "direction": sort_direction}]
        
        records = await service.list_records(
            base_id=base_id,
            table_id=table_id,
            view=view,
            max_records=max_records,
            page_size=page_size,
            offset=offset,
            fields=fields,
            filter_by_formula=filter_by_formula,
            sort=sort,
            user_id=user_id,
            request_id=request_id
        )
        
        return records
    except Exception as e:
        logger.error(
            "Failed to list records",
            error=str(e),
            base_id=base_id,
            table_id=table_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await service.close()


@router.get("/bases/{base_id}/tables/{table_id}/records/{record_id}", response_model=AirtableRecord)
async def get_record(
    base_id: str,
    table_id: str,
    record_id: str,
    request: Request,
    service: AirtableService = Depends(get_airtable_service)
):
    """Get a single record by ID."""
    user_id, request_id = get_request_context(request)
    
    try:
        record = await service.get_record(
            base_id, table_id, record_id, user_id=user_id, request_id=request_id
        )
        return record
    except Exception as e:
        logger.error(
            "Failed to get record",
            error=str(e),
            base_id=base_id,
            table_id=table_id,
            record_id=record_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await service.close()


@router.post("/bases/{base_id}/tables/{table_id}/records")
async def create_records(
    base_id: str,
    table_id: str,
    request: Request,
    record_request: CreateRecordRequest,
    service: AirtableService = Depends(get_airtable_service)
):
    """Create new records in a table."""
    user_id, request_id = get_request_context(request)
    
    try:
        # Format records for Airtable API
        formatted_records = [{"fields": record} for record in record_request.records]
        
        result = await service.create_records(
            base_id,
            table_id,
            formatted_records,
            typecast=record_request.typecast,
            user_id=user_id,
            request_id=request_id
        )
        
        return result
    except ValueError as e:
        logger.warning(
            "Invalid create records request",
            error=str(e),
            base_id=base_id,
            table_id=table_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(
            "Failed to create records",
            error=str(e),
            base_id=base_id,
            table_id=table_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await service.close()


@router.patch("/bases/{base_id}/tables/{table_id}/records")
async def update_records(
    base_id: str,
    table_id: str,
    request: Request,
    update_request: UpdateRecordRequest,
    service: AirtableService = Depends(get_airtable_service)
):
    """Update existing records (partial update)."""
    user_id, request_id = get_request_context(request)
    
    try:
        # Format records for Airtable API
        formatted_records = []
        for record in update_request.records:
            formatted_records.append({
                "id": record["id"],
                "fields": {k: v for k, v in record.items() if k != "id"}
            })
        
        result = await service.update_records(
            base_id,
            table_id,
            formatted_records,
            typecast=update_request.typecast,
            replace=False,
            user_id=user_id,
            request_id=request_id
        )
        
        return result
    except ValueError as e:
        logger.warning(
            "Invalid update records request",
            error=str(e),
            base_id=base_id,
            table_id=table_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(
            "Failed to update records",
            error=str(e),
            base_id=base_id,
            table_id=table_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await service.close()


@router.put("/bases/{base_id}/tables/{table_id}/records")
async def replace_records(
    base_id: str,
    table_id: str,
    request: Request,
    update_request: UpdateRecordRequest,
    service: AirtableService = Depends(get_airtable_service)
):
    """Replace existing records (full update)."""
    user_id, request_id = get_request_context(request)
    
    try:
        # Format records for Airtable API
        formatted_records = []
        for record in update_request.records:
            formatted_records.append({
                "id": record["id"],
                "fields": {k: v for k, v in record.items() if k != "id"}
            })
        
        result = await service.update_records(
            base_id,
            table_id,
            formatted_records,
            typecast=update_request.typecast,
            replace=True,
            user_id=user_id,
            request_id=request_id
        )
        
        return result
    except ValueError as e:
        logger.warning(
            "Invalid replace records request",
            error=str(e),
            base_id=base_id,
            table_id=table_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(
            "Failed to replace records",
            error=str(e),
            base_id=base_id,
            table_id=table_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await service.close()


@router.delete("/bases/{base_id}/tables/{table_id}/records")
async def delete_records(
    base_id: str,
    table_id: str,
    request: Request,
    delete_request: DeleteRecordsRequest,
    service: AirtableService = Depends(get_airtable_service)
):
    """Delete records from a table."""
    user_id, request_id = get_request_context(request)
    
    try:
        result = await service.delete_records(
            base_id,
            table_id,
            delete_request.record_ids,
            user_id=user_id,
            request_id=request_id
        )
        
        return result
    except ValueError as e:
        logger.warning(
            "Invalid delete records request",
            error=str(e),
            base_id=base_id,
            table_id=table_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(
            "Failed to delete records",
            error=str(e),
            base_id=base_id,
            table_id=table_id,
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await service.close()


@router.post("/cache/invalidate")
async def invalidate_cache(
    request: Request,
    invalidation_request: CacheInvalidationRequest,
    service: AirtableService = Depends(get_airtable_service)
):
    """Invalidate cache entries with flexible patterns."""
    user_id, request_id = get_request_context(request)
    
    try:
        deleted_count = await service.invalidate_cache(
            pattern=invalidation_request.pattern,
            base_id=invalidation_request.base_id,
            table_id=invalidation_request.table_id,
        )
        
        logger.info(
            "Cache invalidated",
            deleted_count=deleted_count,
            pattern=invalidation_request.pattern,
            base_id=invalidation_request.base_id,
            table_id=invalidation_request.table_id,
            user_id=user_id,
            request_id=request_id
        )
        
        return {
            "status": "success",
            "message": f"Cache invalidated successfully",
            "deleted_count": deleted_count,
            "pattern": invalidation_request.pattern,
            "base_id": invalidation_request.base_id,
            "table_id": invalidation_request.table_id,
        }
    except Exception as e:
        logger.error(
            "Failed to invalidate cache",
            error=str(e),
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await service.close()


@router.get("/stats")
async def get_operation_stats(
    request: Request,
    base_id: Optional[str] = Query(None, description="Filter by base ID"),
    service: AirtableService = Depends(get_airtable_service)
):
    """Get operation statistics and metrics."""
    user_id, request_id = get_request_context(request)
    
    try:
        stats = await service.get_operation_stats(base_id=base_id, user_id=user_id)
        return stats
    except Exception as e:
        logger.error(
            "Failed to get operation stats",
            error=str(e),
            user_id=user_id,
            request_id=request_id
        )
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await service.close()