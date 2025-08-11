# PyAirtable Automation Domain Service

A consolidated automation domain service that combines workflow-engine, notification-service, and webhook-service into a single, production-ready Python service using FastAPI and Celery.

## Features

### Workflow Management
- ✅ Workflow definition and execution
- ✅ Step-based workflow engine with conditions
- ✅ Multi-step workflows with parallel execution support
- ✅ Workflow state management and persistence
- ✅ Execution history and monitoring

### Notification Service
- ✅ Email notifications with SMTP support
- ✅ SMS notifications (extensible provider support)
- ✅ Template system with Jinja2 templating
- ✅ Delivery tracking and retry logic
- ✅ Rate limiting and queue management

### Webhook Management
- ✅ Webhook endpoint registration and management
- ✅ Event-driven webhook delivery
- ✅ Signature verification with HMAC
- ✅ Retry policies with exponential backoff
- ✅ Delivery tracking and monitoring

### Automation Orchestration
- ✅ Rule-based automation engine
- ✅ Event-driven triggers
- ✅ Conditional logic evaluation
- ✅ Action execution (workflows, notifications, webhooks)
- ✅ Priority-based execution

### Infrastructure
- ✅ FastAPI with async/await support
- ✅ Celery for background task processing
- ✅ Redis for caching and task queuing
- ✅ PostgreSQL with optimized schema
- ✅ Comprehensive observability (metrics, logging, tracing)
- ✅ Production-ready Docker setup

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   FastAPI App   │    │  Celery Worker  │    │ Celery Beat     │
│                 │    │                 │    │ (Scheduler)     │
│ - REST API      │    │ - Workflow Tasks│    │                 │
│ - Health Checks │◄──►│ - Notification  │    │ - Cron Jobs     │
│ - Authentication│    │ - Webhook Tasks │    │ - Periodic Tasks│
│ - Rate Limiting │    │ - Automation    │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
              ┌─────────────────────────────────────┐
              │              Redis                  │
              │                                     │
              │ - Task Queue (Priority Queues)     │
              │ - Result Backend                    │
              │ - Caching Layer                     │
              │ - Session Storage                   │
              └─────────────────────────────────────┘
                                 │
              ┌─────────────────────────────────────┐
              │            PostgreSQL               │
              │                                     │
              │ - Workflows & Executions           │
              │ - Notifications & Templates        │
              │ - Webhooks & Deliveries           │
              │ - Automation Rules & Executions    │
              └─────────────────────────────────────┘
```

## Quick Start

### Prerequisites
- Docker and Docker Compose
- Python 3.11+ (for local development)
- Poetry (for dependency management)

### Development Setup

1. **Clone and navigate to the service directory:**
   ```bash
   cd pyairtable-automation-domain
   ```

2. **Start the development environment:**
   ```bash
   make dev
   ```

This will start:
- **API Server**: http://localhost:8090
- **Flower (Celery Monitoring)**: http://localhost:5555
- **MailHog (Email Testing)**: http://localhost:8025
- **PostgreSQL**: localhost:5432
- **Redis**: localhost:6379

3. **Check service health:**
   ```bash
   curl http://localhost:8090/health
   ```

### Production Deployment

1. **Build production image:**
   ```bash
   make prod-build
   ```

2. **Run with production configuration:**
   ```bash
   docker run -d \
     --name automation-domain \
     -p 8090:8090 \
     -e ENV=production \
     -e DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/db \
     -e REDIS_URL=redis://host:6379/0 \
     -e CELERY_BROKER_URL=redis://host:6379/1 \
     -e INTERNAL_API_KEY=your-secure-key \
     -e JWT_SECRET_KEY=your-jwt-secret \
     pyairtable-automation-domain:latest
   ```

## API Documentation

### Core Endpoints

- **Health Check**: `GET /health`
- **Service Info**: `GET /info`
- **API Documentation**: `GET /docs` (development only)

### Workflow Management

```bash
# List workflows
GET /api/v1/workflows

