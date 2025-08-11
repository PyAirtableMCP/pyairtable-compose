# PyAirtable Automation Services Architecture

## Service Overview

The **PyAirtable Automation Services** consolidates the functionality of two separate microservices:
- **File Processor Service** (300 lines) - Document parsing and file handling
- **Workflow Engine Service** (400 lines) - Workflow automation and scheduling

**Total Service Size**: ~850 lines (within the 900-line target)
**Port**: 8006 (replaces file-processor port)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    PyAirtable Automation Services               │
│                           (Port 8006)                          │
├─────────────────────────────────────────────────────────────────┤
│  FastAPI Application Layer                                     │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐   │
│  │   Files Routes  │ │ Workflows Routes│ │  Health Routes  │   │
│  │   /files/*      │ │  /workflows/*   │ │    /health      │   │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  Business Logic Layer                                          │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐   │
│  │  FileService    │ │ WorkflowService │ │  WorkflowScheduler│  │
│  │  - File upload  │ │ - CRUD ops      │ │ - Cron scheduling│  │
│  │  - Processing   │ │ - Execution     │ │ - Background tasks│ │
│  │  - Content      │ │ - Integration   │ │ - Health checks  │  │
│  │    extraction   │ │   with files    │ │                 │  │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  Data Layer                                                     │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐   │
│  │     Files       │ │   Workflows     │ │   Executions    │   │
│  │   - File meta   │ │ - Config        │ │ - Status        │   │
│  │   - Content     │ │ - Triggers      │ │ - Results       │   │
│  │   - Status      │ │ - Schedule      │ │ - Logs          │   │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
              │                     │                     │
              ▼                     ▼                     ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PostgreSQL    │    │      Redis      │    │  File Storage   │
│   - Metadata    │    │   - Caching     │    │   - Uploads     │
│   - Workflows   │    │   - Sessions    │    │   - Temp files  │
│   - Executions  │    │   - Pub/Sub     │    │   - Processing  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Key Integration Points

### 1. File → Workflow Triggers
```
File Upload → Content Extraction → Workflow Trigger Check → Execute Matching Workflows
```

### 2. Workflow → File Processing
```
Workflow Step → File Processing Action → Update File Status → Continue Workflow
```

### 3. Shared Task Queue
```
Background Tasks (Redis) ← FileService + WorkflowService → Async Execution
```

## API Endpoints

### File Operations (Backward Compatible)
- `POST /files/upload` - Upload and process files
- `GET /files/{file_id}` - Get file information
- `POST /files/{file_id}/process` - Process uploaded file
- `GET /files/{file_id}/extract` - Extract file content
- `DELETE /files/{file_id}` - Delete file
- `GET /files` - List files

### Workflow Operations (Backward Compatible)
- `POST /workflows` - Create workflow
- `GET /workflows` - List workflows
- `GET /workflows/{id}` - Get workflow details
- `PUT /workflows/{id}` - Update workflow
- `DELETE /workflows/{id}` - Delete workflow
- `POST /workflows/{id}/trigger` - Manual trigger
- `GET /workflows/{id}/executions` - Get workflow executions
- `GET /executions` - List all executions (legacy endpoint)

### Health Check
- `GET /health` - Combined service health check
- `GET /ready` - Kubernetes readiness probe
- `GET /live` - Kubernetes liveness probe

## Database Schema

### Files Table
```sql
- id (PRIMARY KEY)
- filename, original_filename
- file_path, mime_type, file_size, file_hash
- status (uploaded, processing, processed, failed, deleted)
- extracted_content, extraction_metadata
- error_message, retry_count
- triggered_workflows (JSON array)
- timestamps (created_at, updated_at, processed_at, deleted_at)
```

### Workflows Table
```sql
- id (PRIMARY KEY)
- name, description
- workflow_config (JSON), trigger_config (JSON)
- cron_schedule, is_scheduled
- trigger_on_file_upload, trigger_file_extensions
- status (active, inactive, paused, deleted)
- is_enabled, max_retries, timeout_seconds
- execution_stats (total, successful, failed)
- timestamps (created_at, updated_at, last_execution_at, deleted_at)
```

### Workflow Executions Table
```sql
- id (PRIMARY KEY), workflow_id (FOREIGN KEY)
- trigger_type (manual, scheduled, file_upload)
- trigger_data (JSON context)
- status (pending, running, completed, failed, cancelled, timeout)
- execution_config, result_data, log_output
- error_message, retry_count
- input_file_ids, output_file_ids (JSON arrays)
- execution_time_ms
- timestamps (created_at, started_at, completed_at, updated_at)
```

## Technology Stack

### Core Framework
- **FastAPI** - High-performance async web framework
- **Uvicorn** - ASGI server with WebSocket support
- **Pydantic** - Data validation and settings

### Database & Caching
- **PostgreSQL** - Primary database with ACID compliance
- **SQLAlchemy** - ORM with async support
- **Redis** - Caching, sessions, and pub/sub

### File Processing
- **python-multipart** - File upload handling
- **PyPDF2** - PDF content extraction
- **python-docx** - Word document processing
- **pandas** - Excel/CSV data processing
- **pdfplumber** - Advanced PDF parsing

### Task Management
- **asyncio** - Async task execution
- **croniter** - Cron expression parsing
- **Background Tasks** - FastAPI background processing

### Monitoring & Security
- **structlog** - Structured logging
- **httpx** - HTTP client for service communication
- **Docker** - Containerization with health checks

## Performance Characteristics

### Scalability
- **Horizontal Scaling**: Stateless design enables multiple instances
- **Database Connection Pooling**: SQLAlchemy manages connections efficiently
- **Redis Caching**: Reduces database load for frequently accessed data
- **Background Processing**: Non-blocking async execution

### File Processing Limits
- **Max File Size**: 10MB (configurable)
- **Supported Formats**: PDF, DOC/DOCX, TXT, CSV, XLSX
- **Concurrent Uploads**: Limited by available memory and disk I/O
- **Storage**: Configurable upload directory with cleanup

### Workflow Execution
- **Concurrent Workflows**: Async execution supports multiple workflows
- **Scheduling Precision**: 30-second check interval (configurable)
- **Timeout Handling**: Per-workflow timeout configuration
- **Retry Logic**: Configurable retry attempts with exponential backoff

## Security Features

### Authentication
- **API Key Validation**: Integration with auth service
- **Service-to-Service Auth**: Consistent API key headers
- **Request Validation**: Pydantic model validation

### File Security
- **Extension Validation**: Whitelist of allowed file types
- **Size Limits**: Configurable maximum file size
- **Path Sanitization**: Secure file storage paths
- **Access Control**: Authenticated access to all endpoints

### Container Security
- **Non-root User**: Container runs as unprivileged user
- **Minimal Base Image**: Python slim image reduces attack surface
- **Volume Isolation**: Secure file storage mounting

## Deployment Configuration

### Environment Variables
```env
# Service Configuration
API_KEY=your-api-key
AUTH_SERVICE_URL=http://auth-service:8007
LOG_LEVEL=INFO

# Database
DATABASE_URL=postgresql://user:pass@postgres:5432/db
REDIS_URL=redis://redis:6379
REDIS_PASSWORD=your-redis-password

# File Processing
MAX_FILE_SIZE=10MB
ALLOWED_EXTENSIONS=pdf,doc,docx,txt,csv,xlsx
UPLOAD_DIR=/tmp/uploads

# Workflow Settings
DEFAULT_WORKFLOW_TIMEOUT=300
MAX_WORKFLOW_RETRIES=3
SCHEDULER_CHECK_INTERVAL=30
```

### Docker Compose Integration
```yaml
automation-services:
  image: ghcr.io/reg-kris/pyairtable-automation-services:latest
  ports: ["8006:8006"]
  depends_on: [auth-service, redis, postgres]
  volumes: [file-uploads:/tmp/uploads]
  healthcheck: # Kubernetes-ready health checks
```

## Migration Strategy

### From Separate Services
1. **Database Migration**: Run migration scripts to create unified schema
2. **Container Replacement**: Replace both services with automation-services
3. **Environment Update**: Update API gateway and frontend URLs
4. **Data Migration**: Migrate existing file and workflow data
5. **Validation**: Test all endpoints for backward compatibility

### Rollback Plan
- Keep original service images available
- Database schema supports both old and new structures
- Environment variables remain backward compatible
- Health check endpoints validate service functionality

## Monitoring & Observability

### Health Checks
- **Service Health**: Database, Redis, file storage, scheduler status
- **Kubernetes Probes**: Readiness and liveness endpoints
- **Dependency Validation**: External service connectivity

### Logging
- **Structured Logging**: JSON format with correlation IDs
- **Request Tracing**: Track file uploads and workflow executions
- **Error Tracking**: Comprehensive error logging with stack traces
- **Performance Metrics**: Execution times and resource usage

### Metrics
- **File Processing**: Upload rates, processing times, success rates
- **Workflow Execution**: Execution counts, durations, failure rates
- **System Health**: Memory usage, database connections, Redis status