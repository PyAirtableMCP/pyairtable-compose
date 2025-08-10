# PyAirtable Workflow Management API Documentation

## Overview

The PyAirtable Workflow Management system provides comprehensive workflow automation capabilities including template management, workflow execution with step-by-step tracking, and SAGA orchestration for distributed transactions.

### Base URLs
- **Automation Services**: `http://localhost:8006` (Port 8006)
- **SAGA Orchestrator**: `http://localhost:8008` (Port 8008)

### Authentication
All API endpoints require authentication via API key in the Authorization header:
```
Authorization: Bearer your-api-key-here
```

## API Endpoints Overview

### 🏗️ Workflow Templates (`/api/v1/templates`)

Template management for reusable workflow definitions.

#### List Templates
```http
GET /api/v1/templates
```

**Query Parameters:**
- `category` (optional): Filter by category (integration, file-processing, sync, etc.)
- `public_only` (optional): Show only public templates (default: true)
- `search` (optional): Search in name and description
- `tags` (optional): Filter by comma-separated tags
- `page` (optional): Page number (default: 1)
- `page_size` (optional): Page size (default: 20, max: 100)

**Response:**
```json
{
  "templates": [
    {
      "id": 1,
      "name": "Simple HTTP Request",
      "description": "Execute a simple HTTP request with optional data processing",
      "category": "integration",
      "template_config": {
        "steps": [
          {
            "name": "http_request",
            "type": "http_request",
            "config": {
              "url": "",
              "method": "GET",
              "headers": {}
            }
          }
        ]
      },
      "default_trigger_config": {
        "type": "manual",
        "enabled": true
      },
      "is_public": true,
      "version": "1.0.0",
      "usage_count": 5,
      "created_at": "2025-01-08T10:00:00Z",
      "updated_at": "2025-01-08T10:00:00Z"
    }
  ],
  "total": 10,
  "page": 1,
  "page_size": 20
}
```

#### Get Template Categories
```http
GET /api/v1/templates/categories
```

**Response:**
```json
{
  "categories": [
    {
      "name": "integration",
      "count": 5,
      "display_name": "Integration"
    },
    {
      "name": "file-processing",
      "count": 3,
      "display_name": "File Processing"
    }
  ],
  "total": 2
}
```

#### Create Template
```http
POST /api/v1/templates
```

**Request Body:**
```json
{
  "name": "Custom Integration Template",
  "description": "Custom template for API integrations",
  "category": "integration",
  "template_config": {
    "steps": [
      {
        "name": "fetch_data",
        "type": "http_request",
        "config": {
          "url": "{{api_endpoint}}",
          "method": "GET",
          "headers": {
            "Authorization": "Bearer {{api_token}}"
          }
        }
      },
      {
        "name": "process_data",
        "type": "data_transform",
        "config": {
          "transformations": [
            {
              "type": "extract",
              "path": "data.items",
              "key": "extracted_items"
            }
          ]
        }
      }
    ]
  },
  "default_trigger_config": {
    "type": "schedule",
    "enabled": false
  },
  "default_cron_schedule": "0 9 * * 1",
  "is_public": true,
  "tags": "api,integration,custom"
}
```

#### Get Template Details
```http
GET /api/v1/templates/{template_id}
```

#### Update Template
```http
PUT /api/v1/templates/{template_id}
```

#### Delete Template
```http
DELETE /api/v1/templates/{template_id}
```

#### Create Workflow from Template
```http
POST /api/v1/templates/create-workflow
```

**Request Body:**
```json
{
  "template_id": 1,
  "workflow_name": "Daily Data Sync",
  "workflow_description": "Daily synchronization workflow created from template",
  "custom_config": {
    "steps": [
      {
        "name": "fetch_data",
        "config": {
          "url": "https://api.example.com/data"
        }
      }
    ]
  },
  "cron_schedule": "0 9 * * *",
  "is_scheduled": true,
  "trigger_on_file_upload": false
}
```

#### Get Template Usage Statistics
```http
GET /api/v1/templates/{template_id}/usage-stats
```

### 🔄 Workflow Management (`/api/v1/workflows`)

Core workflow management operations.

#### Create Workflow
```http
POST /api/v1/workflows
```

**Request Body:**
```json
{
  "name": "Data Processing Workflow",
  "description": "Process uploaded files and sync with external API",
  "workflow_config": {
    "steps": [
      {
        "name": "validate_file",
        "type": "file_process",
        "config": {
          "action": "validate",
          "file_id": "{{trigger.file_id}}"
        }
      },
      {
        "name": "extract_content",
        "type": "file_process",
        "config": {
          "action": "extract",
          "file_id": "{{trigger.file_id}}"
        }
      },
      {
        "name": "sync_data",
        "type": "http_request",
        "config": {
          "url": "https://api.example.com/sync",
          "method": "POST",
          "data": {
            "content": "{{steps.extract_content.content}}"
          }
        }
      },
      {
        "name": "notify_completion",
        "type": "notification",
        "config": {
          "type": "webhook",
          "webhook_url": "https://hooks.slack.com/...",
          "message": "File processing completed successfully"
        }
      }
    ]
  },
  "trigger_config": {
    "type": "file_upload",
    "enabled": true
  },
  "trigger_on_file_upload": true,
  "trigger_file_extensions": "pdf,docx,csv",
  "timeout_seconds": 600,
  "is_enabled": true
}
```

