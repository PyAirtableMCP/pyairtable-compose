# PyAirtable Automation Services

A unified microservice that consolidates file processing and workflow engine capabilities into a single, efficient service.

## Service Overview

This service combines:
- **File Processing**: Document parsing, file handling (CSV/PDF/DOCX)
- **Workflow Engine**: Workflow automation, cron scheduling, triggers

**Port**: 8006 (replaces file-processor)
**Dependencies**: Auth Service, Redis, PostgreSQL

## Features

### File Processing
- File upload and storage management
- Document parsing (CSV, PDF, DOCX, TXT)
- File content extraction
- File metadata management

### Workflow Engine
- Workflow creation and management
- Cron-based scheduling
- Manual and automatic triggers
- Workflow execution tracking

### Integration Points
- Workflows can trigger file processing
- File uploads can trigger workflows
- Shared task queue for processing
- Combined monitoring and logging

## API Endpoints

### File Operations
- `POST /files/upload` - Upload files
- `GET /files/{file_id}` - Get file information
- `POST /files/{file_id}/process` - Process uploaded file
- `GET /files/{file_id}/extract` - Extract file content
- `DELETE /files/{file_id}` - Delete file

### Workflow Operations
- `POST /workflows` - Create workflow
- `GET /workflows` - List workflows
- `GET /workflows/{id}` - Get workflow details
- `PUT /workflows/{id}` - Update workflow
- `DELETE /workflows/{id}` - Delete workflow
- `POST /workflows/{id}/trigger` - Manual trigger
- `GET /executions` - List workflow executions

### Health Check
- `GET /health` - Combined health check

## Architecture

```
automation-services/
├── src/
│   ├── main.py              # FastAPI application
│   ├── config.py            # Configuration management
│   ├── database.py          # Database connection
│   ├── models/              # Database models
│   │   ├── __init__.py
│   │   ├── files.py         # File models
│   │   ├── workflows.py     # Workflow models
│   │   └── executions.py    # Execution models
│   ├── routes/              # API routes
│   │   ├── __init__.py
│   │   ├── files.py         # File endpoints
│   │   ├── workflows.py     # Workflow endpoints
│   │   └── health.py        # Health check
│   ├── services/            # Business logic
│   │   ├── __init__.py
│   │   ├── file_service.py  # File processing
│   │   ├── workflow_service.py # Workflow management
│   │   └── scheduler.py     # Task scheduling
│   └── utils/               # Utilities
│       ├── __init__.py
│       ├── auth.py          # Authentication
│       ├── redis_client.py  # Redis connection
│       └── file_utils.py    # File utilities
├── Dockerfile
├── requirements.txt
└── docker-compose.test.yml
```

## Environment Variables

- `AUTH_SERVICE_URL` - Authentication service URL
- `API_KEY` - Service API key
- `LOG_LEVEL` - Logging level
- `REDIS_URL` - Redis connection URL
- `REDIS_PASSWORD` - Redis password
- `DATABASE_URL` - PostgreSQL connection URL
- `MAX_FILE_SIZE` - Maximum file upload size
- `ALLOWED_EXTENSIONS` - Allowed file extensions
- `UPLOAD_DIR` - File upload directory

## Development

1. Install dependencies: `pip install -r requirements.txt`
2. Set environment variables
3. Run: `uvicorn src.main:app --host 0.0.0.0 --port 8006`

## Docker

```bash
docker build -t pyairtable-automation-services .
docker run -p 8006:8006 pyairtable-automation-services
```