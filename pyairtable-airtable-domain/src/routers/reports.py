"""Report generation and management endpoints."""

from typing import Any, Dict, List, Optional
from datetime import datetime

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field

from ..services.reports import ReportEngine, ReportTemplate, ReportType
from ..services.airtable_service import AirtableService
from ..utils.exceptions import BusinessLogicError
from ..utils.redis_client import RedisCache

router = APIRouter()

# Global instances (in production, these would be dependency-injected)
_report_engine: Optional[ReportEngine] = None


def get_report_engine() -> ReportEngine:
    """Get or create report engine instance."""
    global _report_engine
    if _report_engine is None:
        # In production, these would be properly injected
        from ..core.config import get_airtable_settings
        airtable_service = AirtableService()
        cache = RedisCache()
        _report_engine = ReportEngine(airtable_service, cache)
    return _report_engine


class ReportGenerationRequest(BaseModel):
    """Request to generate a report."""
    template_id: str
    parameters: Dict[str, Any] = Field(default_factory=dict)
    report_id: Optional[str] = None
    output_format: str = "json"


class ReportTemplateRequest(BaseModel):
    """Request to create a report template."""
    template_id: str
    name: str
    report_type: str  # ReportType enum value
    description: str = ""
    sections: List[Dict[str, Any]] = Field(default_factory=list)
    data_sources: Dict[str, Dict[str, Any]] = Field(default_factory=dict)
    parameters: Dict[str, Any] = Field(default_factory=dict)


class UpdateTemplateRequest(BaseModel):
    """Request to update a report template."""
    name: Optional[str] = None
    description: Optional[str] = None
    sections: Optional[List[Dict[str, Any]]] = None
    data_sources: Optional[Dict[str, Dict[str, Any]]] = None
    parameters: Optional[Dict[str, Any]] = None