**Step Types Available:**
- `http_request`: HTTP requests with authentication and error handling
- `file_process`: File processing operations (validate, extract, convert)
- `delay`: Wait/delay steps
- `log`: Logging steps
- `conditional`: Conditional branching
- `data_transform`: Data transformation and extraction
- `notification`: Send notifications (webhook, log)

#### List Workflows
```http
GET /api/v1/workflows
```

**Query Parameters:**
- `status` (optional): Filter by status (active, inactive, paused, deleted)
- `limit` (optional): Maximum number of results (default: 100)
- `offset` (optional): Offset for pagination (default: 0)

#### Get Workflow Details
```http
GET /api/v1/workflows/{workflow_id}
```

#### Update Workflow
```http
PUT /api/v1/workflows/{workflow_id}
```

#### Delete Workflow
```http
DELETE /api/v1/workflows/{workflow_id}
```

#### Execute Workflow
```http
POST /api/v1/workflows/{workflow_id}/execute
```

**Request Body:**
```json
{
  "trigger_data": {
    "file_id": "123",
    "user_id": "user_456",
    "custom_params": {
      "priority": "high"
    }
  }
}
```

**Response:**
```json
{
  "message": "Workflow execution started",
  "execution_id": 789,
  "workflow_id": 123
}
```

#### Get Workflow Executions
```http
GET /api/v1/workflows/{workflow_id}/executions
```

**Query Parameters:**
- `status` (optional): Filter by execution status
- `limit` (optional): Maximum number of results (default: 50)
- `offset` (optional): Offset for pagination (default: 0)

**Response:**
```json
[
  {
    "id": 789,
    "workflow_id": 123,
    "trigger_type": "manual",
    "status": "completed",
    "execution_time_ms": 1500,
    "retry_count": 0,
    "created_at": "2025-01-08T10:00:00Z",
    "started_at": "2025-01-08T10:00:01Z",
    "completed_at": "2025-01-08T10:00:02Z",
    "result_data": {
      "validate_file": {"valid": true, "size": 1024},
      "extract_content": {"content": "extracted text"},
      "sync_data": {"status_code": 200, "response_id": "abc123"},
      "notify_completion": {"sent": true}
    }
  }
]
```

### 📊 Workflow Monitoring

#### Get Execution Steps (Enhanced tracking)
```http
GET /api/v1/workflows/executions/{execution_id}/steps
```

**Response:**
```json
[
  {
    "id": 1,
    "step_order": 1,
    "step_name": "validate_file",
    "step_type": "file_process",
    "status": "completed",
    "execution_time_ms": 250,
    "started_at": "2025-01-08T10:00:01Z",
    "completed_at": "2025-01-08T10:00:01.250Z",
    "input_data": {"file_id": "123"},
    "output_data": {"valid": true, "size": 1024},
    "retry_count": 0
  },
  {
    "id": 2,
    "step_order": 2,
    "step_name": "extract_content",
    "step_type": "file_process",
    "status": "completed",
    "execution_time_ms": 800,
    "started_at": "2025-01-08T10:00:01.250Z",
    "completed_at": "2025-01-08T10:00:02.050Z",
    "input_data": {"file_id": "123", "action": "extract"},
    "output_data": {"content": "extracted text", "word_count": 150},
    "retry_count": 0
  }
]
```

#### Retry Failed Step
```http
POST /api/v1/workflows/steps/{step_id}/retry
```

### 🔧 Health and Monitoring

#### Health Check
```http
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-01-08T10:00:00Z",
  "service": "automation-services",
  "version": "1.0.0",
  "components": {
    "database": "healthy",
    "redis": "healthy",
    "scheduler": "healthy",
    "saga_orchestrator": "healthy"
  },
  "metrics": {
    "total_workflows": 25,
    "active_executions": 3,
    "completed_executions_24h": 150,
    "failed_executions_24h": 2,
    "success_rate_24h": 98.7
  }
}
```

## SAGA Orchestrator Integration (`http://localhost:8008`)

### Start SAGA
```http
POST /api/v1/sagas/start
```

**Request Body:**
```json
{
  "saga_type": "workflow_execution",
  "input_data": {
    "workflow_id": 123,
    "execution_id": 789,
    "workflow_config": {...},
    "timeout_seconds": 600
  },
  "correlation_id": "workflow-123-execution-789",
  "tenant_id": "automation-services"
}
```

### List SAGAs
```http
GET /api/v1/sagas/
```

### Get SAGA Details
```http
GET /api/v1/sagas/{saga_id}
```

### Cancel SAGA
```http
POST /api/v1/sagas/{saga_id}/cancel
```

### Publish Event
```http
POST /api/v1/events/publish
```

## Context Variables and Templating

Workflow configurations support context variable injection:

### Available Variables
- `{{execution_id}}` - Current execution ID
- `{{workflow_id}}` - Current workflow ID
- `{{trigger.field_name}}` - Trigger data fields
- `{{steps.step_name.field_name}}` - Previous step results

