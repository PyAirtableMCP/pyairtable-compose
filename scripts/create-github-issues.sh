#!/bin/bash

# PyAirtable GitHub Issues Creation Script
# This script creates all GitHub issues for the 3-sprint agile plan

set -e

echo "🚀 Creating PyAirtable Agile Sprint Issues"
echo "========================================"

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed. Please install it first."
    echo "Visit: https://cli.github.com/"
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
    echo "❌ Please authenticate with GitHub CLI first:"
    echo "gh auth login"
    exit 1
fi

echo "✅ GitHub CLI is ready"

# Create labels if they don't exist
echo "📋 Creating project labels..."
gh label create "P0" --description "Critical priority" --color "d73a49" --force
gh label create "P1" --description "High priority" --color "fb8500" --force
gh label create "P2" --description "Medium priority" --color "28a745" --force
gh label create "sprint1" --description "Sprint 1 issues" --color "0e4429" --force
gh label create "sprint2" --description "Sprint 2 issues" --color "1f6feb" --force
gh label create "sprint3" --description "Sprint 3 issues" --color "8b5cf6" --force
gh label create "authentication" --description "Authentication related" --color "6f42c1" --force
gh label create "testing" --description "Testing infrastructure" --color "d1ecf1" --force
gh label create "observability" --description "Monitoring and logging" --color "fd7e14" --force
gh label create "infrastructure" --description "Infrastructure and DevOps" --color "6c757d" --force
gh label create "airtable" --description "Airtable integration" --color "18beaa" --force
gh label create "frontend" --description "Frontend development" --color "61dafb" --force
gh label create "performance" --description "Performance optimization" --color "ff6b35" --force
gh label create "security" --description "Security hardening" --color "dc3545" --force

echo "✅ Labels created successfully"

# Sprint 1 Issues
echo ""
echo "🏃‍♂️ Creating Sprint 1 Issues (Foundation)"
echo "========================================="

# P0-S1-001: Authentication
echo "Creating P0-S1-001: Fix End-to-End Authentication Flow..."
gh issue create \
  --title "P0-S1-001: Fix End-to-End Authentication Flow" \
  --body "## User Story
As a user, I need to successfully authenticate so I can access the PyAirtable features.

## Current State
- Frontend login form exists but doesn't connect to backend
- Authentication service running on port 7007 but not properly integrated
- JWT token generation/validation not working end-to-end
- CORS issues preventing frontend-backend communication

## Acceptance Criteria
- [ ] Frontend login form connects to backend auth service on port 7007
- [ ] JWT tokens are properly generated and validated
- [ ] Session management working between frontend (port 5173) and backend
- [ ] Error handling for invalid credentials with user-friendly messages
- [ ] Protected routes redirect unauthenticated users to login
- [ ] Token refresh mechanism prevents session expiration
- [ ] CORS configuration allows frontend-backend communication