# Create workflow
POST /api/v1/workflows
{
  "name": "Data Processing Workflow",
  "description": "Process uploaded data files",
  "trigger_type": "manual",
  "steps": [
    {
      "id": "validate",
      "type": "data_transform",
      "config": {...}
    },
    {
      "id": "notify",
      "type": "notification",
      "config": {...}
    }
  ]
}

# Execute workflow
POST /api/v1/workflows/{id}/execute
{
  "input_data": {...},
  "priority": "high"
}
```

### Notification Service

```bash
# Send email notification
POST /api/v1/notifications/email
{
  "to": ["user@example.com"],
  "subject": "Welcome!",
  "body": "Welcome to our platform!",
  "template_id": "welcome_email",
  "template_data": {
    "user_name": "John Doe",
    "app_name": "PyAirtable"
  }
}

# Send SMS notification
POST /api/v1/notifications/sms
{
  "to": ["+1234567890"],
  "message": "Your verification code is 123456",
  "template_id": "verification_sms"
}
```

### Webhook Management

```bash
# Register webhook endpoint
POST /api/v1/webhooks/endpoints
{
  "name": "External System Webhook",
  "url": "https://api.external.com/webhook",
  "events": ["workflow.completed", "notification.sent"],
  "secret": "webhook_secret_key"
}

# Deliver webhook
POST /api/v1/webhooks/deliver
{
  "event_type": "workflow.completed",
  "payload": {
    "workflow_id": "123",
    "status": "completed"
  }
}
```

### Automation Rules

```bash
# Create automation rule
POST /api/v1/automation/rules
{
  "name": "Welcome Email Automation",
  "trigger": {
    "type": "event",
    "event_type": "user.created"
  },
  "conditions": [
    {
      "type": "field_check",
      "field": "user.email_verified",
      "operator": "equals",
      "value": true
    }
  ],
  "actions": [
    {
      "type": "notification",
      "notification_type": "email",
      "template": "welcome_email",
      "to": "{{user.email}}"
    }
  ]
}
```

## Configuration

### Environment Variables

#### Core Configuration
- `ENV`: Environment (development/production)
- `HOST`: Server host (default: 0.0.0.0)
- `PORT`: Server port (default: 8090)
- `WORKERS`: Number of workers (default: 1)
- `RELOAD`: Enable auto-reload (default: false)

#### Database
- `DATABASE_URL`: PostgreSQL connection string
- `DATABASE_POOL_SIZE`: Connection pool size (default: 10)
- `DATABASE_MAX_OVERFLOW`: Max overflow connections (default: 20)

#### Redis
- `REDIS_URL`: Redis connection string
- `REDIS_PASSWORD`: Redis password (optional)
- `REDIS_MAX_CONNECTIONS`: Max connections (default: 20)

#### Celery
- `CELERY_BROKER_URL`: Celery broker URL
- `CELERY_RESULT_BACKEND`: Celery result backend URL
- `CELERY_TASK_TIME_LIMIT`: Task time limit in seconds (default: 1800)

#### Security
- `INTERNAL_API_KEY`: Internal service API key (required)
- `JWT_SECRET_KEY`: JWT signing secret (required)
- `WEBHOOK_SECRET_KEY`: Webhook signing secret (required)

#### Notifications
- `SMTP_HOST`: SMTP server host
- `SMTP_PORT`: SMTP server port (default: 587)
- `SMTP_USERNAME`: SMTP username (optional)
- `SMTP_PASSWORD`: SMTP password (optional)
- `SMTP_USE_TLS`: Use TLS (default: true)

## Development

### Available Commands

```bash
# Development
make dev                 # Start development environment
make dev-detached       # Start in background
make stop               # Stop all services
make logs               # Show logs
make shell              # Get shell in container

