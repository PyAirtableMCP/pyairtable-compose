# PyAirtable Services Documentation

## Overview

After aggressive cleanup, PyAirtable now consists of **6 core services** with actual functionality. We deleted 7 empty services that only had health endpoints and no real implementation.

## Active Services

### 1. **ai-processing-service** (Port: 8001)
**Status**: ✅ **KEEP** - Has real chat functionality
- **Location**: `/pyairtable-python-services/ai-processing-service`
- **Functionality**: 
  - Chat endpoints with echo responses
  - Basic chat model implementation
  - Foundation for AI processing features
- **Routes**: `/api/ai/chat`

### 2. **airtable-gateway** (Port: 8002)
**Status**: ✅ **KEEP** - Full Airtable API integration
- **Location**: `/pyairtable-python-services/airtable-gateway`
- **Functionality**:
  - Complete Airtable CRUD operations
  - Base and table schema retrieval
  - Record management (create, read, update, delete)
  - Cache management with Redis
  - GraphQL schema support
- **Routes**: 
  - `/api/v1/airtable/bases` - List bases
  - `/api/v1/airtable/bases/{base_id}/schema` - Get base schema
  - `/api/v1/airtable/bases/{base_id}/tables/{table_id}/records` - CRUD operations
  - `/api/v1/airtable/cache/invalidate` - Cache management

### 3. **workspace-service** (Port: 8003)
**Status**: ✅ **KEEP** - Full workspace CRUD with database
- **Location**: `/pyairtable-python-services/workspace-service`
- **Functionality**:
  - Complete workspace management system
  - Member management (add, update, remove)
  - Workspace invitations system
  - Role-based access control
  - Database persistence with PostgreSQL
  - JWT authentication middleware
- **Routes**:
  - `/api/v1/workspaces` - CRUD operations
  - `/api/v1/workspaces/{workspace_id}/members` - Member management
  - `/api/v1/workspaces/{workspace_id}/invitations` - Invitation system

### 4. **llm-orchestrator** (Port: Consolidated into ai-processing-service)
**Status**: ✅ **KEEP** - Advanced LLM orchestration
- **Location**: `/pyairtable-python-services/llm-orchestrator`
- **Functionality**:
  - Advanced chat completions with Gemini
  - Streaming chat responses
  - Session management with Redis
  - Table analysis workflows
  - Token counting and usage tracking
  - Quality assurance and error handling
- **Routes**:
  - `/api/v1/chat/completions` - Chat completions
  - `/api/v1/chat/completions/stream` - Streaming chat
  - `/api/v1/sessions` - Session management
  - `/api/v1/table_analysis` - Table analysis workflows
  - `/api/v1/workflow` - Workflow orchestration

### 5. **mcp-server** (Port: Consolidated into ai-processing-service)
**Status**: ✅ **KEEP** - Model Context Protocol server
- **Location**: `/pyairtable-python-services/mcp-server`
- **Functionality**:
  - MCP protocol implementation
  - Tool execution framework
  - Model context management
- **Routes**: `/api/v1/mcp` - MCP endpoints

### 6. **analytics-service** (Port: 8007 as platform-services)
**Status**: ✅ **KEEP** - Has database setup and infrastructure
- **Location**: `/pyairtable-python-services/analytics-service`
- **Functionality**:
  - Database initialization and migrations
  - Basic analytics infrastructure
  - Platform services foundation
- **Note**: Renamed to `platform-services` in docker-compose.yml

### 7. **ai-service** (Port: 8006 as automation-services)
**Status**: ✅ **KEEP** - Simple service for automation
- **Location**: `/pyairtable-python-services/ai-service`
- **Functionality**:
  - Basic AI service endpoints
  - Used as foundation for automation-services
- **Note**: Mapped to `automation-services` in docker-compose.yml

## Deleted Services ❌

The following **7 empty services** were completely removed as they only had health endpoints:

1. **audit-service** - Empty boilerplate
2. **chat-service** - Empty boilerplate (real chat is in ai-processing-service)
3. **embedding-service** - Empty boilerplate
4. **formula-engine** - Empty boilerplate
5. **schema-service** - Empty boilerplate
6. **semantic-search** - Empty boilerplate
7. **workflow-engine** - Empty boilerplate

## Infrastructure Services

### Database Services
- **PostgreSQL** - Primary database for workspaces, sessions, and metadata
- **Redis** - Caching, session storage, and pub/sub

### Gateway & Frontend
- **api-gateway** - Main entry point and routing
- **frontend** - Next.js web interface
- **saga-orchestrator** - Distributed transaction coordination

## Scripts Cleanup

### Kept Scripts (5 Essential)
- `start.sh` - Start all services
- `stop.sh` - Stop all services  
- `test.sh` - Run test suites
- `setup.sh` - Environment setup
- `dev.sh` - Development mode startup

### Archived Scripts (57 scripts → `scripts-archive/`)
All non-essential scripts have been moved to `scripts-archive/` directory for historical reference.

## Service Architecture

```
┌─────────────────┐    ┌───────────────────┐    ┌──────────────────┐
│   Frontend      │────│   API Gateway     │────│  Airtable API    │
│   (Port 3000)   │    │   (Port 8000)     │    │                  │
└─────────────────┘    └───────────────────┘    └──────────────────┘
                                │
                ┌───────────────┼───────────────┐
                │               │               │
    ┌───────────▼────┐ ┌───────▼────────┐ ┌────▼──────────┐
    │ AI Processing  │ │ Airtable       │ │ Workspace     │
    │ Service        │ │ Gateway        │ │ Service       │
    │ (Port 8001)    │ │ (Port 8002)    │ │ (Port 8003)   │
    └────────────────┘ └────────────────┘ └───────────────┘
                                │
                ┌───────────────┼───────────────┐
                │               │               │
        ┌───────▼────┐  ┌──────▼──────┐ ┌──────▼──────────┐
        │ PostgreSQL │  │    Redis    │ │ Platform/Auto   │
        │ Database   │  │   Cache     │ │ Services        │
        └────────────┘  └─────────────┘ └─────────────────┘
```

## Key Improvements After Cleanup

1. **Reduced Complexity**: From 13 services to 6 functional services
2. **Eliminated Bloat**: Removed 57 unnecessary scripts
3. **Clearer Architecture**: Only services with real functionality remain
4. **Easier Maintenance**: Fewer moving parts to manage
5. **Better Resource Usage**: No more empty containers consuming resources

## Next Steps

1. **Consolidation**: Consider further consolidating services that share similar functionality
2. **Documentation**: Update all remaining scripts and services with proper documentation
3. **Testing**: Verify all remaining services work correctly after cleanup
4. **Deployment**: Update CI/CD pipelines to reflect the new simplified architecture