## Branch Name
\`fix/authentication-flow\`

## Story Points
8 (Complex integration between frontend and backend)

## Dependencies
- Platform services must be running and healthy
- Database connection for user storage
- Redis for session management" \
  --label "P0,sprint1,authentication" \
  --milestone "Sprint 1: Foundation"

# P0-S1-002: Testing Infrastructure
echo "Creating P0-S1-002: Establish Test Infrastructure..."
gh issue create \
  --title "P0-S1-002: Establish Test Infrastructure" \
  --body "## User Story
As a developer, I need a working test suite so I can ensure code quality and prevent regressions.

## Current State
- Test suite shows 0-8 out of 42 tests passing
- Multiple testing frameworks partially configured
- No consistent testing strategy across services
- CI/CD pipeline not running tests automatically

## Acceptance Criteria
- [ ] Unit test framework setup for all Python services (pytest)
- [ ] Frontend testing setup with React Testing Library/Vitest
- [ ] Integration tests for critical API endpoints
- [ ] E2E tests for authentication flow
- [ ] Test database isolation and cleanup
- [ ] CI/CD pipeline running tests automatically
- [ ] At least 50% of existing tests passing
- [ ] Test coverage reporting enabled

## Branch Name
\`feat/test-infrastructure\`

## Story Points
13 (Large effort involving multiple services and frameworks)

## Dependencies
- All services must be buildable and startable
- CI/CD pipeline access and configuration" \
  --label "P0,sprint1,testing" \
  --milestone "Sprint 1: Foundation"

# P0-S1-003: Observability Stack
echo "Creating P0-S1-003: Deploy Observability Stack..."
gh issue create \
  --title "P0-S1-003: Deploy Observability Stack" \
  --body "## User Story
As an operations team member, I need monitoring and logging so I can troubleshoot issues and monitor system health.

## Current State
- Observability stack is offline
- No centralized logging or metrics collection
- Service health monitoring not functional

## Acceptance Criteria
- [ ] Prometheus metrics collection for all 8 services
- [ ] Grafana dashboards showing service health and performance
- [ ] Loki log aggregation collecting logs from all services
- [ ] Jaeger distributed tracing for request flow visualization
- [ ] Health check endpoints implemented for all services
- [ ] Alert rules configured for critical failures

## Branch Name
\`feat/observability-stack\`

## Story Points
10 (Medium-high complexity with multiple monitoring tools)

## Dependencies
- All services must be running and accessible
- Docker compose configuration access" \
  --label "P0,sprint1,observability" \
  --milestone "Sprint 1: Foundation"

# P1-S1-004: Fix Failed Services
echo "Creating P1-S1-004: Fix Failed Services..."
gh issue create \
  --title "P1-S1-004: Fix Failed Services (Automation & SAGA)" \
  --body "## User Story
As a system administrator, I need all services running reliably so the application functions completely.

## Current State
- Automation services (port 7006) returning 'Service unavailable'
- SAGA orchestrator (port 7008) in continuous restart loop
- File processing and workflow automation not functional

## Acceptance Criteria
- [ ] Automation services health check passes
- [ ] SAGA orchestrator starts without restart loops
- [ ] File processing endpoints functional
- [ ] Workflow automation endpoints working
- [ ] Distributed transaction coordination active
- [ ] All services show 'healthy' in docker-compose ps

## Branch Name
\`fix/failed-services\`

## Story Points
8

## Dependencies
- Database and Redis services must be healthy" \
  --label "P1,sprint1,infrastructure" \
  --milestone "Sprint 1: Foundation"

# P1-S1-005: Database Schema
echo "Creating P1-S1-005: Database Schema Validation and Migration..."
gh issue create \
  --title "P1-S1-005: Database Schema Validation and Migration" \
  --body "## User Story
As a developer, I need a consistent database schema so all services can interact with data correctly.

## Acceptance Criteria
- [ ] Database migration scripts run successfully
- [ ] All services connect to database without errors
- [ ] Foreign key constraints properly implemented
- [ ] Indexes optimized for common queries
- [ ] Data validation rules enforced at database level
- [ ] Backup and restore procedures documented

## Branch Name
\`feat/database-schema-migration\`

## Story Points
5" \
  --label "P1,sprint1,infrastructure" \
  --milestone "Sprint 1: Foundation"

echo "✅ Sprint 1 issues created successfully"

# Sprint 2 Issues
echo ""
echo "🏃‍♂️ Creating Sprint 2 Issues (Core Features)"
echo "============================================"

# P0-S2-001: Airtable Integration
echo "Creating P0-S2-001: Core Airtable API Integration..."
gh issue create \
  --title "P0-S2-001: Core Airtable API Integration" \
  --body "## User Story
As a user, I need to connect to my Airtable bases so I can perform CRUD operations on my data.

## Acceptance Criteria
- [ ] Airtable authentication working with user tokens
- [ ] List bases functionality implemented
- [ ] List tables within a base working
- [ ] CRUD operations (Create, Read, Update, Delete) for records
- [ ] Proper error handling for API rate limits
- [ ] Field type validation and conversion
- [ ] Batch operations support

## Branch Name
\`feat/airtable-core-integration\`

## Story Points
13

## Dependencies
- Authentication flow must be working
- Airtable gateway service healthy" \
  --label "P0,sprint2,airtable" \
  --milestone "Sprint 2: Core Features"

# P0-S2-002: MCP Tools
echo "Creating P0-S2-002: MCP Server Tool Implementation..."
gh issue create \
  --title "P0-S2-002: MCP Server Tool Implementation" \
  --body "## User Story
As a user interacting with the chat interface, I need access to all 14 MCP tools so I can perform complex operations.

## Acceptance Criteria
- [ ] All 14 MCP tools functional and tested
- [ ] Tool descriptions and schemas properly defined
- [ ] Error handling for each tool
- [ ] Integration with LLM orchestrator
- [ ] Tool result formatting for chat interface
- [ ] Performance optimization for tool execution

## Branch Name
\`feat/mcp-tools-implementation\`

## Story Points
10" \
  --label "P0,sprint2,mcp" \
  --milestone "Sprint 2: Core Features"

# P0-S2-003: Chat Interface
echo "Creating P0-S2-003: Chat Interface Integration..."
gh issue create \
  --title "P0-S2-003: Chat Interface Integration" \
  --body "## User Story
As a user, I need a working chat interface so I can interact with my Airtable data through natural language.

## Acceptance Criteria
- [ ] Frontend chat UI connects to LLM orchestrator
- [ ] Messages sent and received correctly
- [ ] Real-time response streaming
- [ ] Chat history persistence
- [ ] Error message display
- [ ] Loading states and typing indicators
- [ ] File upload for data import

## Branch Name
\`feat/chat-interface-integration\`

## Story Points
8" \
  --label "P0,sprint2,frontend" \
  --milestone "Sprint 2: Core Features"

echo "✅ Sprint 2 issues created successfully"

# Sprint 3 Issues
echo ""
echo "🏃‍♂️ Creating Sprint 3 Issues (Production Ready)"
echo "==============================================="

# P0-S3-001: Performance
echo "Creating P0-S3-001: Performance Optimization..."
gh issue create \
  --title "P0-S3-001: Performance Optimization" \
  --body "## User Story
As a user, I need fast response times so I can work efficiently with my data.

## Acceptance Criteria
- [ ] API response times under 200ms for simple operations
- [ ] Frontend load times under 2 seconds
- [ ] Database query optimization implemented
- [ ] Caching strategy for frequently accessed data
- [ ] Lazy loading for large datasets
- [ ] Connection pooling optimized
- [ ] Performance monitoring dashboards

## Branch Name
\`perf/application-optimization\`

## Story Points
10" \
  --label "P0,sprint3,performance" \
  --milestone "Sprint 3: Production Ready"

# P0-S3-002: Security
echo "Creating P0-S3-002: Security Hardening..."
gh issue create \
  --title "P0-S3-002: Security Hardening" \
  --body "## User Story
As a security-conscious user, I need my data protected so I can trust the application with sensitive information.

## Acceptance Criteria
- [ ] Input sanitization and validation
- [ ] SQL injection prevention measures
- [ ] XSS protection implemented
- [ ] HTTPS enforced for all connections
- [ ] API rate limiting in place
- [ ] Secrets management secure
- [ ] Security headers configured
- [ ] Dependency vulnerability scanning

## Branch Name
\`security/hardening\`

## Story Points
8" \
  --label "P0,sprint3,security" \
  --milestone "Sprint 3: Production Ready"

# P0-S3-003: CI/CD Pipeline
echo "Creating P0-S3-003: Production Deployment Pipeline..."
gh issue create \
  --title "P0-S3-003: Production Deployment Pipeline" \
  --body "## User Story
As a DevOps engineer, I need automated deployment so I can release updates safely and efficiently.

## Acceptance Criteria
- [ ] Automated testing in CI pipeline
- [ ] Docker image building and versioning
- [ ] Staging environment deployment
- [ ] Production deployment with rollback capability
- [ ] Database migration automation
- [ ] Health checks before promoting deployments
- [ ] Blue-green deployment strategy

## Branch Name
\`ci-cd/production-pipeline\`

## Story Points
10" \
  --label "P0,sprint3,cicd" \
  --milestone "Sprint 3: Production Ready"

echo "✅ Sprint 3 issues created successfully"

echo ""
echo "🎉 All GitHub issues created successfully!"
echo "========================================"
echo ""
echo "📊 Summary:"
echo "- Sprint 1: 5 issues (Foundation)"
echo "- Sprint 2: 3 issues (Core Features)"  
echo "- Sprint 3: 3 issues (Production Ready)"
echo "- Total: 11 issues created"
echo ""
echo "🔗 Next steps:"
echo "1. Review issues in GitHub repository"
echo "2. Create milestones for each sprint"
echo "3. Assign issues to team members"
echo "4. Start Sprint 1 planning session"
echo ""
echo "📋 View issues: gh issue list"
echo "📝 Edit issue: gh issue edit [number]"