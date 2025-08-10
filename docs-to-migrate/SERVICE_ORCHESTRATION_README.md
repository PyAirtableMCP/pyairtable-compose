# PyAirtable Service Startup Orchestration

## Overview

This document describes the comprehensive service startup orchestration system implemented for the PyAirtable microservices architecture. The system ensures reliable, dependency-aware service startup and graceful shutdown with health validation.

## System Architecture

### Service Dependency Tiers

The services are organized into 7 tiers based on their dependencies:

#### Tier 1: Infrastructure Services
- **PostgreSQL Database** (`postgres`) - Primary data store
- **Redis Cache** (`redis`) - Session storage and caching

#### Tier 2: Platform Services  
- **Airtable Gateway** (`airtable-gateway`) - Direct Airtable API integration
- **Platform Services** (`platform-services`) - Unified Auth & Analytics

#### Tier 3: Protocol Layer
- **MCP Server** (`mcp-server`) - Model Context Protocol implementation

#### Tier 4: Processing Layer
- **LLM Orchestrator** (`llm-orchestrator`) - Gemini 2.5 Flash integration
- **Automation Services** (`automation-services`) - File processing and workflow automation

#### Tier 5: Coordination Layer
- **SAGA Orchestrator** (`saga-orchestrator`) - Distributed transaction coordination

#### Tier 6: Gateway Layer
- **API Gateway** (`api-gateway`) - Main entry point and request routing

#### Tier 7: Presentation Layer
- **Frontend Dashboard** (`frontend`) - Next.js web interface

## Core Components

### 1. Enhanced Docker Compose Configuration

The main `docker-compose.yml` has been updated with:

- **Comprehensive Health Checks**: All services include proper health check configurations
- **Dependency Management**: Uses `depends_on` with `condition: service_healthy`
- **Retry Logic**: Health checks include appropriate intervals, timeouts, and retry counts
- **Start Period Buffers**: Services have adequate time to initialize before health checks begin

#### Example Health Check Configuration:
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f http://localhost:8002/health || exit 1"]
  interval: 15s
  timeout: 10s
  retries: 3
  start_period: 30s
```

### 2. Wait-for Scripts

#### `scripts/wait-for-database.sh`
- **Purpose**: Ensures PostgreSQL is ready for connections
- **Features**: 
  - Connection testing with retry logic
  - Schema validation
  - Migration status checking
  - Configurable timeouts and intervals

#### `scripts/wait-for-redis.sh`
- **Purpose**: Ensures Redis is ready and operational
- **Features**:
  - Authentication-aware connection testing
  - Operation testing (SET/GET/DELETE)
  - Memory usage monitoring
  - Server information retrieval

#### `scripts/wait-for-service.sh`
- **Purpose**: Generic HTTP service health checking
- **Features**:
  - Configurable health endpoints
  - Response time monitoring
  - Endpoint discovery
  - Service information gathering

### 3. Startup Orchestration Script

#### `start-services.sh`
The main orchestration script that manages the entire startup process:

**Key Features:**
- **Tiered Startup**: Services start in proper dependency order
- **Health Validation**: Each tier waits for health confirmation before proceeding
- **Failure Handling**: Failed tiers prevent dependent tiers from starting
- **Progress Tracking**: Real-time status updates and timing information
- **Environment Validation**: Checks required environment variables

**Usage:**
```bash
# Standard startup
./start-services.sh

# With debug output
DEBUG=1 ./start-services.sh

# Show help
./start-services.sh help
```

**Startup Flow:**
1. Prerequisites check (Docker, Compose, .env file, required variables)
2. Cleanup existing containers
3. Tier-by-tier service startup with health validation
4. Service URL display and monitoring instructions

### 4. Graceful Shutdown Script

#### `stop-services.sh`
Manages intelligent shutdown in reverse dependency order:

**Key Features:**
- **Reverse Dependency Order**: Shuts down in opposite order of startup
- **Graceful Shutdown**: Sends SIGTERM first, allowing services to cleanup
- **Force Shutdown Fallback**: Uses SIGKILL if graceful shutdown times out
- **Data Safety**: Performs critical data backup checks before shutdown
- **Resource Cleanup**: Removes orphaned containers and networks

**Usage:**
```bash
# Graceful shutdown
./stop-services.sh

# Emergency shutdown (force)
./stop-services.sh emergency

# With volume cleanup
CLEANUP_VOLUMES=true ./stop-services.sh
```

## Configuration

### Environment Variables

Required variables in `.env` file:
```bash
# Database Configuration
POSTGRES_USER=admin
POSTGRES_PASSWORD=your-secure-password
POSTGRES_DB=pyairtable

# Redis Configuration  
REDIS_PASSWORD=your-redis-password

# API Keys
AIRTABLE_TOKEN=your-airtable-token
GEMINI_API_KEY=your-gemini-api-key
API_KEY=your-api-key

