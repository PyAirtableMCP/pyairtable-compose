"""Core report generation engine with templates and data processing."""

import asyncio
import json
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Union, Callable
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from ..business_logic import CalculationService, FormulaEngine
from ...core.logging import get_logger
from ...utils.exceptions import BusinessLogicError
from ...utils.redis_client import RedisCache
from ...services.airtable_service import AirtableService

logger = get_logger(__name__)


class ReportType(Enum):
    """Types of reports."""
    TABLE_SUMMARY = "table_summary"
    ANALYTICS_DASHBOARD = "analytics_dashboard"
    CUSTOM_QUERY = "custom_query"
    SCHEDULED_DIGEST = "scheduled_digest"
    EXPORT_REPORT = "export_report"
    AUDIT_REPORT = "audit_report"


class ReportStatus(Enum):
    """Report generation status."""
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class DataSourceType(Enum):
    """Types of data sources for reports."""
    AIRTABLE = "airtable"
    DATABASE = "database"
    API = "api"
    FILE = "file"
    FORMULA = "formula"


@dataclass
class DataSource:
    """Configuration for a report data source."""
    source_type: DataSourceType
    name: str
    configuration: Dict[str, Any] = field(default_factory=dict)
    filters: Dict[str, Any] = field(default_factory=dict)
    transformations: List[str] = field(default_factory=list)


@dataclass
class ReportSection:
    """Individual section of a report."""
    section_id: str
    title: str
    section_type: str  # chart, table, text, image, etc.
    data_source: Optional[DataSource] = None
    configuration: Dict[str, Any] = field(default_factory=dict)
    template: Optional[str] = None
    order: int = 0


@dataclass
class ReportMetadata:
    """Metadata for report generation and tracking."""
    generated_at: datetime
    generation_time_ms: int
    record_count: int
    data_sources_used: List[str]
    cache_used: bool = False
    warnings: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)


