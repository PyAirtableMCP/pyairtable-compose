# 🚀 Event Infrastructure - Track 1 Implementation

## Overview

This implementation adds comprehensive event infrastructure to PyAirtable with:

- **Redis Event Streams** - Real-time event processing
- **BullMQ Job Queues** - Long-running job processing (10-60 minutes)
- **Dead Letter Queue** - Failed job handling and retry logic
- **Pub/Sub System** - Real-time notifications
- **Queue Monitoring UI** - Visual queue management

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Redis Master  │    │ Redis Streams   │    │  Redis Queue    │
│   (Port 6379)   │    │  (Port 6380)    │    │  (Port 6381)    │
│                 │    │                 │    │                 │
│ • Sessions      │    │ • Event Streams │    │ • Job Queues    │
│ • Pub/Sub       │    │ • Real-time     │    │ • Long-running  │
│ • Caching       │    │ • Event Log     │    │ • Persistence   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
┌─────────────────────────────────┼─────────────────────────────────┐
│                                 │                                 │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐ │
│  │ Event Processor │   │ Queue Processor │   │  DLQ Processor  │ │
│  │                 │   │                 │   │                 │ │
│  │ • Stream Reader │   │ • Job Worker    │   │ • Failed Jobs   │ │
│  │ • Event Router  │   │ • BullMQ UI     │   │ • Retry Logic   │ │
│  │ • Real-time     │   │ • Monitoring    │   │ • Alerting      │ │
│  └─────────────────┘   └─────────────────┘   └─────────────────┘ │
│                                 │                                 │
│                     Queue UI (Port 8009)                         │
└───────────────────────────────────────────────────────────────────┘
```

## 🔧 Services Added

### 1. Redis Infrastructure (3 instances)
- **redis** (6379) - Sessions, caching, pub/sub
- **redis-streams** (6380) - Event streaming
- **redis-queue** (6381) - Job queue persistence

### 2. Queue System
- **queue-processor** (8009) - BullMQ with monitoring UI
- **event-processor** - Real-time event stream processing
- **dlq-processor** - Dead letter queue handling

## 🚦 Quick Start

### 1. Environment Setup
```bash
# Copy environment template
cp env-example-event-infrastructure .env

# Update required variables
vim .env  # Set REDIS_PASSWORD, API_KEY, etc.
```

### 2. Start Services
```bash
# Start all services
docker-compose up -d

# Check service health
docker-compose ps
```

### 3. Verify Installation
```bash
# Run comprehensive test suite
./test-event-infrastructure.sh

# Check individual components
curl http://localhost:8009/health  # Queue UI
curl http://localhost:8009/stats   # Queue statistics
```

## 📊 Access Points

| Service | URL | Purpose |
|---------|-----|---------|
| Queue UI | http://localhost:8009/admin/queues | Visual queue management |
| Queue Health | http://localhost:8009/health | Health check |
| Queue Stats | http://localhost:8009/stats | Real-time statistics |
| Queue API | http://localhost:8009/jobs/{queue} | Job submission |
| Redis Master | localhost:6382 | Direct Redis access |
| Redis Streams | localhost:6380 | Event streams |
| Redis Queue | localhost:6381 | Job persistence |

## 🎯 Usage Examples

### Publishing Events
```javascript
// Using the event publisher utility
const { createEventPublisher } = require('./event-system/event-publisher');

const publisher = createEventPublisher();
await publisher.connect();

// Publish events
await publisher.publishUserEvent('created', 'user123', { 
  email: 'user@example.com' 
});

await publisher.publishWorkspaceEvent('updated', 'ws456', { 
  name: 'My Workspace' 
});

await publisher.notifyUser('user123', 'Welcome message');
```

### Creating Jobs
```bash
# Create a long-running job via API
curl -X POST http://localhost:8009/jobs/long-running-jobs \
  -H "Content-Type: application/json" \
  -d '{
    "name": "data-sync",
    "data": { "baseId": "appXXXXXX", "records": 1000 },
    "options": { "timeout": 3600000 }
  }'

# Create async processing job
curl -X POST http://localhost:8009/jobs/async-processing \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ai-processing",
    "data": { "text": "Process this content" }
  }'
```

### Redis Commands
```bash
# Event streams
redis-cli -h localhost -p 6380 -a $REDIS_PASSWORD XREAD COUNT 10 STREAMS pyairtable-events 0

# Pub/Sub
redis-cli -h localhost -p 6382 -a $REDIS_PASSWORD PUBLISH user:123 "notification message"

