# PyAirtable SAGA Orchestrator

Production-ready SAGA pattern implementation for distributed transactions in the PyAirtable ecosystem.

## Overview

The SAGA Orchestrator service manages distributed transactions across microservices using the SAGA pattern. It ensures data consistency and provides compensation mechanisms for failed transactions.

## Features

- **Event-Driven Architecture**: Listens to domain events and triggers appropriate SAGAs
- **Redis Event Bus**: Reliable event distribution using Redis Streams
- **PostgreSQL Event Store**: Persistent event storage with optimistic concurrency control
- **Compensation Handling**: Automatic rollback of completed steps when failures occur
- **Health Monitoring**: Comprehensive health checks and metrics
- **RESTful API**: Management endpoints for SAGA instances and events

## Available SAGAs

### User Onboarding SAGA
Triggered when a user registers:
1. Create user profile
2. Setup default workspace
3. Send welcome email
4. Setup default Airtable integration

### Airtable Integration SAGA
Triggered when connecting an Airtable base:
1. Validate Airtable access
2. Fetch base schema
3. Setup webhook
4. Perform initial data sync
5. Send success notification

## API Endpoints

### Health
- `GET /health` - Health check with component status
- `GET /health/ready` - Kubernetes readiness probe
- `GET /health/live` - Kubernetes liveness probe

### SAGAs
- `POST /sagas/start` - Start a new SAGA
- `GET /sagas/` - List SAGA instances
- `GET /sagas/{saga_id}` - Get specific SAGA
- `POST /sagas/{saga_id}/cancel` - Cancel running SAGA
- `GET /sagas/{saga_id}/steps` - Get SAGA steps
- `GET /sagas/types/available` - Get available SAGA types

### Events
- `POST /events/publish` - Publish an event
- `GET /events/stream/{stream_id}` - Get events from stream
- `GET /events/all` - Get all events
- `GET /events/types` - Get available event types
- `POST /events/replay/{stream_id}` - Replay events

## Configuration

Environment variables:

```bash
# Application
ENVIRONMENT=development
LOG_LEVEL=INFO
PORT=8008

# Security
API_KEY=your-api-key
REQUIRE_API_KEY=true

# Database
DATABASE_URL=postgresql://user:pass@localhost:5432/db

# Redis
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=optional-password

# Event Bus
USE_REDIS_EVENT_BUS=true

# SAGA Configuration
SAGA_TIMEOUT_SECONDS=3600
SAGA_RETRY_ATTEMPTS=3
SAGA_STEP_TIMEOUT_SECONDS=300

# Service URLs
AUTH_SERVICE_URL=http://platform-services:8007
USER_SERVICE_URL=http://platform-services:8007
PERMISSION_SERVICE_URL=http://platform-services:8007
NOTIFICATION_SERVICE_URL=http://automation-services:8006
AIRTABLE_CONNECTOR_URL=http://airtable-gateway:8002
```

## Development

### Local Setup

1. Install dependencies:
```bash
pip install -e ".[dev]"
```

2. Set up environment variables:
```bash
cp .env.example .env
# Edit .env with your configuration
```

3. Run the service:
```bash
python -m saga_orchestrator.main
```

### Testing

```bash
# Run tests
pytest

# Run tests with coverage
pytest --cov=src --cov-report=html

# Run integration tests
pytest -m integration
```

### Docker

```bash
# Build image
docker build -t pyairtable-saga-orchestrator .

# Run container
docker run -p 8008:8008 \
  -e DATABASE_URL=postgresql://... \
  -e REDIS_URL=redis://... \
  pyairtable-saga-orchestrator
```

## Architecture

The SAGA Orchestrator consists of several key components:

- **Event Store**: PostgreSQL-based persistent storage for events
- **Event Bus**: Redis Streams for reliable event distribution
- **SAGA Engine**: Core orchestration logic with compensation handling
- **API Layer**: FastAPI-based REST endpoints
- **Service Clients**: HTTP clients for calling downstream services

## Event Flow

1. Domain events are published to the event bus
2. SAGA Orchestrator subscribes to relevant events
3. Matching events trigger appropriate SAGA definitions
4. SAGA steps are executed sequentially
5. Step responses update SAGA state
6. Failed steps trigger compensation in reverse order
7. SAGA completion/failure events are published

## Monitoring

The service exposes Prometheus metrics at `/metrics` and provides detailed health checks at `/health`. Logs are structured and include correlation IDs for tracing.

## Security

- API key authentication for external access
- Non-root container execution
- Input validation and sanitization
- Secure service-to-service communication