# Sprint 2 E2E Test Suite

Comprehensive end-to-end testing framework for Sprint 2 integration stack validation.

## Overview

This test suite validates the complete Sprint 2 integration including:

- **Chat UI** (port 3001) - Frontend chat interface
- **API Gateway** (port 8000) - Backend API orchestration  
- **Airtable Gateway** (port 8002) - Enhanced CRUD operations
- **MCP Server** (port 8001) - 10+ tools for Airtable operations
- **LLM Orchestrator** (port 8003) - AI coordination service
- **Authentication** - Sprint 1 integration

## Test Components

### 1. Automated E2E Tests (`sprint2-e2e-test-suite.py`)

Comprehensive automated test suite covering:

- Service health checks across all components
- Authentication integration and token validation
- Chat UI integration with Playwright
- MCP tools execution and validation
- Airtable Gateway CRUD operations
- WebSocket communication testing
- File upload and processing workflows
- Performance requirements validation
- Error handling and edge cases
- Complete end-to-end user flows

### 2. Manual Test Scenarios (`sprint2-manual-test-scenarios.py`)

Structured manual test scenarios for:

- Complex user authentication flows
- Multi-step chat interactions with tool execution
- File upload with real-time processing feedback
- WebSocket connection reliability under network conditions
- Error recovery and user experience validation
- Performance testing under load
- Cross-browser compatibility

### 3. Comprehensive Test Runner (`sprint2-comprehensive-test-runner.py`)

Master orchestrator that:

- Validates test environment readiness
- Executes automated test suite
- Generates manual test guidance
- Performs performance analysis
- Assesses integration health
- Creates actionable recommendations
- Generates comprehensive deliverables

## Quick Start

### Prerequisites

Ensure all Sprint 2 services are running:

```bash
docker-compose up -d
```

### Run Complete Test Suite

```bash
# Run everything (automated + manual guidance)
./run-sprint2-tests.sh

# Run only automated tests
./run-sprint2-tests.sh --automated-only

# Generate only manual test guidance  
./run-sprint2-tests.sh --manual-only

# Skip environment setup
./run-sprint2-tests.sh --skip-setup

# Enable verbose logging
./run-sprint2-tests.sh --verbose
```

## Test Categories

### Functional Tests
- ✅ Service health validation
- ✅ Authentication flows
- ✅ API endpoint functionality
- ✅ Chat interface operations
- ✅ Tool execution workflows
- ✅ File processing capabilities

### Integration Tests  
- ✅ Service-to-service communication
- ✅ Authentication token propagation
- ✅ MCP tools ↔ Airtable Gateway integration
- ✅ LLM Orchestrator ↔ MCP Server coordination
- ✅ Chat UI ↔ Backend API integration
- ✅ WebSocket real-time communication

### Performance Tests
- ✅ Response time validation (Chat < 2s, Airtable API < 500ms)
- ✅ Concurrent user handling
- ✅ Resource usage monitoring
- ✅ Connection stability
- ✅ Memory leak detection

### User Experience Tests
- ✅ End-to-end user workflows
- ✅ Error handling and recovery
- ✅ Loading states and feedback
- ✅ Cross-browser compatibility
- ✅ Network resilience

## Success Criteria

### Automated Test Targets
- **Pass Rate:** ≥ 90% for production readiness
- **Chat Response Time:** ≤ 2 seconds
- **Airtable API Response:** ≤ 500ms  
- **Concurrent Users:** ≥ 95% success rate
- **Service Health:** All services healthy

### Integration Health Targets
- All service-to-service connections working
- Authentication properly validated across services
- MCP tools executing Airtable operations successfully
- Real-time communication functioning
- Error handling graceful across all components

### Manual Test Validation
- User workflows intuitive and complete
- Error messages user-friendly and actionable  
- Performance acceptable under realistic usage
- Cross-browser functionality consistent
- Recovery mechanisms effective

## Architecture

### Service Dependencies
```
Chat UI (3001)
    ↓
API Gateway (8000)
    ├── Auth Service
    ├── LLM Orchestrator (8003)
    └── File Processing
         ↓
LLM Orchestrator (8003)
    ↓
MCP Server (8001)
    ├── Tool 1: list_bases
    ├── Tool 2: list_tables  
    ├── Tool 3: get_records
    ├── Tool 4: create_record
    └── ... (10+ tools)
         ↓
Airtable Gateway (8002)
    └── Airtable API
```

---

*This test suite ensures Sprint 2 integration quality and production readiness through comprehensive automated and manual validation.*