# Queue inspection
redis-cli -h localhost -p 6381 -a $REDIS_PASSWORD KEYS "*queue*"
```

## 🔍 Monitoring

### Queue Statistics
```bash
# Get current queue stats
curl http://localhost:8009/stats

# Response format:
{
  "long-running-jobs": {
    "waiting": 5,
    "active": 2,
    "completed": 150,
    "failed": 3
  },
  "async-processing": { ... },
  "dead-letter-queue": { ... }
}
```

### Health Checks
All services include health checks with appropriate intervals:
- **Redis instances**: 10s interval, 8 retries
- **Queue processor**: 30s interval, 5 retries  
- **Event processor**: 30s interval, 3 retries
- **DLQ processor**: 30s interval, 3 retries

### Logs
```bash
# View service logs
docker-compose logs -f queue-processor
docker-compose logs -f event-processor
docker-compose logs -f dlq-processor

# View specific service
docker-compose logs -f redis-streams
```

## 🛠️ Job Types Supported

### 1. Long-Running Jobs (10-60 minutes)
- AI processing tasks
- Bulk data operations
- Complex calculations
- Large file processing

### 2. Async Processing Jobs (seconds to minutes)
- Data synchronization
- Notifications
- Quick computations
- API integrations

### 3. Event-Driven Jobs
- Real-time responses
- Trigger-based actions
- Workflow steps
- Status updates

## 💪 Persistence & Reliability

### Job Persistence
- All queues persist to Redis with AOF (Append Only File)
- Jobs survive service restarts
- Configurable retention periods
- Automatic cleanup of old jobs

### Failure Handling
- **Automatic Retries**: Exponential backoff
- **Dead Letter Queue**: Failed jobs sent to DLQ
- **Manual Recovery**: DLQ processor analyzes and retries
- **Alerting**: Failed jobs trigger alerts

### High Availability
- Redis persistence with fsync
- Health checks for all components
- Graceful shutdown handling
- Connection retry logic

## 🚨 Troubleshooting

### Common Issues

#### Redis Connection Errors
```bash
# Check Redis status
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD ping
redis-cli -h localhost -p 6380 -a $REDIS_PASSWORD ping
redis-cli -h localhost -p 6381 -a $REDIS_PASSWORD ping

# Check Docker containers
docker-compose ps redis redis-streams redis-queue
```

#### Queue UI Not Accessible
```bash
# Check queue processor logs
docker-compose logs queue-processor

# Verify port binding
netstat -tlnp | grep 8009

# Test health endpoint
curl -v http://localhost:8009/health
```

#### Jobs Not Processing
```bash
# Check worker status
curl http://localhost:8009/stats

# View queue processor logs
docker-compose logs -f queue-processor

# Check Redis queue
redis-cli -h localhost -p 6381 -a $REDIS_PASSWORD KEYS "*"
```

#### Event Processing Issues
```bash
# Check event processor logs
docker-compose logs event-processor

# Inspect event stream
redis-cli -h localhost -p 6380 -a $REDIS_PASSWORD XINFO STREAM pyairtable-events
```

### Performance Tuning

#### Redis Configuration
```bash
# Memory usage
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD INFO memory

# Keyspace statistics
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD INFO keyspace
```

#### Queue Optimization
- Adjust `CONCURRENCY` for worker threads
- Tune `MAX_JOB_ATTEMPTS` for retry behavior
- Set appropriate job timeouts
- Configure job retention periods

## 🔐 Security

### Access Control
- Redis password authentication required
- Internal Docker network isolation
- API key authentication for external access
- Health endpoints require no authentication

### Data Protection
- Redis persistence with secure storage
- Environment variable security
- Connection encryption available
- Audit logging for job operations

## 📈 Success Criteria ✅

All deliverables have been completed:

1. **✅ Redis Infrastructure**: 3 Redis instances (master, streams, queue)
2. **✅ Job Queue System**: BullMQ with persistence and 60-minute job support
3. **✅ Event Infrastructure**: Pub/sub, streaming, and DLQ
4. **✅ Integration Points**: Port 6379 (Redis), Port 8009 (Queue UI)
5. **✅ Testing**: Comprehensive test suite validates all functionality

## 🎉 Next Steps

The event infrastructure is now ready for:
- Integration with existing services
- Custom event handlers
- Long-running workflow implementation
- Real-time notification system
- Advanced monitoring and alerting

Access the Queue UI at: **http://localhost:8009/admin/queues**