# Code Quality
make lint               # Run linting
make format             # Format code
make test               # Run tests
make test-cov           # Run tests with coverage

# Database
make db-upgrade         # Run migrations
make db-revision        # Create new migration
make db-reset           # Reset database

# Workers
make worker             # Start Celery worker
make beat               # Start Celery beat
make flower             # Start Flower monitoring

# Monitoring
make monitor            # Show system status
```

### Project Structure

```
pyairtable-automation-domain/
├── src/
│   ├── core/              # Core application components
│   │   ├── app.py         # FastAPI application factory
│   │   ├── config.py      # Configuration management
│   │   └── logging.py     # Logging configuration
│   ├── database/          # Database management
│   │   └── connection.py  # Connection pooling
│   ├── middleware/        # FastAPI middleware
│   │   ├── auth.py        # Authentication
│   │   ├── logging.py     # Request logging
│   │   └── metrics.py     # Prometheus metrics
│   ├── models/            # Database models (SQLAlchemy)
│   ├── routers/           # API route handlers
│   │   ├── workflows.py   # Workflow endpoints
│   │   ├── notifications.py # Notification endpoints
│   │   ├── webhooks.py    # Webhook endpoints
│   │   └── automation.py  # Automation endpoints
│   ├── services/          # Business logic services
│   ├── utils/             # Utility modules
│   │   └── redis_client.py # Redis utilities
│   ├── workers/           # Celery tasks
│   │   ├── celery_app.py  # Celery configuration
│   │   ├── workflow_tasks.py # Workflow tasks
│   │   ├── notification_tasks.py # Notification tasks
│   │   ├── webhook_tasks.py # Webhook tasks
│   │   └── automation_tasks.py # Automation tasks
│   └── main.py            # Application entry point
├── tests/                 # Test suite
├── migrations/            # Database migrations
├── configs/               # Configuration files
├── docker-compose.yml     # Development environment
├── Dockerfile            # Container definition
├── Makefile              # Development commands
└── pyproject.toml        # Python dependencies
```

## Monitoring and Observability

### Health Checks
- `/health` - Basic health check
- `/health/detailed` - Detailed health with dependencies
- `/ready` - Kubernetes readiness probe
- `/live` - Kubernetes liveness probe

### Metrics
- Prometheus metrics at `/metrics`
- HTTP request metrics
- Celery task metrics
- Custom business metrics

### Logging
- Structured JSON logging in production
- Rich console logging in development
- Request/response logging
- Error tracking and alerting

### Monitoring Tools
- **Flower**: Celery task monitoring at http://localhost:5555
- **MailHog**: Email testing at http://localhost:8025
- **Prometheus**: Metrics collection
- **Grafana**: Dashboards and alerting

## Security

### Authentication
- JWT token validation
- Internal API key for service-to-service communication
- Request ID tracking

### Webhook Security
- HMAC signature verification
- Configurable secret keys
- Request timestamp validation

### Rate Limiting
- Per-endpoint rate limiting
- Queue-based request throttling
- Configurable limits per user/service

## Performance

### Optimizations
- Async/await throughout the codebase
- Connection pooling for database and Redis
- Priority-based task queues
- Efficient database indexes

### Scalability
- Horizontal scaling with multiple workers
- Load balancing support
- Redis clustering support
- Database read replicas support

## Migration from Existing Services

This service consolidates functionality from:

1. **workflow-engine** (Python) → Workflow management module
2. **notification-service** (Go) → Notification module
3. **webhook-service** (Go) → Webhook module

### Migration Benefits
- **Reduced Infrastructure**: Single service instead of three
- **Shared Resources**: Common database and Redis instances
- **Unified Logging**: Centralized observability
- **Cost Savings**: Reduced operational overhead
- **gRPC Ready**: Prepared for gRPC migration

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run the test suite: `make ci-test`
6. Submit a pull request

## License

Copyright (c) 2024 PyAirtable Team. All rights reserved.