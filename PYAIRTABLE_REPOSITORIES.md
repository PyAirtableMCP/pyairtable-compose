# PyAirtable Microservices Platform - Repository List

This document lists all repositories that are part of the PyAirtable microservices platform. Use this to create a GitHub Project and add these repositories.

## Core Services

### 1. **pyairtable-compose** ⭐ (Main Orchestration)
- **URL**: https://github.com/Reg-Kris/pyairtable-compose
- **Description**: Docker Compose orchestration and Kubernetes deployment for all services
- **Key Features**: Docker Compose configs, Helm charts, deployment scripts

### 2. **pyairtable-frontend** 🎨
- **URL**: https://github.com/Reg-Kris/pyairtable-frontend
- **Description**: Next.js 15 frontend with TypeScript
- **Key Features**: Chat interface, cost tracking, dashboard, settings

### 3. **pyairtable-api-gateway** 🚪
- **URL**: https://github.com/Reg-Kris/pyairtable-api-gateway
- **Description**: Central API gateway for routing and authentication
- **Key Features**: Request routing, WebSocket support, health aggregation

### 4. **llm-orchestrator-py** 🧠
- **URL**: https://github.com/Reg-Kris/llm-orchestrator-py
- **Description**: Gemini 2.5 Flash integration and chat orchestration
- **Key Features**: LLM integration, session management, cost tracking

### 5. **mcp-server-py** 🔧
- **URL**: https://github.com/Reg-Kris/mcp-server-py
- **Description**: Model Context Protocol server with 14 Airtable tools
- **Key Features**: MCP tools, HTTP mode, modular handlers

### 6. **airtable-gateway-py** 📊
- **URL**: https://github.com/Reg-Kris/airtable-gateway-py
- **Description**: Airtable API wrapper service
- **Key Features**: CRUD operations, caching, rate limiting

### 7. **pyairtable-platform-services** 🔐
- **URL**: https://github.com/Reg-Kris/pyairtable-platform-services
- **Description**: Consolidated authentication and analytics services
- **Key Features**: JWT auth, user management, metrics collection

### 8. **pyairtable-automation-services** ⚙️
- **URL**: https://github.com/Reg-Kris/pyairtable-automation-services
- **Description**: Consolidated file processing and workflow automation
- **Key Features**: File processing (CSV/PDF/DOCX), workflow scheduling

## Supporting Libraries

### 9. **pyairtable-common** 📦
- **URL**: https://github.com/Reg-Kris/pyairtable-common
- **Description**: Shared utilities and base classes
- **Key Features**: Security, middleware, database models, cost tracking

## Legacy/Archived Services

### 10. **pyairtable-auth-service** (Merged into platform-services)
- **URL**: https://github.com/Reg-Kris/pyairtable-auth-service
- **Status**: Archived - functionality merged into platform-services

### 11. **pyairtable-analytics-service** (Merged into platform-services)
- **URL**: https://github.com/Reg-Kris/pyairtable-analytics-service
- **Status**: Archived - functionality merged into platform-services

### 12. **pyairtable-workflow-engine** (Merged into automation-services)
- **URL**: https://github.com/Reg-Kris/pyairtable-workflow-engine
- **Status**: Archived - functionality merged into automation-services

### 13. **pyairtable-file-processor** (Merged into automation-services)
- **URL**: https://github.com/Reg-Kris/pyairtable-file-processor
- **Status**: Archived - functionality merged into automation-services

## Creating a GitHub Project

1. Go to https://github.com/Reg-Kris?tab=projects
2. Click "New project"
3. Choose "Board" template
4. Name it "PyAirtable Microservices Platform"
5. Add all the active repositories (1-9) to the project
6. Create columns:
   - Backlog
   - In Progress
   - Testing
   - Done
7. Add cards for current work items

## Architecture Diagram

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│   Frontend  │────▶│ API Gateway  │────▶│ LLM Orchestrator│
└─────────────┘     └──────────────┘     └─────────────────┘
                            │                      │
                            ▼                      ▼
                    ┌──────────────┐     ┌─────────────────┐
                    │ MCP Server   │────▶│Airtable Gateway │
                    └──────────────┘     └─────────────────┘
                            │
                    ┌───────┴────────┐
                    ▼                ▼
          ┌──────────────┐  ┌──────────────────┐
          │Platform Svcs │  │Automation Svcs   │
          └──────────────┘  └──────────────────┘
```

## Quick Links

- **Main Documentation**: [pyairtable-compose README](https://github.com/Reg-Kris/pyairtable-compose)
- **Local Setup**: [LOCAL_DEVELOPMENT_GUIDE.md](https://github.com/Reg-Kris/pyairtable-compose/blob/main/LOCAL_DEVELOPMENT_GUIDE.md)
- **Security**: [SECURITY_CHECKLIST.md](https://github.com/Reg-Kris/pyairtable-compose/blob/main/SECURITY_CHECKLIST.md)
- **Kubernetes**: [k8s/README.md](https://github.com/Reg-Kris/pyairtable-compose/blob/main/k8s/README.md)