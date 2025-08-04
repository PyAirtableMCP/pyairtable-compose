# PyAirtable Airtable Domain Service

A consolidated, high-performance service that combines Airtable Gateway functionality, Business Logic Engine, and Automation capabilities into a unified platform built with FastAPI.

## Features

- **Airtable API Gateway**: Complete Airtable API integration with caching, rate limiting, and monitoring
- **Workflow Management**: Create and execute complex workflows with various triggers and actions
- **Business Logic Engine**: Apply data transformations, validations, and business rules
- **Automation & Scheduling**: Schedule workflows, handle webhooks, and manage background tasks
- **Comprehensive Monitoring**: Prometheus metrics, structured logging, and health checks
- **Production Ready**: Docker containerization, database migrations, and scalable architecture

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    FastAPI Application                     │
├─────────────────────────────────────────────────────────────┤
│  Routers: Airtable │ Workflows │ Automation │ Business Logic │
├─────────────────────────────────────────────────────────────┤
│     Middleware: Auth │ Logging │ Metrics │ CORS │ Error      │
├─────────────────────────────────────────────────────────────┤
│   Services: Airtable │ Workflow │ Scheduler │ Validation     │
├─────────────────────────────────────────────────────────────┤
│      Database: PostgreSQL │ Redis Cache │ Celery Queue      │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Python 3.11+
- Poetry
- Docker & Docker Compose
- PostgreSQL (for production)
- Redis (for caching and queues)

### Development Setup

1. **Clone and setup the project:**
   ```bash
   cd pyairtable-airtable-domain
   cp .env.example .env
   # Edit .env with your configuration
   ```

2. **Install dependencies:**
   ```bash
   make install-dev
   ```

3. **Start development environment:**
   ```bash
   # Start dependencies
   docker-compose up -d postgres redis
   
   # Run migrations
   make migrate
   
   # Start the application
   make dev
   ```

4. **Access the application:**
   - API: http://localhost:8000
   - Documentation: http://localhost:8000/docs
   - Health Check: http://localhost:8000/health

### Docker Development

```bash
# Start all services
make run

# Start with monitoring
make run-monitoring

# Start with background workers
make run-workers

# View logs
make logs
```

## Configuration

The service uses environment-based configuration. Key settings:

### Airtable Configuration
```env
AIRTABLE_TOKEN=your_personal_access_token
AIRTABLE_RATE_LIMIT=5
AIRTABLE_TIMEOUT=30
AIRTABLE_CACHE_TTL=3600
```

### Database Configuration
```env
DATABASE_URL=postgresql+asyncpg://user:pass@host:port/db
DATABASE_POOL_SIZE=20
DATABASE_MAX_OVERFLOW=30
```

### Security Configuration
```env
SECURITY_INTERNAL_API_KEY=your_internal_key
SECURITY_JWT_SECRET_KEY=your_jwt_secret
```

See `.env.example` for complete configuration options.

## API Endpoints

### Airtable Operations
- `GET /api/v1/airtable/bases` - List accessible bases
- `GET /api/v1/airtable/bases/{base_id}/schema` - Get base schema
- `GET /api/v1/airtable/bases/{base_id}/tables/{table_id}/records` - List records
- `POST /api/v1/airtable/bases/{base_id}/tables/{table_id}/records` - Create records
- `PATCH /api/v1/airtable/bases/{base_id}/tables/{table_id}/records` - Update records
- `DELETE /api/v1/airtable/bases/{base_id}/tables/{table_id}/records` - Delete records

### Workflow Management
- `GET /api/v1/workflows` - List workflows
- `POST /api/v1/workflows` - Create workflow
- `PUT /api/v1/workflows/{id}` - Update workflow
- `POST /api/v1/workflows/{id}/execute` - Execute workflow

### Automation
- `GET /api/v1/automation/scheduled-tasks` - List scheduled tasks
- `POST /api/v1/automation/scheduled-tasks` - Create scheduled task
- `POST /api/v1/automation/triggers/webhook/{id}` - Webhook triggers

### Business Logic
- `POST /api/v1/business-logic/transform` - Transform data
- `POST /api/v1/business-logic/validate` - Validate data
- `POST /api/v1/business-logic/rules/execute` - Execute business rules

## Development

### Testing

```bash
# Run all tests
make test

# Run with coverage
make test-cov

# Run specific test types
make test-unit
make test-integration
```

### Code Quality

```bash
# Format code
make format

# Run linting
make lint

# Check formatting
make format-check
```

### Database Operations

```bash
# Create migration
make migrate-create name="description"

# Run migrations
make migrate

# Reset database
make db-reset
```

## Data Models

### Airtable Models
- `AirtableBase` - Base information and schema
- `AirtableTable` - Table schema and metadata
- `AirtableOperation` - API operation logging

### Workflow Models
- `Workflow` - Workflow definitions
- `WorkflowExecution` - Execution instances
- `WorkflowStep` - Individual step executions
- `ScheduledTask` - Scheduled workflow tasks

## Services

### AirtableService
Handles all Airtable API interactions with:
- Rate limiting (configurable requests/second)
- Response caching with Redis
- Automatic retries with exponential backoff
- Operation logging and metrics
- Batch operations support

### Workflow Engine
Manages workflow execution with:
- Multiple trigger types (manual, scheduled, webhook, API)
- Various action types (Airtable operations, HTTP requests, transformations)
- Error handling and retry logic
- Execution tracking and logging

### Background Tasks
Celery-based task processing for:
- Scheduled workflow execution
- Long-running operations
- Email notifications
- Data processing jobs

## Monitoring & Observability

### Metrics
Prometheus metrics available at `/metrics`:
- HTTP request metrics
- Airtable API call metrics
- Cache hit/miss rates
- Workflow execution metrics
- Background task metrics

### Logging
Structured logging with:
- Request/response logging
- Error tracking
- Performance metrics
- Context propagation

### Health Checks
- `/health` - Basic health check
- `/health/detailed` - Dependency status
- `/ready` - Kubernetes readiness probe
- `/live` - Kubernetes liveness probe

## Deployment

### Docker Production
```bash
# Build production image
make build-prod

# Run with production config
docker run -d \
  --name airtable-domain \
  -p 8000:8000 \
  -e DATABASE_URL=postgresql://... \
  -e REDIS_URL=redis://... \
  -e AIRTABLE_TOKEN=... \
  pyairtable-airtable-domain:latest
```

### Kubernetes
```bash
# Deploy to Kubernetes
make k8s-deploy

# Check status
kubectl get pods -l app=airtable-domain
```

## Security

- API key authentication for service-to-service communication
- JWT token support for user authentication
- Input validation and sanitization
- Rate limiting protection
- CORS configuration
- Security headers middleware

## Performance

- Async/await throughout for high concurrency
- Connection pooling for database and Redis
- Response caching with configurable TTL
- Batch operation support
- Background task processing
- Horizontal scaling support

## Migration from Existing Services

This service consolidates functionality from:
- `airtable-gateway` - Migrated with enhanced features
- `business-logic-engine` - To be integrated
- `workflow-automation` - Framework established

### Migration Steps
1. **Phase 1**: Airtable Gateway migration (✅ Complete)
2. **Phase 2**: Business Logic Engine integration
3. **Phase 3**: Workflow automation features
4. **Phase 4**: Advanced scheduling and triggers

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Run quality checks: `make lint test`
5. Submit pull request

## License

This project is part of the PyAirtable ecosystem.

---

For more information, see the [API documentation](http://localhost:8000/docs) when running the service.