# PyAirtable AI Domain Service

A consolidated AI domain service that combines LLM orchestration, model serving, and MCP (Model Context Protocol) tools into a single, efficient microservice.

## Features

### LLM Orchestration
- **Multi-provider support**: OpenAI, Anthropic, Google Gemini, Azure OpenAI, Ollama
- **Automatic fallbacks**: Seamless switching between providers
- **Cost tracking**: Real-time token usage and cost monitoring
- **Response caching**: Redis-based caching for improved performance
- **Rate limiting**: Configurable per-user rate limits

### Model Serving
- **Local model hosting**: Serve embedding and classification models locally
- **Model caching**: Intelligent model loading and memory management
- **GPU support**: Optimized for GPU acceleration when available
- **Performance monitoring**: Detailed inference metrics and logging

### MCP Tools
- **Airtable integration**: Complete CRUD operations for Airtable bases
- **AI-powered tools**: Text classification, summarization, entity extraction
- **Vector search**: Semantic search using embeddings
- **Extensible architecture**: Easy to add custom tools

## Quick Start

### Prerequisites
- Docker and Docker Compose
- Python 3.11+ (for local development)
- API keys for LLM providers (optional, but recommended)

### Environment Setup

1. **Clone and setup**:
```bash
cd /Users/kg/IdeaProjects/pyairtable-compose/pyairtable-ai-domain
cp .env.example .env
```

2. **Configure environment variables** in `.env`:
```env
# LLM Provider API Keys
OPENAI_API_KEY=your_openai_key_here
ANTHROPIC_API_KEY=your_anthropic_key_here
GEMINI_API_KEY=your_gemini_key_here

# Service Configuration
DEBUG=true
LOG_LEVEL=INFO
PORT=8080

# External Service URLs
AIRTABLE_GATEWAY_URL=http://localhost:8001
AUTH_SERVICE_URL=http://localhost:8002
```

### Running with Docker

**Development mode**:
```bash
docker-compose up -d
```

**Production mode**:
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Local Development

1. **Install dependencies**:
```bash
poetry install
```

2. **Start supporting services**:
```bash
docker-compose up -d postgres redis qdrant
```

3. **Run the service**:
```bash
poetry run python -m src.main
```

## API Documentation

Once running, access the interactive API documentation at:
- **Swagger UI**: http://localhost:8080/docs
- **ReDoc**: http://localhost:8080/redoc

### Key Endpoints

#### LLM Operations
- `POST /api/v1/llm/chat/completions` - Chat completions
- `POST /api/v1/llm/chat/completions/stream` - Streaming chat
- `POST /api/v1/llm/embeddings` - Generate embeddings
- `GET /api/v1/llm/models` - List available models

#### MCP Tools
- `POST /api/v1/mcp/tools/execute` - Execute a tool
- `GET /api/v1/mcp/tools` - List available tools
- `POST /api/v1/mcp/tools/batch` - Execute multiple tools

#### Model Management
- `POST /api/v1/models/load` - Load a model
- `GET /api/v1/models` - List loaded models
- `POST /api/v1/models/embeddings` - Generate embeddings locally

#### Health and Monitoring
- `GET /health` - Comprehensive health check
- `GET /health/ready` - Kubernetes readiness probe
- `GET /health/live` - Kubernetes liveness probe
- `GET /metrics` - Prometheus metrics

## Configuration

### LLM Providers

Configure providers through environment variables:

```env
# OpenAI
OPENAI_API_KEY=sk-...
OPENAI_BASE_URL=https://api.openai.com/v1  # Optional
OPENAI_ORGANIZATION=org-...  # Optional

# Anthropic
ANTHROPIC_API_KEY=sk-ant-...

# Google Gemini
GEMINI_API_KEY=...
GEMINI_MODEL=gemini-2.0-flash-exp

# Azure OpenAI
AZURE_OPENAI_API_KEY=...
AZURE_OPENAI_ENDPOINT=https://....openai.azure.com/
```

### Vector Databases

Supports multiple vector database providers:

```env
# Qdrant (default)
VECTOR_DB_PROVIDER=qdrant
QDRANT_URL=http://localhost:6333

# Pinecone
VECTOR_DB_PROVIDER=pinecone
PINECONE_API_KEY=...
PINECONE_ENVIRONMENT=us-east-1-aws

# Weaviate
VECTOR_DB_PROVIDER=weaviate
WEAVIATE_URL=http://localhost:8080
```

### Cost Tracking

Enable cost tracking and alerts:

```env
ENABLE_COST_TRACKING=true
COST_ALERT_THRESHOLD=100.0  # USD
```

## Architecture

The service is organized into several key modules:

### Core (`src/core/`)
- **config.py**: Centralized configuration management
- **app.py**: FastAPI application factory
- **logging.py**: Structured logging with metrics

### Services (`src/services/`)
- **llm/**: LLM provider abstractions and management
- **models/**: Local model serving and caching
- **mcp/**: MCP tool registry and execution

### Models (`src/models/`)
- **llm/**: Pydantic models for LLM operations
- **mcp/**: MCP tool definitions and schemas

### Routers (`src/routers/`)
- **llm/**: LLM endpoints (chat, embeddings, etc.)
- **mcp/**: MCP tool endpoints
- **models/**: Model management endpoints

## Monitoring and Observability

### Metrics
- **Prometheus integration**: Detailed metrics for requests, tokens, costs
- **Custom metrics**: LLM-specific metrics (tokens/second, cost per request)
- **Health checks**: Comprehensive health monitoring

### Logging
- **Structured logging**: JSON-formatted logs with correlation IDs
- **Performance tracking**: Request tracing and latency monitoring
- **Cost logging**: Detailed token usage and cost tracking

### Dashboards
- **Grafana dashboards**: Pre-built dashboards for monitoring
- **Cost tracking**: Real-time cost monitoring and alerting

## Security

### Authentication
- **JWT-based auth**: Secure API access with JWT tokens
- **Rate limiting**: Per-user and per-endpoint rate limiting
- **API key validation**: Secure provider API key management

### Data Protection
- **Input validation**: Comprehensive request validation
- **SQL injection protection**: Safe database query execution
- **Sandboxed execution**: Safe code execution for calculations

## Performance Optimization

### Caching
- **Response caching**: Redis-based response caching
- **Model caching**: Intelligent model loading and eviction
- **Session management**: Efficient chat session handling

### Resource Management
- **Memory monitoring**: Automatic model cleanup based on memory usage
- **Connection pooling**: Efficient database and HTTP connections
- **Async processing**: Non-blocking I/O for all operations

## Development

### Code Quality
```bash
# Format code
poetry run black src/
poetry run isort src/

# Type checking
poetry run mypy src/

# Linting
poetry run flake8 src/
```

### Testing
```bash
# Run all tests
poetry run pytest

# Run with coverage
poetry run pytest --cov=src --cov-report=html

# Run specific test categories
poetry run pytest -m "unit"
poetry run pytest -m "integration"
poetry run pytest -m "ai" --env=test
```

### Pre-commit Hooks
```bash
poetry run pre-commit install
poetry run pre-commit run --all-files
```

## Deployment

### Kubernetes
The service includes Kubernetes manifests for production deployment:

```bash
# Apply configurations
kubectl apply -f k8s/

# Check deployment
kubectl get pods -l app=pyairtable-ai-domain
```

### Helm Chart
```bash
# Install with Helm
helm install ai-domain ./helm/pyairtable-ai-domain

# Upgrade
helm upgrade ai-domain ./helm/pyairtable-ai-domain
```

## Troubleshooting

### Common Issues

1. **Model loading failures**:
   - Check available memory
   - Verify model names and paths
   - Check network connectivity for downloads

2. **Provider API errors**:
   - Verify API keys are correct
   - Check rate limits and quotas
   - Monitor provider status pages

3. **Performance issues**:
   - Monitor memory usage and model cache
   - Check database connection pool settings
   - Review Redis performance metrics

### Debug Mode
Enable debug mode for detailed logging:

```env
DEBUG=true
LOG_LEVEL=DEBUG
```

### Health Checks
Monitor service health:

```bash
# Basic health check
curl http://localhost:8080/health

# Detailed component status
curl http://localhost:8080/health | jq '.checks'
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.