@router.post("/generate", response_model=Dict[str, Any])
async def generate_report(request: ReportGenerationRequest):
    """Generate a report from a template."""
    try:
        engine = get_report_engine()
        
        report = await engine.generate_report(
            template_id=request.template_id,
            parameters=request.parameters,
            report_id=request.report_id
        )
        
        return {
            "success": True,
            "report": {
                "report_id": report.report_id,
                "template_id": report.template.template_id,
                "status": report.status.value,
                "sections_data": report.sections_data,
                "metadata": {
                    "generated_at": report.metadata.generated_at.isoformat() if report.metadata else None,
                    "generation_time_ms": report.metadata.generation_time_ms if report.metadata else None,
                    "record_count": report.metadata.record_count if report.metadata else None,
                    "data_sources_used": report.metadata.data_sources_used if report.metadata else [],
                    "cache_used": report.metadata.cache_used if report.metadata else False,
                    "warnings": report.metadata.warnings if report.metadata else [],
                    "errors": report.metadata.errors if report.metadata else []
                } if report.metadata else None,
                "created_at": report.created_at.isoformat(),
                "completed_at": report.completed_at.isoformat() if report.completed_at else None
            }
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/reports/{report_id}", response_model=Dict[str, Any])
async def get_report(report_id: str):
    """Get a specific report."""
    try:
        engine = get_report_engine()
        report = engine.get_report(report_id)
        
        if not report:
            raise HTTPException(status_code=404, detail=f"Report '{report_id}' not found")
        
        return {
            "success": True,
            "report": report.to_dict()
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/reports", response_model=Dict[str, Any])
async def list_reports(status: Optional[str] = None):
    """List all reports, optionally filtered by status."""
    try:
        engine = get_report_engine()
        
        if status:
            from ..services.reports.report_engine import ReportStatus
            filter_status = ReportStatus(status)
            reports = engine.list_reports(filter_status)
        else:
            reports = engine.list_reports()
        
        return {
            "success": True,
            "reports": [
                {
                    "report_id": report.report_id,
                    "template_id": report.template.template_id,
                    "status": report.status.value,
                    "created_at": report.created_at.isoformat(),
                    "completed_at": report.completed_at.isoformat() if report.completed_at else None,
                    "metadata": {
                        "record_count": report.metadata.record_count if report.metadata else None,
                        "generation_time_ms": report.metadata.generation_time_ms if report.metadata else None,
                        "errors_count": len(report.metadata.errors) if report.metadata else 0
                    } if report.metadata else None
                }
                for report in reports
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/reports/{report_id}", response_model=Dict[str, Any])
async def cancel_report(report_id: str):
    """Cancel a pending or processing report."""
    try:
        engine = get_report_engine()
        success = await engine.cancel_report(report_id)
        
        if success:
            return {
                "success": True,
                "message": f"Report '{report_id}' cancelled successfully"
            }
        else:
            raise HTTPException(
                status_code=400, 
                detail=f"Report '{report_id}' cannot be cancelled (not found or not in cancellable state)"
            )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Template management endpoints
@router.post("/templates", response_model=Dict[str, Any])
async def create_template(request: ReportTemplateRequest):
    """Create a new report template."""
    try:
        engine = get_report_engine()
        
        # Create template
        template = ReportTemplate(
            template_id=request.template_id,
            name=request.name,
            report_type=ReportType(request.report_type)
        )
        
        template.description = request.description
        template.parameters = request.parameters
        
        # Add data sources
        from ..services.reports.report_engine import DataSource, DataSourceType
        for name, ds_config in request.data_sources.items():
            data_source = DataSource(
                source_type=DataSourceType(ds_config["source_type"]),
                name=name,
                configuration=ds_config.get("configuration", {}),
                filters=ds_config.get("filters", {}),
                transformations=ds_config.get("transformations", [])
            )
            template.add_data_source(data_source)
        
        # Add sections
        from ..services.reports.report_engine import ReportSection
        for section_config in request.sections:
            data_source = None
            if section_config.get("data_source_name"):
                data_source = template.data_sources.get(section_config["data_source_name"])
            
            section = ReportSection(
                section_id=section_config["section_id"],
                title=section_config["title"],
                section_type=section_config["section_type"],
                data_source=data_source,
                configuration=section_config.get("configuration", {}),
                template=section_config.get("template"),
                order=section_config.get("order", 0)
            )
            template.add_section(section)
        
        # Register template
        engine.register_template(template)
        
        return {
            "success": True,
            "template_id": request.template_id,
            "message": f"Template '{request.template_id}' created successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/templates", response_model=Dict[str, Any])
async def list_templates():
    """List all available report templates."""
    try:
        engine = get_report_engine()
        templates = engine.list_templates()
        
        return {
            "success": True,
            "templates": [
                {
                    "template_id": template.template_id,
                    "name": template.name,
                    "report_type": template.report_type.value,
                    "description": template.description,
                    "sections_count": len(template.sections),
                    "data_sources_count": len(template.data_sources),
                    "version": template.version,
                    "created_at": template.created_at.isoformat(),
                    "updated_at": template.updated_at.isoformat()
                }
                for template in templates
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/templates/{template_id}", response_model=Dict[str, Any])
async def get_template(template_id: str):
    """Get a specific report template."""
    try:
        engine = get_report_engine()
        template = engine.get_template(template_id)
        
        if not template:
            raise HTTPException(status_code=404, detail=f"Template '{template_id}' not found")
        
        return {
            "success": True,
            "template": template.to_dict()
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/templates/{template_id}", response_model=Dict[str, Any])
async def update_template(template_id: str, request: UpdateTemplateRequest):
    """Update a report template."""
    try:
        engine = get_report_engine()
        template = engine.get_template(template_id)
        
        if not template:
            raise HTTPException(status_code=404, detail=f"Template '{template_id}' not found")
        
        # Update template properties
        if request.name is not None:
            template.name = request.name
        
        if request.description is not None:
            template.description = request.description
        
        if request.parameters is not None:
            template.parameters = request.parameters
        
        if request.data_sources is not None:
            # Clear existing data sources and add new ones
            template.data_sources.clear()
            
            from ..services.reports.report_engine import DataSource, DataSourceType
            for name, ds_config in request.data_sources.items():
                data_source = DataSource(
                    source_type=DataSourceType(ds_config["source_type"]),
                    name=name,
                    configuration=ds_config.get("configuration", {}),
                    filters=ds_config.get("filters", {}),
                    transformations=ds_config.get("transformations", [])
                )
                template.add_data_source(data_source)
        
        if request.sections is not None:
            # Clear existing sections and add new ones
            template.sections.clear()
            
            from ..services.reports.report_engine import ReportSection
            for section_config in request.sections:
                data_source = None
                if section_config.get("data_source_name"):
                    data_source = template.data_sources.get(section_config["data_source_name"])
                
                section = ReportSection(
                    section_id=section_config["section_id"],
                    title=section_config["title"],
                    section_type=section_config["section_type"],
                    data_source=data_source,
                    configuration=section_config.get("configuration", {}),
                    template=section_config.get("template"),
                    order=section_config.get("order", 0)
                )
                template.add_section(section)
        
        template.updated_at = datetime.now()
        
        return {
            "success": True,
            "template_id": template_id,
            "message": f"Template '{template_id}' updated successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/templates/{template_id}", response_model=Dict[str, Any])
async def delete_template(template_id: str):
    """Delete a report template."""
    try:
        engine = get_report_engine()
        
        if template_id not in engine.templates:
            raise HTTPException(status_code=404, detail=f"Template '{template_id}' not found")
        
        del engine.templates[template_id]
        
        return {
            "success": True,
            "message": f"Template '{template_id}' deleted successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Utility endpoints
@router.post("/cleanup", response_model=Dict[str, Any])
async def cleanup_old_reports(max_age_hours: int = 24):
    """Clean up old completed reports."""
    try:
        engine = get_report_engine()
        removed_count = engine.cleanup_completed_reports(max_age_hours)
        
        return {
            "success": True,
            "removed_count": removed_count,
            "message": f"Cleaned up {removed_count} old reports"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/export/{report_id}", response_model=Dict[str, Any])
async def export_report(report_id: str, format: str = "json"):
    """Export a report in specified format."""
    try:
        engine = get_report_engine()
        report = engine.get_report(report_id)
        
        if not report:
            raise HTTPException(status_code=404, detail=f"Report '{report_id}' not found")
        
        if format.lower() == "json":
            return {
                "success": True,
                "format": "json",
                "data": report.to_dict()
            }
        else:
            # For other formats, you would implement export logic here
            raise HTTPException(status_code=400, detail=f"Export format '{format}' not supported")
            
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))