class ReportTemplate:
    """Template for generating reports."""
    
    def __init__(self, template_id: str, name: str, report_type: ReportType):
        self.template_id = template_id
        self.name = name
        self.report_type = report_type
        self.description = ""
        self.sections: List[ReportSection] = []
        self.data_sources: Dict[str, DataSource] = {}
        self.parameters: Dict[str, Any] = {}
        self.created_at = datetime.now()
        self.updated_at = datetime.now()
        self.version = "1.0.0"
    
    def add_section(self, section: ReportSection) -> 'ReportTemplate':
        """Add a section to the template."""
        self.sections.append(section)
        self.sections.sort(key=lambda s: s.order)
        self.updated_at = datetime.now()
        return self
    
    def add_data_source(self, data_source: DataSource) -> 'ReportTemplate':
        """Add a data source to the template."""
        self.data_sources[data_source.name] = data_source
        self.updated_at = datetime.now()
        return self
    
    def get_section(self, section_id: str) -> Optional[ReportSection]:
        """Get a section by ID."""
        for section in self.sections:
            if section.section_id == section_id:
                return section
        return None
    
    def remove_section(self, section_id: str) -> bool:
        """Remove a section from the template."""
        for i, section in enumerate(self.sections):
            if section.section_id == section_id:
                del self.sections[i]
                self.updated_at = datetime.now()
                return True
        return False
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert template to dictionary."""
        return {
            "template_id": self.template_id,
            "name": self.name,
            "report_type": self.report_type.value,
            "description": self.description,
            "sections": [
                {
                    "section_id": s.section_id,
                    "title": s.title,
                    "section_type": s.section_type,
                    "data_source": {
                        "source_type": s.data_source.source_type.value,
                        "name": s.data_source.name,
                        "configuration": s.data_source.configuration,
                        "filters": s.data_source.filters,
                        "transformations": s.data_source.transformations
                    } if s.data_source else None,
                    "configuration": s.configuration,
                    "template": s.template,
                    "order": s.order
                }
                for s in self.sections
            ],
            "data_sources": {
                name: {
                    "source_type": ds.source_type.value,
                    "name": ds.name,
                    "configuration": ds.configuration,
                    "filters": ds.filters,
                    "transformations": ds.transformations
                }
                for name, ds in self.data_sources.items()
            },
            "parameters": self.parameters,
            "version": self.version,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat()
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'ReportTemplate':
        """Create template from dictionary."""
        template = cls(
            template_id=data["template_id"],
            name=data["name"],
            report_type=ReportType(data["report_type"])
        )
        
        template.description = data.get("description", "")
        template.parameters = data.get("parameters", {})
        template.version = data.get("version", "1.0.0")
        
        # Add data sources
        for name, ds_data in data.get("data_sources", {}).items():
            data_source = DataSource(
                source_type=DataSourceType(ds_data["source_type"]),
                name=ds_data["name"],
                configuration=ds_data.get("configuration", {}),
                filters=ds_data.get("filters", {}),
                transformations=ds_data.get("transformations", [])
            )
            template.add_data_source(data_source)
        
        # Add sections
        for section_data in data.get("sections", []):
            data_source = None
            if section_data.get("data_source"):
                ds_data = section_data["data_source"]
                data_source = DataSource(
                    source_type=DataSourceType(ds_data["source_type"]),
                    name=ds_data["name"],
                    configuration=ds_data.get("configuration", {}),
                    filters=ds_data.get("filters", {}),
                    transformations=ds_data.get("transformations", [])
                )
            
            section = ReportSection(
                section_id=section_data["section_id"],
                title=section_data["title"],
                section_type=section_data["section_type"],
                data_source=data_source,
                configuration=section_data.get("configuration", {}),
                template=section_data.get("template"),
                order=section_data.get("order", 0)
            )
            template.add_section(section)
        
        # Set timestamps
        if "created_at" in data:
            template.created_at = datetime.fromisoformat(data["created_at"])
        if "updated_at" in data:
            template.updated_at = datetime.fromisoformat(data["updated_at"])
        
        return template


class Report:
    """Generated report instance."""
    
    def __init__(self, report_id: str, template: ReportTemplate, parameters: Optional[Dict[str, Any]] = None):
        self.report_id = report_id
        self.template = template
        self.parameters = parameters or {}
        self.status = ReportStatus.PENDING
        self.sections_data: Dict[str, Any] = {}
        self.metadata: Optional[ReportMetadata] = None
        self.created_at = datetime.now()
        self.completed_at: Optional[datetime] = None
        self.output_path: Optional[str] = None
        self.output_format: Optional[str] = None
    
    def add_section_data(self, section_id: str, data: Any) -> None:
        """Add data for a specific section."""
        self.sections_data[section_id] = data
    
    def get_section_data(self, section_id: str) -> Any:
        """Get data for a specific section."""
        return self.sections_data.get(section_id)
    
    def mark_completed(self, metadata: ReportMetadata, output_path: Optional[str] = None) -> None:
        """Mark report as completed."""
        self.status = ReportStatus.COMPLETED
        self.metadata = metadata
        self.completed_at = datetime.now()
        self.output_path = output_path
    
    def mark_failed(self, errors: List[str]) -> None:
        """Mark report as failed."""
        self.status = ReportStatus.FAILED
        self.completed_at = datetime.now()
        if self.metadata:
            self.metadata.errors.extend(errors)
        else:
            self.metadata = ReportMetadata(
                generated_at=datetime.now(),
                generation_time_ms=0,
                record_count=0,
                data_sources_used=[],
                errors=errors
            )
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert report to dictionary."""
        return {
            "report_id": self.report_id,
            "template_id": self.template.template_id,
            "parameters": self.parameters,
            "status": self.status.value,
            "sections_data": self.sections_data,
            "metadata": {
                "generated_at": self.metadata.generated_at.isoformat(),
                "generation_time_ms": self.metadata.generation_time_ms,
                "record_count": self.metadata.record_count,
                "data_sources_used": self.metadata.data_sources_used,
                "cache_used": self.metadata.cache_used,
                "warnings": self.metadata.warnings,
                "errors": self.metadata.errors
            } if self.metadata else None,
            "created_at": self.created_at.isoformat(),
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "output_path": self.output_path,
            "output_format": self.output_format
        }