### Example Usage
```json
{
  "steps": [
    {
      "name": "api_call",
      "type": "http_request",
      "config": {
        "url": "https://api.example.com/data/{{trigger.user_id}}",
        "headers": {
          "X-Execution-ID": "{{execution_id}}"
        }
      }
    },
    {
      "name": "process_response",
      "type": "data_transform",
      "config": {
        "source_data": "{{steps.api_call.json}}",
        "transformations": [
          {
            "type": "extract",
            "path": "data.items",
            "key": "processed_items"
          }
        ]
      }
    }
  ]
}
```

## Error Handling

### HTTP Status Codes
- `200` - Success
- `400` - Bad Request (validation errors)
- `401` - Unauthorized (missing/invalid API key)
- `404` - Resource Not Found
- `409` - Conflict (duplicate names, etc.)
- `429` - Rate Limited
- `500` - Internal Server Error

### Error Response Format
```json
{
  "detail": "Workflow not found",
  "timestamp": "2025-01-08T10:00:00Z",
  "path": "/api/v1/workflows/999",
  "error_code": "WORKFLOW_NOT_FOUND"
}
```

### Retry Logic
- Failed steps are automatically retried up to 3 times
- Exponential backoff between retries
- SAGA compensation is triggered for failed workflows with completed steps

## Rate Limiting

- **Templates**: 100 requests per minute
- **Workflow Creation**: 50 requests per minute  
- **Workflow Execution**: 200 requests per minute
- **Monitoring Endpoints**: 500 requests per minute

## Webhooks and Notifications

### Webhook Events
Workflows can send webhooks on:
- Workflow completion
- Workflow failure
- Step completion
- Step failure

### Webhook Payload Format
```json
{
  "event_type": "workflow_completed",
  "workflow_id": 123,
  "execution_id": 789,
  "status": "completed",
  "timestamp": "2025-01-08T10:00:00Z",
  "execution_time_ms": 1500,
  "result_data": {...}
}
```

## Security Considerations

1. **API Key Management**: Rotate API keys regularly
2. **HTTPS Only**: Use HTTPS in production
3. **Input Validation**: All inputs are validated and sanitized
4. **Rate Limiting**: Prevents abuse and resource exhaustion
5. **Audit Logging**: All operations are logged with correlation IDs
6. **Secret Management**: Use environment variables for sensitive data

## Performance Optimization

1. **Redis Caching**: Workflow and execution states are cached
2. **Database Indexing**: Optimized indexes for common queries
3. **Connection Pooling**: Efficient database connection management
4. **Async Processing**: Non-blocking execution with proper queuing
5. **Resource Limits**: Configurable timeouts and retry limits

## Example Complete Workflow

Here's a complete example of a file processing workflow with error handling and notifications:

```json
{
  "name": "Document Processing Pipeline",
  "description": "Complete document processing with OCR, validation, and notification",
  "workflow_config": {
    "steps": [
      {
        "name": "validate_upload",
        "type": "file_process",
        "config": {
          "action": "validate",
          "file_id": "{{trigger.file_id}}",
          "allowed_types": ["pdf", "jpg", "png"],
          "max_size_mb": 10
        }
      },
      {
        "name": "extract_text",
        "type": "file_process", 
        "config": {
          "action": "ocr_extract",
          "file_id": "{{trigger.file_id}}",
          "language": "en"
        }
      },
      {
        "name": "validate_content",
        "type": "conditional",
        "config": {
          "condition": "{{steps.extract_text.word_count}} > 10",
          "true_action": {
            "type": "log",
            "config": {"message": "Content validation passed"}
          },
          "false_action": {
            "type": "log",
            "config": {"message": "Content validation failed", "level": "warning"}
          }
        }
      },
      {
        "name": "save_to_database",
        "type": "http_request",
        "config": {
          "url": "https://api.internal.com/documents",
          "method": "POST",
          "headers": {
            "Authorization": "Bearer {{env.DATABASE_API_TOKEN}}"
          },
          "data": {
            "file_id": "{{trigger.file_id}}",
            "extracted_text": "{{steps.extract_text.content}}",
            "word_count": "{{steps.extract_text.word_count}}",
            "processed_at": "{{execution_id}}"
          },
          "expected_status": [200, 201]
        }
      },
      {
        "name": "send_notification",
        "type": "notification",
        "config": {
          "type": "webhook",
          "webhook_url": "{{env.NOTIFICATION_WEBHOOK_URL}}",
          "message": "Document {{trigger.file_id}} processed successfully. Database ID: {{steps.save_to_database.json.id}}"
        }
      }
    ]
  },
  "trigger_on_file_upload": true,
  "trigger_file_extensions": "pdf,jpg,jpeg,png",
  "timeout_seconds": 300,
  "max_retries": 2
}
```

This workflow demonstrates:
- File validation and processing
- Conditional logic
- External API integration
- Error handling with expected status codes
- Environment variable usage
- Context variable chaining between steps
- Final notification with results

For additional examples and advanced use cases, see the template library at `/api/v1/templates`.