# Security
JWT_SECRET=your-jwt-secret
NEXTAUTH_SECRET=your-nextauth-secret
```

### Customization Options

#### Timing Configuration
```bash
# In start-services.sh
TIER_WAIT_TIME=30              # Seconds between tier starts
SERVICE_STARTUP_DELAY=10       # Delay after starting tier services
HEALTH_CHECK_TIMEOUT=120       # Maximum time to wait for health check
MAX_STARTUP_TIME=600           # Total startup timeout
```

#### Health Check Tuning
```bash
# In wait-for scripts
MAX_RETRIES=30                 # Maximum retry attempts
RETRY_INTERVAL=5               # Seconds between retries
TIMEOUT=150                    # Total timeout for service
```

## Monitoring and Troubleshooting

### Service Status Checking

```bash
# Check all service status
docker-compose ps

# Check specific service logs
docker-compose logs -f [service-name]

# Test individual health endpoints
curl http://localhost:8000/health  # API Gateway
curl http://localhost:8007/health  # Platform Services
curl http://localhost:8002/health  # Airtable Gateway
```

### Common Issues and Solutions

#### 1. Database Connection Issues
```bash
# Check database connectivity
docker-compose exec postgres pg_isready -U admin

# View database logs
docker-compose logs postgres

# Manual connection test
./scripts/wait-for-database.sh
```

#### 2. Redis Connection Issues
```bash
# Test Redis connectivity
docker-compose exec redis redis-cli -a your-password ping

# View Redis logs
docker-compose logs redis

# Manual connection test
./scripts/wait-for-redis.sh
```

#### 3. Service Health Check Failures
```bash
# Test service health manually
./scripts/wait-for-service.sh http://service-name:port

# Check service logs for errors
docker-compose logs service-name

# Restart specific service
docker-compose restart service-name
```

#### 4. Startup Timeout Issues
```bash
# Increase timeout values
export HEALTH_CHECK_TIMEOUT=300
export MAX_STARTUP_TIME=900
./start-services.sh

# Start with debug output
DEBUG=1 ./start-services.sh
```

## Service URLs

Once all services are running, the following URLs are available:

| Service | URL | Description |
|---------|-----|-------------|
| Frontend Dashboard | http://localhost:3000 | Web interface |
| API Gateway | http://localhost:8000 | Main API endpoint |
| MCP Server | http://localhost:8001 | Protocol server |
| Airtable Gateway | http://localhost:8002 | Airtable integration |
| LLM Orchestrator | http://localhost:8003 | AI processing |
| Automation Services | http://localhost:8006 | File & workflow processing |
| Platform Services | http://localhost:8007 | Auth & analytics |
| SAGA Orchestrator | http://localhost:8008 | Transaction coordination |

## Best Practices

### 1. Environment Management
- Keep `.env` file secure and never commit to version control
- Use strong passwords for database and Redis
- Rotate API keys regularly
- Use environment-specific configurations

### 2. Monitoring
- Monitor service health endpoints regularly
- Set up log aggregation for production
- Implement alerting for service failures
- Track startup/shutdown times

### 3. Troubleshooting
- Always check service logs first when issues occur
- Use the wait-for scripts to test individual service connectivity
- Verify environment variables are set correctly
- Test services in isolation when debugging

### 4. Production Deployment
- Use external managed databases and Redis for production
- Implement proper secrets management
- Set up load balancing for API Gateway
- Configure persistent storage for volumes
- Implement backup strategies for data services

## Migration from Legacy Startup

If migrating from the old startup system:

1. **Backup current configuration**:
   ```bash
   cp docker-compose.yml docker-compose.yml.backup
   cp start-all-services.sh start-all-services.sh.backup
   ```

2. **Update environment file**:
   - Ensure all required variables are present
   - Update any changed variable names

3. **Test new startup system**:
   ```bash
   ./stop-services.sh
   ./start-services.sh
   ```

4. **Verify all services are healthy**:
   ```bash
   docker-compose ps
   ./scripts/wait-for-service.sh http://localhost:8000/health
   ```

## Performance Considerations

### Startup Performance
- **Parallel within tiers**: Services in the same tier start simultaneously
- **Health check optimization**: Tuned intervals prevent unnecessary waiting
- **Smart timeouts**: Different timeouts for different service types

### Resource Usage
- **Memory efficient**: Health checks use minimal resources
- **Network optimized**: Health checks use internal Docker networks
- **CPU conscious**: Wait scripts use efficient polling intervals

### Scaling Considerations
- **Horizontal scaling**: Each tier can be scaled independently
- **Load balancing**: API Gateway supports multiple instances
- **Database clustering**: PostgreSQL can be configured for high availability
- **Redis clustering**: Redis can be clustered for scalability

This orchestration system provides a robust, production-ready foundation for managing the PyAirtable microservices ecosystem with reliability, observability, and operational excellence.