class DataProcessor:
    """Processes data from different sources for reports."""
    
    def __init__(self, airtable_service: AirtableService, calculation_service: CalculationService,
                 formula_engine: FormulaEngine):
        self.airtable_service = airtable_service
        self.calculation_service = calculation_service
        self.formula_engine = formula_engine
    
    async def process_data_source(self, data_source: DataSource, parameters: Dict[str, Any]) -> Any:
        """Process data from a specific source."""
        if data_source.source_type == DataSourceType.AIRTABLE:
            return await self._process_airtable_source(data_source, parameters)
        elif data_source.source_type == DataSourceType.FORMULA:
            return await self._process_formula_source(data_source, parameters)
        else:
            raise BusinessLogicError(f"Unsupported data source type: {data_source.source_type}")
    
    async def _process_airtable_source(self, data_source: DataSource, parameters: Dict[str, Any]) -> Any:
        """Process Airtable data source."""
        config = data_source.configuration
        base_id = config.get("base_id") or parameters.get("base_id")
        table_id = config.get("table_id") or parameters.get("table_id")
        
        if not base_id or not table_id:
            raise BusinessLogicError("Airtable data source requires base_id and table_id")
        
        # Build query parameters
        query_params = {}
        
        # Apply filters
        filters = data_source.filters
        if filters.get("formula"):
            query_params["filter_by_formula"] = filters["formula"]
        
        if filters.get("view"):
            query_params["view"] = filters["view"]
        
        if filters.get("fields"):
            query_params["fields"] = filters["fields"]
        
        if filters.get("max_records"):
            query_params["max_records"] = filters["max_records"]
        
        if filters.get("sort"):
            query_params["sort"] = filters["sort"]
        
        # Fetch data
        result = await self.airtable_service.list_records(
            base_id=base_id,
            table_id=table_id,
            **query_params
        )
        
        records = result.get("records", [])
        
        # Apply transformations
        for transformation in data_source.transformations:
            records = await self._apply_transformation(records, transformation, parameters)
        
        return records
    
    async def _process_formula_source(self, data_source: DataSource, parameters: Dict[str, Any]) -> Any:
        """Process formula-based data source."""
        formula = data_source.configuration.get("formula")
        if not formula:
            raise BusinessLogicError("Formula data source requires formula configuration")
        
        # Prepare context with parameters
        context = {**parameters, **data_source.configuration.get("context", {})}
        
        # Execute formula
        result = self.formula_engine.execute_formula_direct(formula, context)
        
        if not result.is_valid:
            raise BusinessLogicError(f"Formula execution failed: {result.error_message}")
        
        return result.value
    
    async def _apply_transformation(self, data: List[Dict[str, Any]], transformation: str, 
                                   parameters: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Apply data transformation."""
        # Parse transformation (simplified)
        if transformation.startswith("filter:"):
            filter_expression = transformation[7:]
            filtered_data = []
            for record in data:
                try:
                    # Simple field-based filtering
                    if self._evaluate_filter(record, filter_expression):
                        filtered_data.append(record)
                except Exception as e:
                    logger.warning(f"Filter evaluation failed: {e}")
            return filtered_data
        
        elif transformation.startswith("sort:"):
            sort_field = transformation[5:]
            return sorted(data, key=lambda x: x.get("fields", {}).get(sort_field, ""))
        
        elif transformation.startswith("limit:"):
            limit = int(transformation[6:])
            return data[:limit]
        
        # If no matching transformation, return data unchanged
        return data
    
    def _evaluate_filter(self, record: Dict[str, Any], filter_expression: str) -> bool:
        """Evaluate simple filter expression."""
        # Simplified filter evaluation - in real implementation, use formula engine
        fields = record.get("fields", {})
        
        # Example: "status=Active"
        if "=" in filter_expression:
            field, value = filter_expression.split("=", 1)
            return str(fields.get(field.strip(), "")) == value.strip()
        
        return True


class ReportEngine:
    """Main report generation engine."""
    
    def __init__(self, airtable_service: AirtableService, cache: Optional[RedisCache] = None):
        self.airtable_service = airtable_service
        self.cache = cache or RedisCache()
        self.calculation_service = CalculationService(cache)
        self.formula_engine = FormulaEngine()
        self.data_processor = DataProcessor(
            airtable_service, self.calculation_service, self.formula_engine
        )
        
        self.templates: Dict[str, ReportTemplate] = {}
        self.active_reports: Dict[str, Report] = {}
        
        # Initialize default templates
        self._initialize_default_templates()
    
    def _initialize_default_templates(self) -> None:
        """Initialize default report templates."""
        # Table Summary Template
        table_summary = ReportTemplate(
            template_id="table_summary",
            name="Table Summary Report",
            report_type=ReportType.TABLE_SUMMARY
        )
        
        # Add data source
        airtable_source = DataSource(
            source_type=DataSourceType.AIRTABLE,
            name="main_table",
            configuration={},
            filters={},
            transformations=[]
        )
        table_summary.add_data_source(airtable_source)
        
        # Add sections
        summary_section = ReportSection(
            section_id="summary",
            title="Table Summary",
            section_type="summary",
            data_source=airtable_source,
            configuration={"include_count": True, "include_last_updated": True},
            order=1
        )
        
        records_section = ReportSection(
            section_id="records",
            title="Recent Records",
            section_type="table",
            data_source=airtable_source,
            configuration={"limit": 10, "sort_by": "created_time"},
            order=2
        )
        
        table_summary.add_section(summary_section)
        table_summary.add_section(records_section)
        
        self.register_template(table_summary)
    
    def register_template(self, template: ReportTemplate) -> None:
        """Register a report template."""
        self.templates[template.template_id] = template
        logger.info(f"Registered report template: {template.template_id}")
    
    def get_template(self, template_id: str) -> Optional[ReportTemplate]:
        """Get a report template."""
        return self.templates.get(template_id)
    
    def list_templates(self) -> List[ReportTemplate]:
        """List all available templates."""
        return list(self.templates.values())
    
    async def generate_report(self, template_id: str, parameters: Dict[str, Any], 
                             report_id: Optional[str] = None) -> Report:
        """Generate a report from a template."""
        template = self.get_template(template_id)
        if not template:
            raise BusinessLogicError(f"Template '{template_id}' not found")
        
        if not report_id:
            report_id = f"{template_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        report = Report(report_id, template, parameters)
        self.active_reports[report_id] = report
        
        start_time = datetime.now()
        
        try:
            report.status = ReportStatus.PROCESSING
            
            # Generate each section
            total_records = 0
            data_sources_used = set()
            warnings = []
            cache_used = False
            
            for section in template.sections:
                try:
                    # Check cache first
                    cache_key = self._generate_cache_key(section, parameters)
                    cached_data = await self.cache.get(cache_key)
                    
                    if cached_data:
                        section_data = cached_data
                        cache_used = True
                        logger.debug(f"Using cached data for section {section.section_id}")
                    else:
                        # Process section data
                        if section.data_source:
                            section_data = await self.data_processor.process_data_source(
                                section.data_source, parameters
                            )
                            data_sources_used.add(section.data_source.name)
                            
                            # Cache the result
                            await self.cache.set(cache_key, section_data, ttl=300)  # 5 minutes
                        else:
                            section_data = section.configuration.get("static_data", {})
                    
                    # Process section-specific data
                    processed_data = await self._process_section_data(section, section_data, parameters)
                    report.add_section_data(section.section_id, processed_data)
                    
                    # Count records
                    if isinstance(processed_data, list):
                        total_records += len(processed_data)
                    elif isinstance(processed_data, dict) and "count" in processed_data:
                        total_records += processed_data["count"]
                    
                except Exception as e:
                    error_msg = f"Section '{section.section_id}' failed: {str(e)}"
                    warnings.append(error_msg)
                    logger.error(error_msg)
                    report.add_section_data(section.section_id, {"error": str(e)})
            
            # Calculate generation time
            generation_time = int((datetime.now() - start_time).total_seconds() * 1000)
            
            # Create metadata
            metadata = ReportMetadata(
                generated_at=start_time,
                generation_time_ms=generation_time,
                record_count=total_records,
                data_sources_used=list(data_sources_used),
                cache_used=cache_used,
                warnings=warnings
            )
            
            report.mark_completed(metadata)
            
            logger.info(
                f"Report generated successfully",
                report_id=report_id,
                template_id=template_id,
                generation_time_ms=generation_time,
                record_count=total_records
            )
            
        except Exception as e:
            error_msg = f"Report generation failed: {str(e)}"
            logger.error(error_msg, report_id=report_id, template_id=template_id)
            report.mark_failed([error_msg])
            raise
        
        return report
    
    async def _process_section_data(self, section: ReportSection, data: Any, 
                                   parameters: Dict[str, Any]) -> Any:
        """Process data for a specific section type."""
        if section.section_type == "summary":
            return await self._process_summary_section(data, section.configuration)
        elif section.section_type == "table":
            return await self._process_table_section(data, section.configuration)
        elif section.section_type == "chart":
            return await self._process_chart_section(data, section.configuration)
        else:
            return data
    
    async def _process_summary_section(self, data: Any, config: Dict[str, Any]) -> Dict[str, Any]:
        """Process summary section data."""
        if not isinstance(data, list):
            return {"error": "Summary section requires list data"}
        
        summary = {
            "record_count": len(data)
        }
        
        if config.get("include_last_updated") and data:
            # Find most recent record
            try:
                last_updated = max(
                    record.get("createdTime", "1970-01-01T00:00:00.000Z")
                    for record in data
                )
                summary["last_updated"] = last_updated
            except Exception:
                summary["last_updated"] = "Unknown"
        
        if config.get("field_stats"):
            # Calculate field statistics
            field_stats = {}
            for field_name in config["field_stats"]:
                values = []
                for record in data:
                    value = record.get("fields", {}).get(field_name)
                    if value is not None:
                        values.append(value)
                
                if values:
                    if all(isinstance(v, (int, float)) for v in values):
                        field_stats[field_name] = {
                            "count": len(values),
                            "sum": sum(values),
                            "average": sum(values) / len(values),
                            "min": min(values),
                            "max": max(values)
                        }
                    else:
                        field_stats[field_name] = {
                            "count": len(values),
                            "unique_values": len(set(str(v) for v in values))
                        }
            
            summary["field_stats"] = field_stats
        
        return summary
    
    async def _process_table_section(self, data: Any, config: Dict[str, Any]) -> Any:
        """Process table section data."""
        if not isinstance(data, list):
            return data
        
        # Apply limit
        limit = config.get("limit")
        if limit and limit > 0:
            data = data[:limit]
        
        # Apply sorting
        sort_by = config.get("sort_by")
        if sort_by:
            try:
                reverse = config.get("sort_descending", False)
                data = sorted(data, 
                            key=lambda x: x.get("fields", {}).get(sort_by, ""),
                            reverse=reverse)
            except Exception as e:
                logger.warning(f"Sorting failed: {e}")
        
        # Filter fields
        include_fields = config.get("include_fields")
        if include_fields:
            filtered_data = []
            for record in data:
                filtered_record = {
                    "id": record.get("id"),
                    "createdTime": record.get("createdTime"),
                    "fields": {}
                }
                
                for field in include_fields:
                    if field in record.get("fields", {}):
                        filtered_record["fields"][field] = record["fields"][field]
                
                filtered_data.append(filtered_record)
            
            data = filtered_data
        
        return data
    
    async def _process_chart_section(self, data: Any, config: Dict[str, Any]) -> Dict[str, Any]:
        """Process chart section data."""
        if not isinstance(data, list):
            return {"error": "Chart section requires list data"}
        
        chart_type = config.get("chart_type", "bar")
        x_field = config.get("x_field")
        y_field = config.get("y_field")
        
        if not x_field or not y_field:
            return {"error": "Chart requires x_field and y_field configuration"}
        
        # Group data for chart
        chart_data = {}
        
        for record in data:
            fields = record.get("fields", {})
            x_value = str(fields.get(x_field, "Unknown"))
            y_value = fields.get(y_field, 0)
            
            try:
                y_value = float(y_value) if y_value is not None else 0
            except (ValueError, TypeError):
                y_value = 0
            
            if x_value not in chart_data:
                chart_data[x_value] = []
            chart_data[x_value].append(y_value)
        
        # Aggregate values
        aggregation = config.get("aggregation", "sum")
        aggregated_data = {}
        
        for x_value, y_values in chart_data.items():
            if aggregation == "sum":
                aggregated_data[x_value] = sum(y_values)
            elif aggregation == "average":
                aggregated_data[x_value] = sum(y_values) / len(y_values)
            elif aggregation == "count":
                aggregated_data[x_value] = len(y_values)
            elif aggregation == "max":
                aggregated_data[x_value] = max(y_values)
            elif aggregation == "min":
                aggregated_data[x_value] = min(y_values)
            else:
                aggregated_data[x_value] = sum(y_values)
        
        return {
            "chart_type": chart_type,
            "data": aggregated_data,
            "x_field": x_field,
            "y_field": y_field,
            "aggregation": aggregation
        }
    
    def _generate_cache_key(self, section: ReportSection, parameters: Dict[str, Any]) -> str:
        """Generate cache key for section data."""
        import hashlib
        import json
        
        key_data = {
            "section_id": section.section_id,
            "data_source": section.data_source.to_dict() if section.data_source else None,
            "configuration": section.configuration,
            "parameters": parameters
        }
        
        key_string = json.dumps(key_data, sort_keys=True)
        hash_key = hashlib.md5(key_string.encode()).hexdigest()
        
        return f"report_section:{hash_key}"
    
    def get_report(self, report_id: str) -> Optional[Report]:
        """Get a report by ID."""
        return self.active_reports.get(report_id)
    
    def list_reports(self, status: Optional[ReportStatus] = None) -> List[Report]:
        """List reports, optionally filtered by status."""
        reports = list(self.active_reports.values())
        
        if status:
            reports = [r for r in reports if r.status == status]
        
        return sorted(reports, key=lambda r: r.created_at, reverse=True)
    
    async def cancel_report(self, report_id: str) -> bool:
        """Cancel a pending or processing report."""
        report = self.get_report(report_id)
        if report and report.status in [ReportStatus.PENDING, ReportStatus.PROCESSING]:
            report.status = ReportStatus.CANCELLED
            report.completed_at = datetime.now()
            return True
        return False
    
    def cleanup_completed_reports(self, max_age_hours: int = 24) -> int:
        """Clean up completed reports older than specified age."""
        cutoff_time = datetime.now() - timedelta(hours=max_age_hours)
        removed_count = 0
        
        for report_id, report in list(self.active_reports.items()):
            if (report.status in [ReportStatus.COMPLETED, ReportStatus.FAILED, ReportStatus.CANCELLED] and
                report.completed_at and report.completed_at < cutoff_time):
                del self.active_reports[report_id]
                removed_count += 1
        
        logger.info(f"Cleaned up {removed_count} old reports")
        return removed_count